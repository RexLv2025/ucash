import 'dotenv/config';
import { db, setSetting, tx } from './db.js';
import { addMonthsClamped, buildDueDates, nowIso, parseDate, todayStr } from './lib/date.js';
import { buildSchedule } from './lib/money.js';
import { encryptPII, hashPassword, maskBankCard, maskIdCard, maskPhone } from './lib/security.js';
import { genInviteCode, genNo } from './lib/id.js';

const reset = process.argv.includes('--reset');

function shiftDays(dateStr: string, days: number): string {
  const d = parseDate(dateStr);
  d.setDate(d.getDate() + days);
  return todayStr(d);
}

function wipe() {
  const tables = [
    'idempotency_keys',
    'audit_logs',
    'messages',
    'invitations',
    'user_coupons',
    'repayments',
    'loan_schedules',
    'loans',
    'credit_applications',
    'risk_decisions',
    'kyc_records',
    'bank_cards',
    'user_profiles',
    'users',
    'risk_rules',
    'coupons',
    'admins',
    'settings',
  ];
  db.exec('PRAGMA foreign_keys = OFF');
  for (const t of tables) {
    try {
      db.prepare(`DELETE FROM ${t}`).run();
      db.prepare(`DELETE FROM sqlite_sequence WHERE name = ?`).run(t);
    } catch {
      /* ignore */
    }
  }
  db.exec('PRAGMA foreign_keys = ON');
}

function seedSettings() {
  setSetting('service_phone', '400-000-8888', '客服热线');
  setSetting('service_time', '09:00-21:00', '服务时间');
  setSetting('notice', '理性借贷，量力而行。综合年化利率 7.2%–24%，具体以审批结果为准。', '首页公告');
  setSetting('app_version', '2.4.0');
  setSetting('banners', [
    { id: 1, title: '邀请好友，最高得 200 元', subtitle: '好友完成首借即可到账', action: 'invite' },
    { id: 2, title: '完成认证，额度最高提至 5 万', subtitle: '公积金 / 信用卡账单认证', action: 'boost' },
  ]);
  setSetting('agreements', {
    loan: '《借款合同》',
    privacy: '《隐私政策》',
    personalInfo: '《个人信息授权书》',
    credit: '《征信授权书》',
  });
  setSetting('penalty_daily_bp', 5, '日罚息（万分之五）');
  setSetting('settle_penalty_bp', 0, '提前结清违约金比例（万分比）');
}

function seedAdmins() {
  const rows = [
    ['admin', 'Admin@123', '超级管理员', 'super'],
    ['approver', 'Approve@123', '审批员-李静', 'approver'],
    ['risk', 'Risk@123', '风控员-王涛', 'risk'],
    ['ops', 'Ops@123', '运营-陈晨', 'ops'],
  ];
  const now = nowIso();
  const stmt = db.prepare('INSERT INTO admins(username,password_hash,name,role,status,created_at) VALUES(?,?,?,?,?,?)');
  for (const [u, p, n, r] of rows) stmt.run(u, hashPassword(p), n, r, 'active', now);
}

function seedRules() {
  const now = nowIso();
  const rules: [string, string, string, string, string, string, number, number][] = [
    ['AGE_LIMIT', '年龄准入（22-55 周岁）', 'age', 'lt', '22', 'reject', 0, 10],
    ['AGE_LIMIT_MAX', '年龄准入上限（55 周岁）', 'age', 'gt', '55', 'reject', 0, 11],
    ['STUDENT', '在校学生禁入', 'isStudent', 'truthy', 'true', 'reject', 0, 12],
    ['BLACKLIST', '内部黑名单', 'blacklist', 'truthy', 'true', 'reject', 0, 5],
    ['ID_INVALID', '实名信息校验', 'idCardValid', 'neq', 'true', 'reject', 0, 13],
    ['FACE_LOW', '人脸相似度不足', 'faceScore', 'lt', '60', 'reject', 0, 14],
    ['OVERDUE_HISTORY', '历史逾期次数超限', 'overdueHistory', 'gte', '3', 'reject', 0, 20],
    ['MULTI_LOAN_HIGH', '多头借贷（≥8 家）', 'multiLoanCount', 'gte', '8', 'reject', 0, 21],
    ['MULTI_LOAN_MID', '多头借贷（5-7 家）转人工', 'multiLoanCount', 'gte', '5', 'manual', -30, 22],
    ['ACTIVE_LOAN_LIMIT', '在贷笔数上限', 'activeLoans', 'gte', '3', 'reject', 0, 23],
    ['INCOME_BONUS', '高收入加分', 'monthlyIncomeCents', 'gte', '1000000', 'score', 40, 60],
    ['DEVICE_RISK', '设备风险分', 'deviceRisk', 'gt', '70', 'reject', 0, 30],
  ];
  const stmt = db.prepare(
    `INSERT INTO risk_rules(code,name,field,operator,value,action,score_delta,priority,enabled,description,updated_at)
     VALUES(?,?,?,?,?,?,?,?,1,?,?)`
  );
  for (const [code, name, field, op, value, action, score, priority] of rules) {
    stmt.run(code, name, field, op, value, action, score, priority, name, now);
  }
}

function seedCoupons() {
  const now = nowIso();
  const from = shiftDays(todayStr(), -30);
  const to = shiftDays(todayStr(), 180);
  const stmt = db.prepare(
    `INSERT INTO coupons(code,name,type,amount_cents,rate_off_bp,min_amount_cents,term_limit,total_qty,status,valid_from,valid_to,created_at)
     VALUES(?,?,?,?,?,?,?,?, 'active', ?,?,?)`
  );
  stmt.run('NEW20', '新客立减 20 元', 'cash', 2000, 0, 100000, 0, 9999, from, to, now);
  stmt.run('RATE01', '首借降息 1%', 'rate', 0, 100, 0, 0, 9999, from, to, now);
  stmt.run('SUMMER50', '夏日专享 50 元券', 'cash', 5000, 0, 500000, 12, 500, from, to, now);
}

function createUser(opts: {
  phone: string;
  name?: string;
  idCard?: string;
  verified?: boolean;
  credit?: { limitCents: number; rateBp: number; status: string; score: number; applyAmountCents: number };
  inviteCode?: string;
}) {
  const now = nowIso();
  const id = tx(() => {
    const info = db
      .prepare(
        `INSERT INTO users(phone,name,id_card_enc,id_card_mask,invite_code,status,credit_limit_cents,risk_level,created_at,updated_at,last_login_at)
         VALUES(?,?,?,?,?,'active',?,?,?,?,?)`
      )
      .run(
        opts.phone,
        opts.name ?? null,
        opts.idCard ? encryptPII(opts.idCard) : null,
        opts.idCard ? maskIdCard(opts.idCard) : null,
        opts.inviteCode ?? genInviteCode(),
        opts.credit?.limitCents ?? 0,
        opts.credit ? 'B' : 'NR',
        now,
        now,
        now
      );
    const uid = Number(info.lastInsertRowid);
    db.prepare(
      `INSERT INTO user_profiles(user_id, gender, birth_year, city, occupation, company, monthly_income_cents,
        contact1_name, contact1_phone, contact2_name, contact2_phone,
        realname_verified, face_verified, contacts_verified, fund_verified, updated_at)
       VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
    ).run(
      uid,
      opts.verified ? 'male' : null,
      opts.verified ? 1990 : null,
      opts.verified ? '深圳' : null,
      opts.verified ? '互联网/产品' : null,
      opts.verified ? '深圳某某科技有限公司' : null,
      opts.verified ? 1800000 : null,
      opts.verified ? '李强' : null,
      opts.verified ? '13911112222' : null,
      opts.verified ? '王芳' : null,
      opts.verified ? '13822223333' : null,
      opts.verified ? 1 : 0,
      opts.verified ? 1 : 0,
      opts.verified ? 1 : 0,
      opts.verified ? 1 : 0,
      now
    );
    db.prepare(
      `INSERT INTO bank_cards(user_id, bank_name, bank_code, card_no_enc, card_no_mask, holder_name, phone, is_default, status, created_at)
       VALUES(?,?,?,?,?,?,?,1,'active',?)`
    ).run(
      uid,
      '招商银行',
      'CMB',
      encryptPII(`622588${String(2000000000000 + uid).slice(-13)}`),
      maskBankCard(`622588${String(2000000000000 + uid).slice(-13)}`),
      opts.name ?? null,
      opts.phone,
      now
    );
    db.prepare(`INSERT INTO user_coupons(user_id, coupon_id, status, received_at) SELECT ?, id, 'unused', ? FROM coupons WHERE code IN ('NEW20','RATE01')`).run(uid, now);
    if (opts.credit) {
      db.prepare(
        `INSERT INTO credit_applications(user_id, apply_amount_cents, purpose, status, decision, score, approved_limit_cents, interest_rate_bp, expires_at, risk_snapshot, created_at, updated_at)
         VALUES(?,?,?,?,?,?,?,?,?,?,?,?)`
      ).run(
        uid,
        opts.credit.applyAmountCents,
        '日常消费',
        opts.credit.status,
        opts.credit.status === 'approved' ? 'approve' : opts.credit.status === 'manual' ? 'manual' : 'reject',
        opts.credit.score,
        opts.credit.status === 'rejected' ? null : opts.credit.limitCents,
        opts.credit.rateBp,
        opts.credit.status === 'rejected' ? null : addMonthsClamped(todayStr(), 12),
        JSON.stringify({ score: opts.credit.score, hitRules: [], snapshot: {} }),
        now,
        now
      );
    }
    return uid;
  });
  return id;
}

function addLoan(opts: {
  userId: number;
  principalCents: number;
  termMonths: number;
  rateBp: number;
  monthsAgo: number;
  paidPeriods: number;
  status: 'active' | 'settled' | 'failed' | 'overdue';
  overdueDays?: number;
}) {
  const today = todayStr();
  const disbursedDate =
    opts.overdueDays && opts.overdueDays > 0
      ? shiftDays(addMonthsClamped(today, -opts.monthsAgo), -opts.overdueDays)
      : addMonthsClamped(today, -opts.monthsAgo);
  const base = buildSchedule(opts.principalCents, opts.rateBp, opts.termMonths);
  const dueDates = buildDueDates(disbursedDate, opts.termMonths);
  const loanNo = genNo('UC');
  const now = nowIso();
  const apr = Math.round(((Math.pow(1 + opts.rateBp / 10000 / 12, 12) - 1) * 10000));

  const loanId = tx(() => {
    const info = db
      .prepare(
        `INSERT INTO loans(loan_no,user_id,principal_cents,term_months,interest_rate_bp,apr_bp,total_interest_cents,
          total_repay_cents,monthly_payment_cents,bank_card_id,purpose,status,fail_code,fail_reason,contract_no,signed_at,
          disbursed_at,first_due_date,overdue_days,created_at,updated_at)
         VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        loanNo,
        opts.userId,
        opts.principalCents,
        opts.termMonths,
        opts.rateBp,
        apr,
        base.totalInterestCents,
        base.totalRepayCents,
        base.monthlyPaymentCents,
        1,
        '日常消费',
        opts.status === 'failed' ? 'failed' : opts.status,
        opts.status === 'failed' ? 'E1024' : null,
        opts.status === 'failed' ? '银行卡状态异常（E1024）' : null,
        `HT${loanNo}`,
        shiftDays(disbursedDate, -0),
        opts.status === 'failed' ? null : now,
        dueDates[0],
        opts.overdueDays ?? 0,
        now,
        now
      );
    const lid = Number(info.lastInsertRowid);

    if (opts.status !== 'failed') {
      const stmt = db.prepare(
        `INSERT INTO loan_schedules(loan_id,period_no,due_date,principal_cents,interest_cents,total_cents,
          paid_principal_cents,paid_interest_cents,penalty_cents,status,paid_at)
         VALUES(?,?,?,?,?,?,?,?,?,?,?)`
      );
      base.items.forEach((it, idx) => {
        const paid = idx < opts.paidPeriods;
        const isOverdue = !paid && opts.status === 'overdue' && idx === opts.paidPeriods;
        const penalty = isOverdue
          ? Math.round(((it.principalCents + it.interestCents) * 5 * (opts.overdueDays ?? 0)) / 10000)
          : 0;
        stmt.run(
          lid,
          it.periodNo,
          dueDates[idx],
          it.principalCents,
          it.interestCents,
          it.totalCents,
          paid ? it.principalCents : 0,
          paid ? it.interestCents : 0,
          penalty,
          paid ? 'paid' : isOverdue ? 'overdue' : 'unpaid',
          paid ? shiftDays(dueDates[idx], -2) : null
        );
      });

      const paidPrincipal = base.items.slice(0, opts.paidPeriods).reduce((s, x) => s + x.principalCents, 0);
      db.prepare('UPDATE users SET used_limit_cents = used_limit_cents + ? WHERE id = ?').run(
        opts.status === 'settled' ? 0 : opts.principalCents - paidPrincipal,
        opts.userId
      );

      // 还款流水
      for (let i = 0; i < opts.paidPeriods; i++) {
        const it = base.items[i];
        db.prepare(
          `INSERT INTO repayments(repayment_no,user_id,loan_id,type,amount_cents,principal_cents,interest_cents,penalty_cents,channel,bank_card_id,status,paid_at,created_at)
           VALUES(?,?,?,'normal',?,?,?,0,'bankcard',1,'success',?,?)`
        ).run(genNo('RP'), opts.userId, lid, it.totalCents, it.principalCents, it.interestCents, shiftDays(dueDates[i], -2), shiftDays(dueDates[i], -2));
      }

      db.prepare(
        `INSERT INTO messages(user_id,type,title,content,biz_no,created_at) VALUES(?,?,?,?,?,?)`
      ).run(
        opts.userId,
        'loan',
        '放款成功',
        `您的借款 ¥${(opts.principalCents / 100).toFixed(2)} 已放款至招商银行卡，首期还款日 ${dueDates[0]}。`,
        loanNo,
        now
      );
    } else {
      db.prepare(`INSERT INTO messages(user_id,type,title,content,biz_no,created_at) VALUES(?,?,?,?,?,?)`).run(
        opts.userId,
        'loan',
        '放款失败',
        '您的借款放款失败（E1024 银行卡状态异常），请更换银行卡后重试。',
        loanNo,
        now
      );
    }
    return lid;
  });
  return loanId;
}

function main() {
  if (reset) {
    // eslint-disable-next-line no-console
    console.log('重置数据库…');
    wipe();
  }
  const existing = (db.prepare('SELECT COUNT(*) c FROM admins').get() as any).c;
  if (existing > 0) {
    // eslint-disable-next-line no-console
    console.log('已存在数据，如需重置请执行 npm run reset');
    return;
  }

  seedSettings();
  seedAdmins();
  seedRules();
  seedCoupons();

  // 演示用户 A：完整资质 + 在贷逾期
  const ua = createUser({
    phone: '13800138000',
    name: '张明',
    idCard: '440305199003078214',
    verified: true,
    credit: { limitCents: 20000_00, rateBp: 1660, status: 'approved', score: 726, applyAmountCents: 20000_00 },
  });
  addLoan({ userId: ua, principalCents: 8000_00, termMonths: 12, rateBp: 1660, monthsAgo: 3, paidPeriods: 2, status: 'overdue', overdueDays: 10 });
  addLoan({ userId: ua, principalCents: 3000_00, termMonths: 3, rateBp: 1660, monthsAgo: 6, paidPeriods: 3, status: 'settled' });
  addLoan({ userId: ua, principalCents: 2000_00, termMonths: 3, rateBp: 1660, monthsAgo: 0, paidPeriods: 0, status: 'failed' });

  // 演示用户 B：待人工审批
  const ub = createUser({
    phone: '13700137000',
    name: '李婷',
    idCard: '440305199512126628',
    verified: true,
    credit: { limitCents: 8000_00, rateBp: 2160, status: 'manual', score: 688, applyAmountCents: 8000_00 },
  });
  db.prepare(`UPDATE user_profiles SET fund_verified = 0 WHERE user_id = ?`).run(ub);

  // 演示用户 C：新用户（未实名）
  createUser({ phone: '13900139000' });

  // 消息
  const now = nowIso();
  db.prepare(`INSERT INTO messages(user_id,type,title,content,created_at) VALUES(?,?,?,?,?)`).run(
    ua,
    'system',
    '理性借贷提醒',
    '请根据自身还款能力合理借款，避免过度负债。如遇还款困难，请及时联系客服协商。',
    now
  );
  db.prepare(`INSERT INTO messages(user_id,type,title,content,created_at) VALUES(?,?,?,?,?)`).run(
    ua,
    'repay',
    '还款提醒',
    '您有一笔账单已逾期，请尽快处理以免影响信用记录。',
    now
  );

  // eslint-disable-next-line no-console
  console.log('');
  // eslint-disable-next-line no-console
  console.log('种子数据已生成：');
  // eslint-disable-next-line no-console
  console.log('  借款人 A（在贷+逾期）: 13800138000  验证码 123456');
  // eslint-disable-next-line no-console
  console.log('  借款人 B（待人工审批）: 13700137000  验证码 123456');
  // eslint-disable-next-line no-console
  console.log('  借款人 C（新用户）    : 13900139000  验证码 123456');
  // eslint-disable-next-line no-console
  console.log('  后台: admin / Admin@123   审批: approver / Approve@123');
  // eslint-disable-next-line no-console
  console.log(`  当前时间: ${todayStr()}`);
}

main();
