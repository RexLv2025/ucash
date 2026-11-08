import { db, tx } from '../db.js';
import { ApiError, ErrCode } from '../lib/http.js';
import { nowIso, todayStr, addMonthsClamped } from '../lib/date.js';
import { evaluateRisk, limitModel, rateModel } from './risk.js';
import { notify } from './notify.js';

const RATE_MIN_BP = 600;
const RATE_MAX_BP = 2160;

export function assertVerified(userId: number) {
  const p = db.prepare('SELECT * FROM user_profiles WHERE user_id = ?').get(userId) as any;
  if (!p?.realname_verified) throw new ApiError(ErrCode.NOT_VERIFIED, '请先完成实名认证');
  if (!p?.face_verified) throw new ApiError(ErrCode.FACE_FAILED, '请先完成人脸识别');
  if (!p?.contacts_verified) throw new ApiError(ErrCode.CONTACT_REQUIRED, '请先完成紧急联系人授权');
  return p;
}

export function currentCredit(userId: number) {
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId) as any;
  const app = db
    .prepare(`SELECT * FROM credit_applications WHERE user_id = ? ORDER BY id DESC LIMIT 1`)
    .get(userId) as any;
  const active = db
    .prepare(`SELECT * FROM credit_applications WHERE user_id = ? AND status = 'approved' ORDER BY id DESC LIMIT 1`)
    .get(userId) as any;
  const expired = active?.expires_at ? active.expires_at < todayStr() : false;
  return {
    totalLimitCents: user.credit_limit_cents,
    usedLimitCents: user.used_limit_cents,
    frozenLimitCents: user.frozen_limit_cents,
    availableLimitCents: Math.max(0, user.credit_limit_cents - user.used_limit_cents - user.frozen_limit_cents),
    status: active ? (expired ? 'expired' : 'approved') : app?.status === 'rejected' ? 'rejected' : app?.status === 'manual' ? 'manual' : 'none',
    application: app ?? null,
    interestRateBp: active?.interest_rate_bp ?? null,
    expiresAt: active?.expires_at ?? null,
    rejectedAt: app?.status === 'rejected' ? app.created_at : null,
    rejectCode: app?.status === 'rejected' ? app.reject_code : null,
    rejectReason: app?.status === 'rejected' ? app.reject_reason : null,
  };
}

export interface CreditSubmitInput {
  amountCents: number;
  purpose?: string;
}

export function submitCredit(userId: number, input: CreditSubmitInput) {
  assertVerified(userId);
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId) as any;
  if (user.status !== 'active') throw new ApiError(ErrCode.ACCOUNT_FROZEN);

  const pending = db
    .prepare(`SELECT * FROM credit_applications WHERE user_id = ? AND status IN ('submitted','reviewing','manual') ORDER BY id DESC LIMIT 1`)
    .get(userId) as any;
  if (pending) throw new ApiError(ErrCode.CREDIT_REVIEWING, '授信申请审核中，请稍候');

  const approved = db
    .prepare(`SELECT * FROM credit_applications WHERE user_id = ? AND status = 'approved' ORDER BY id DESC LIMIT 1`)
    .get(userId) as any;
  if (approved && (!approved.expires_at || approved.expires_at >= todayStr())) {
    return { applicationId: approved.id, status: 'approved', replayed: true };
  }

  const risk = evaluateRisk(userId, 'credit', input.amountCents);
  const now = nowIso();
  const expiresAt = addMonthsClamped(todayStr(), 12);

  const id = tx(() => {
    const status = risk.decision === 'reject' ? 'rejected' : risk.decision === 'manual' ? 'manual' : 'approved';
    const info = db
      .prepare(
        `INSERT INTO credit_applications
         (user_id, apply_amount_cents, purpose, status, decision, score, approved_limit_cents, interest_rate_bp,
          reject_code, reject_reason, risk_snapshot, expires_at, created_at, updated_at)
         VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        userId,
        input.amountCents,
        input.purpose ?? null,
        status,
        risk.decision,
        risk.score,
        risk.decision === 'reject' ? null : risk.suggestedLimitCents,
        risk.decision === 'reject' ? null : risk.suggestedRateBp,
        risk.rejectCode ?? null,
        risk.rejectReason ?? null,
        JSON.stringify({ score: risk.score, hitRules: risk.hitRules, snapshot: risk.snapshot }),
        risk.decision === 'reject' ? null : expiresAt,
        now,
        now
      );
    const appId = Number(info.lastInsertRowid);

    if (status === 'approved') {
      db.prepare('UPDATE users SET credit_limit_cents = ?, risk_level = ?, updated_at = ? WHERE id = ?').run(
        risk.suggestedLimitCents,
        risk.score >= 740 ? 'A' : risk.score >= 660 ? 'B' : 'C',
        now,
        userId
      );
      notify(
        userId,
        'risk',
        '额度已激活',
        `恭喜，您的可用额度为 ¥${(risk.suggestedLimitCents / 100).toFixed(2)}，年化利率 ${(risk.suggestedRateBp / 100).toFixed(2)}% 起，额度有效期 12 个月。`,
        `CR${appId}`
      );
    } else if (status === 'rejected') {
      notify(userId, 'risk', '授信申请结果', risk.rejectReason || '综合评估未通过，建议 3 个月后重试。', `CR${appId}`);
    }
    db.prepare(
      `INSERT INTO risk_decisions(user_id, scene, application_id, score, decision, hit_rules, snapshot, created_at)
       VALUES(?,?,?,?,?,?,?,?)`
    ).run(userId, 'credit', appId, risk.score, risk.decision, JSON.stringify(risk.hitRules), JSON.stringify(risk.snapshot), now);

    return appId;
  });

  return { applicationId: id, status: risk.decision, risk };
}

/** 认证项补全后重新评估额度（只升不降） */
export function refreshLimit(userId: number): { before: number; after: number } {
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId) as any;
  const app = db
    .prepare(`SELECT * FROM credit_applications WHERE user_id = ? AND status = 'approved' ORDER BY id DESC LIMIT 1`)
    .get(userId) as any;
  if (!app) return { before: user.credit_limit_cents, after: user.credit_limit_cents };

  const risk = evaluateRisk(userId, 'credit', app.apply_amount_cents);
  const newLimit = limitModel(risk.snapshot, risk.score);
  const newRate = rateModel(risk.snapshot, risk.score);
  const finalLimit = Math.max(user.credit_limit_cents, newLimit);
  const finalRate = Math.min(app.interest_rate_bp ?? RATE_MAX_BP, newRate);
  if (finalLimit === user.credit_limit_cents && finalRate === app.interest_rate_bp) {
    return { before: user.credit_limit_cents, after: user.credit_limit_cents };
  }
  db.prepare('UPDATE users SET credit_limit_cents = ?, updated_at = ? WHERE id = ?').run(finalLimit, nowIso(), userId);
  db.prepare('UPDATE credit_applications SET approved_limit_cents = ?, interest_rate_bp = ?, updated_at = ? WHERE id = ?').run(
    finalLimit,
    finalRate,
    nowIso(),
    app.id
  );
  if (finalLimit > user.credit_limit_cents) {
    notify(userId, 'risk', '额度提升成功', `您的额度已提升至 ¥${(finalLimit / 100).toFixed(2)}。`, `CR${app.id}`);
  }
  return { before: user.credit_limit_cents, after: finalLimit };
}

/** 后台人工审批 */
export function reviewCredit(adminId: number, applicationId: number, pass: boolean, limitCents?: number, rateBp?: number, reason?: string) {
  const app = db.prepare('SELECT * FROM credit_applications WHERE id = ?').get(applicationId) as any;
  if (!app) throw new ApiError(ErrCode.NOT_FOUND, '授信申请不存在');
  if (!['manual', 'submitted', 'reviewing'].includes(app.status)) throw new ApiError(ErrCode.CONFLICT, '该申请不在待审状态');

  const now = nowIso();
  if (pass) {
    const finalLimit = Math.min(50000_00, Math.max(1000_00, limitCents ?? app.approved_limit_cents ?? 5000_00));
    const finalRate = Math.min(RATE_MAX_BP, Math.max(RATE_MIN_BP, rateBp ?? app.interest_rate_bp ?? 1800));
    tx(() => {
      db.prepare(
        `UPDATE credit_applications SET status='approved', decision='approve', approved_limit_cents=?, interest_rate_bp=?,
         reviewer_id=?, reviewed_at=?, expires_at=?, updated_at=? WHERE id=?`
      ).run(finalLimit, finalRate, adminId, now, addMonthsClamped(todayStr(), 12), now, applicationId);
      db.prepare('UPDATE users SET credit_limit_cents=?, updated_at=? WHERE id=?').run(finalLimit, now, app.user_id);
      notify(
        app.user_id,
        'risk',
        '额度已激活',
        `恭喜，您的可用额度为 ¥${(finalLimit / 100).toFixed(2)}，年化利率 ${(finalRate / 100).toFixed(2)}% 起。`,
        `CR${applicationId}`
      );
    });
  } else {
    tx(() => {
      db.prepare(
        `UPDATE credit_applications SET status='rejected', decision='reject', reject_code=?, reject_reason=?, reviewer_id=?, reviewed_at=?, updated_at=? WHERE id=?`
      ).run('MANUAL_REJECT', reason || '人工审核未通过', adminId, now, now, applicationId);
      notify(app.user_id, 'risk', '授信申请结果', reason || '综合评估未通过，建议 3 个月后重试。', `CR${applicationId}`);
    });
  }
  return { applicationId, status: pass ? 'approved' : 'rejected' };
}
