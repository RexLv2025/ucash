import { db } from '../db.js';
import { ApiError, ErrCode } from '../lib/http.js';
import { nowIso } from '../lib/date.js';

export interface RiskSnapshot {
  age: number;
  idCardValid: boolean;
  faceScore: number;
  hasContact: boolean;
  blacklist: boolean;
  isStudent: boolean;
  overdueHistory: number;
  multiLoanCount: number;
  deviceRisk: number;
  monthlyIncomeCents: number;
  fundVerified: boolean;
  providerVerified: boolean;
  cardbillVerified: boolean;
  activeLoans: number;
  requestingAmountCents: number;
  hour: number;
}

export interface HitRule {
  code: string;
  name: string;
  action: string;
  field: string;
  actual: unknown;
  expected: string;
  scoreDelta: number;
}

export interface RiskResult {
  score: number;
  decision: 'approve' | 'reject' | 'manual';
  hitRules: HitRule[];
  rejectCode?: string;
  rejectReason?: string;
  snapshot: RiskSnapshot;
  suggestedLimitCents: number;
  suggestedRateBp: number;
}

const BASE_SCORE = 560;

/** 评分卡：基础分 + 资质加分 − 风险减分，输出 300-850 */
function scoreCard(s: RiskSnapshot): number {
  let score = BASE_SCORE;
  if (s.idCardValid) score += 30;
  if (s.faceScore >= 80) score += 25;
  else if (s.faceScore >= 60) score += 10;
  if (s.hasContact) score += 20;
  if (s.monthlyIncomeCents >= 2000000) score += 110;
  else if (s.monthlyIncomeCents >= 1000000) score += 80;
  else if (s.monthlyIncomeCents >= 500000) score += 50;
  else if (s.monthlyIncomeCents > 0) score += 25;
  if (s.fundVerified) score += 50;
  if (s.providerVerified) score += 25;
  if (s.cardbillVerified) score += 35;
  if (s.age >= 31 && s.age <= 45) score += 20;
  if (s.monthlyIncomeCents >= 1000000) score += 15;
  score -= s.overdueHistory * 55;
  if (s.multiLoanCount >= 5) score -= 80;
  else if (s.multiLoanCount >= 3) score -= 40;
  if (s.deviceRisk > 70) score -= 60;
  else if (s.deviceRisk > 40) score -= 20;
  if (s.activeLoans >= 3) score -= 30;
  return Math.max(300, Math.min(850, Math.round(score)));
}

/** 额度模型：收入档位 + 认证项加成，封顶 5 万，向下取整到 500 */
export function limitModel(s: RiskSnapshot, score: number): number {
  let limit = 3000_00;
  if (s.monthlyIncomeCents >= 2000000) limit = 15000_00;
  else if (s.monthlyIncomeCents >= 1000000) limit = 10000_00;
  else if (s.monthlyIncomeCents >= 500000) limit = 6000_00;

  if (s.idCardValid) limit += 1000_00;
  if (s.faceScore >= 80) limit += 1000_00;
  if (s.hasContact) limit += 1000_00;
  if (s.fundVerified) limit += 5000_00;
  if (s.providerVerified) limit += 3000_00;
  if (s.cardbillVerified) limit += 3000_00;

  let coefficient = 1;
  if (score >= 780) coefficient = 1.4;
  else if (score >= 740) coefficient = 1.25;
  else if (score >= 700) coefficient = 1.1;
  else if (score >= 660) coefficient = 0.9;
  else coefficient = 0.7;

  limit = Math.floor((limit * coefficient) / 50000) * 50000; // 500 元整数倍
  return Math.max(1000_00, Math.min(50000_00, limit));
}

/** 定价模型：评分 → 合同年利率（基点）；资质项可降息，下限 9% */
export function rateModel(s: RiskSnapshot, score: number): number {
  let rate: number;
  if (score >= 780) rate = 1080;
  else if (score >= 740) rate = 1440;
  else if (score >= 700) rate = 1800;
  else if (score >= 660) rate = 2040;
  else rate = 2160;
  if (s.fundVerified) rate -= 120;
  if (s.cardbillVerified) rate -= 80;
  if (s.providerVerified) rate -= 40;
  if (s.multiLoanCount >= 5) rate += 120;
  return Math.max(900, Math.min(2160, rate));
}

function matchRule(actual: unknown, operator: string, expectedRaw: string): boolean {
  let expected: any = expectedRaw;
  try {
    expected = JSON.parse(expectedRaw);
  } catch {
    /* 保持字符串 */
  }
  switch (operator) {
    case 'gte':
      return Number(actual) >= Number(expected);
    case 'gt':
      return Number(actual) > Number(expected);
    case 'lte':
      return Number(actual) <= Number(expected);
    case 'lt':
      return Number(actual) < Number(expected);
    case 'eq':
      return String(actual) === String(expected);
    case 'neq':
      return String(actual) !== String(expected);
    case 'in':
      return Array.isArray(expected) && expected.map(String).includes(String(actual));
    case 'not_in':
      return Array.isArray(expected) && !expected.map(String).includes(String(actual));
    case 'truthy':
      return Boolean(actual);
    default:
      return false;
  }
}

const REJECT_TEXT: Record<string, string> = {
  AGE_LIMIT: '年龄不符合准入要求（22-55 周岁）',
  STUDENT: '暂不支持向在校学生提供服务',
  BLACKLIST: '综合评估未通过，暂无法提供服务',
  ID_INVALID: '身份信息校验未通过',
  FACE_LOW: '人脸识别未通过',
  OVERDUE_HISTORY: '历史逾期记录较多，暂不符合准入条件',
  MULTI_LOAN: '多头借贷风险较高，暂不符合准入条件',
  SCORE_LOW: '综合评分不足，建议 3 个月后重试',
  NO_INCOME: '收入信息不足，请补充资料',
};

export function buildSnapshot(userId: number, requestingAmountCents: number): RiskSnapshot {
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId) as any;
  const profile = db.prepare('SELECT * FROM user_profiles WHERE user_id = ?').get(userId) as any;
  const kyc = db.prepare('SELECT * FROM kyc_records WHERE user_id = ? ORDER BY id DESC LIMIT 1').get(userId) as any;
  const activeLoans = (db.prepare(`SELECT COUNT(*) c FROM loans WHERE user_id = ? AND status IN ('active','overdue')`).get(userId) as any).c;
  const overdueHistory = (db.prepare(`SELECT COUNT(*) c FROM loans WHERE user_id = ? AND overdue_days > 0`).get(userId) as any).c;
  const multiLoanCount = (db.prepare(`SELECT COUNT(*) c FROM credit_applications WHERE user_id = ? AND created_at >= datetime('now','-90 day')`).get(userId) as any).c + 1;

  const birthYear = profile?.birth_year || (kyc ? 1990 : 1990);
  const age = new Date().getFullYear() - birthYear;

  return {
    age,
    idCardValid: Boolean(profile?.realname_verified),
    faceScore: kyc?.face_score ?? 0,
    hasContact: Boolean(profile?.contact1_phone && profile?.contact2_phone),
    blacklist: Boolean(user?.blacklist),
    isStudent: String(profile?.occupation || '').includes('学生'),
    overdueHistory,
    multiLoanCount,
    deviceRisk: 20,
    monthlyIncomeCents: profile?.monthly_income_cents || 0,
    fundVerified: Boolean(profile?.fund_verified),
    providerVerified: Boolean(profile?.provider_verified),
    cardbillVerified: Boolean(profile?.cardbill_verified),
    activeLoans,
    requestingAmountCents,
    hour: new Date().getHours(),
  };
}

export function evaluateRisk(userId: number, scene: 'credit' | 'loan', requestingAmountCents = 0): RiskResult {
  const snapshot = buildSnapshot(userId, requestingAmountCents);
  const rules = db.prepare('SELECT * FROM risk_rules WHERE enabled = 1 ORDER BY priority ASC').all() as any[];

  const hitRules: HitRule[] = [];
  let scoreDelta = 0;
  let forcedReject: HitRule | null = null;
  let needManual = false;

  for (const rule of rules) {
    const actual = (snapshot as any)[rule.field];
    if (actual === undefined) continue;
    if (!matchRule(actual, rule.operator, rule.value)) continue;
    const hit: HitRule = {
      code: rule.code,
      name: rule.name,
      action: rule.action,
      field: rule.field,
      actual,
      expected: `${rule.operator} ${rule.value}`,
      scoreDelta: rule.score_delta,
    };
    hitRules.push(hit);
    if (rule.action === 'score') scoreDelta += rule.score_delta;
    if (rule.action === 'manual') needManual = true;
    if (rule.action === 'reject' && !forcedReject) forcedReject = hit;
  }

  const score = Math.max(300, Math.min(850, scoreCard(snapshot) + scoreDelta));

  let decision: RiskResult['decision'] = 'approve';
  let rejectCode: string | undefined;
  let rejectReason: string | undefined;

  if (forcedReject) {
    decision = 'reject';
    rejectCode = forcedReject.code;
    rejectReason = REJECT_TEXT[forcedReject.code] || '综合评估未通过';
  } else if (score < 600) {
    decision = 'reject';
    rejectCode = 'SCORE_LOW';
    rejectReason = REJECT_TEXT.SCORE_LOW;
  } else if (needManual && scene === 'credit') {
    decision = 'manual';
  }

  const suggestedLimitCents = decision === 'reject' ? 0 : limitModel(snapshot, score);
  const suggestedRateBp = rateModel(snapshot, score);

  db.prepare(
    `INSERT INTO risk_decisions(user_id, scene, score, decision, hit_rules, snapshot, created_at)
     VALUES(?,?,?,?,?,?,?)`
  ).run(userId, scene, score, decision, JSON.stringify(hitRules), JSON.stringify(snapshot), nowIso());

  return { score, decision, hitRules, rejectCode, rejectReason, snapshot, suggestedLimitCents, suggestedRateBp };
}

/** 用信风控：借款时的二次校验 */
export function assertLoanRisk(userId: number, amountCents: number) {
  const s = buildSnapshot(userId, amountCents);
  if (s.blacklist) throw new ApiError(ErrCode.DISBURSE_RISK, '综合评估未通过，暂无法借款');
  if (s.activeLoans >= 3) throw new ApiError(ErrCode.CONFLICT, '当前在贷笔数已达上限（3 笔）');
  const overdue = db.prepare(`SELECT COUNT(*) c FROM loans WHERE user_id = ? AND status = 'overdue'`).get(userId) as any;
  if (overdue.c > 0) throw new ApiError(ErrCode.CONFLICT, '存在逾期借款，请先结清后再申请');
  const result = evaluateRisk(userId, 'loan', amountCents);
  if (result.decision === 'reject') throw new ApiError(ErrCode.DISBURSE_RISK, result.rejectReason || '综合评估未通过');
  return result;
}
