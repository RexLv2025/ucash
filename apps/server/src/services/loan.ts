import jwt from 'jsonwebtoken';
import { db, tx } from '../db.js';
import { ApiError, ErrCode } from '../lib/http.js';
import { addMonthsClamped, buildDueDates, nowIso, todayDateStr, todayStr } from '../lib/date.js';
import { buildSchedule, irrAnnualBp } from '../lib/money.js';
import { genNo } from '../lib/id.js';
import { assertLoanRisk } from './risk.js';
import { currentCredit } from './credit.js';
import { notify } from './notify.js';

const SECRET = process.env.JWT_SECRET || 'ucash-dev-jwt-secret-2026';
export const MIN_AMOUNT = 500_00;
export const MAX_AMOUNT = 50000_00;
export const TERMS = [3, 6, 12];
const SETTLE_PENALTY_BP = 0; // 提前结清违约金（万分比），0 = 免收

export interface QuoteInput {
  amountCents: number;
  termMonths: number;
  couponId?: number | null;
}

/** 现金券：从末期往前抵扣利息，返回实际抵扣金额 */
export function applyCashDiscount(items: { interestCents: number; principalCents: number; totalCents: number }[], discount: number): number {
  let left = Math.max(0, discount);
  const granted = left;
  for (let i = items.length - 1; i >= 0 && left > 0; i--) {
    const cut = Math.min(items[i].interestCents, left);
    items[i].interestCents -= cut;
    items[i].totalCents = items[i].principalCents + items[i].interestCents;
    left -= cut;
  }
  return granted - left;
}

function loadCoupon(userId: number, couponId?: number | null) {  if (!couponId) return null;
  const row = db
    .prepare(
      `SELECT uc.id AS user_coupon_id, uc.status AS uc_status, c.* FROM user_coupons uc
       JOIN coupons c ON c.id = uc.coupon_id WHERE uc.user_id = ? AND uc.coupon_id = ?`
    )
    .get(userId, couponId) as any;
  if (!row) throw new ApiError(ErrCode.COUPON_INVALID, '优惠券不存在');
  if (row.uc_status !== 'unused') throw new ApiError(ErrCode.COUPON_INVALID, '优惠券已使用或已失效');
  if (row.status !== 'active') throw new ApiError(ErrCode.COUPON_INVALID, '优惠券已停用');
  const now = todayDateStr();
  if (now < row.valid_from || now > row.valid_to) throw new ApiError(ErrCode.COUPON_INVALID, '优惠券不在有效期内');
  return row;
}

export function quote(userId: number, input: QuoteInput) {
  if (!Number.isInteger(input.amountCents) || input.amountCents < MIN_AMOUNT || input.amountCents > MAX_AMOUNT) {
    throw new ApiError(ErrCode.LOAN_AMOUNT, `借款金额需在 ${MIN_AMOUNT / 100} - ${MAX_AMOUNT / 100} 元之间`);
  }
  if (!TERMS.includes(input.termMonths)) throw new ApiError(ErrCode.LOAN_TERM, `仅支持 ${TERMS.join('/')} 期`);
  if (input.amountCents % 10000 !== 0) throw new ApiError(ErrCode.LOAN_AMOUNT, '借款金额需为 100 元的整数倍');

  const credit = currentCredit(userId);
  if (credit.status === 'expired') throw new ApiError(ErrCode.CREDIT_EXPIRED, '授信已过期，请重新申请');
  if (credit.status !== 'approved') throw new ApiError(ErrCode.NO_CREDIT, '暂无可用额度，请先申请授信');
  if (input.amountCents > credit.availableLimitCents) {
    throw new ApiError(ErrCode.CREDIT_INSUFFICIENT, `可用额度不足，当前可用 ¥${(credit.availableLimitCents / 100).toFixed(2)}`);
  }

  let rateBp = Math.min(credit.interestRateBp || 1800, 2160);
  let coupon = loadCoupon(userId, input.couponId);
  if (coupon) {
    if (input.amountCents < coupon.min_amount_cents) throw new ApiError(ErrCode.COUPON_INVALID, '未达到优惠券使用门槛');
    if (coupon.term_limit && coupon.term_limit !== input.termMonths) throw new ApiError(ErrCode.COUPON_INVALID, '该优惠券不适用所选期数');
    if (coupon.type === 'rate') rateBp = Math.max(600, rateBp - coupon.rate_off_bp);
  }

  const base = buildSchedule(input.amountCents, rateBp, input.termMonths);
  const items = base.items.map((x) => ({ ...x }));
  let couponDiscount = 0;
  if (coupon && coupon.type === 'cash') {
    couponDiscount = applyCashDiscount(items, coupon.amount_cents);
  }
  const totalInterest = items.reduce((s, x) => s + x.interestCents, 0);
  const totalRepay = items.reduce((s, x) => s + x.totalCents, 0);
  const apr = irrAnnualBp(input.amountCents, items.map((x) => x.totalCents));

  const disbursedDate = todayStr();
  const dueDates = buildDueDates(disbursedDate, input.termMonths);
  const schedule = items.map((x, idx) => ({
    periodNo: x.periodNo,
    dueDate: dueDates[idx],
    principalCents: x.principalCents,
    interestCents: x.interestCents,
    totalCents: x.totalCents,
  }));

  const payload = {
    userId,
    amountCents: input.amountCents,
    termMonths: input.termMonths,
    rateBp,
    couponId: input.couponId ?? null,
    couponDiscount,
    totalInterest,
    totalRepay,
    exp: Math.floor(Date.now() / 1000) + 600,
  };
  const quoteToken = jwt.sign(payload, SECRET);

  return {
    amountCents: input.amountCents,
    termMonths: input.termMonths,
    rateBp,
    aprBp: apr,
    monthlyPaymentCents: schedule[0].totalCents,
    totalInterestCents: totalInterest,
    totalRepayCents: totalRepay,
    serviceFeeCents: 0,
    arriveAmountCents: input.amountCents,
    couponId: input.couponId ?? null,
    couponDiscountCents: couponDiscount,
    firstDueDate: dueDates[0],
    lastDueDate: dueDates[dueDates.length - 1],
    schedule,
    quoteToken,
    availableLimitCents: credit.availableLimitCents,
  };
}

export interface CreateLoanInput {
  quoteToken: string;
  bankCardId: number;
  purpose?: string;
  contractSigned: boolean;
  agreementVersion?: string;
}

export function createLoan(userId: number, input: CreateLoanInput) {
  if (!input.contractSigned) throw new ApiError(ErrCode.CONTRACT_UNSIGNED);

  let q: any;
  try {
    q = jwt.verify(input.quoteToken, SECRET);
  } catch {
    throw new ApiError(ErrCode.CONFLICT, '试算已过期，请重新试算');
  }
  if (q.userId !== userId) throw new ApiError(ErrCode.FORBIDDEN);

  const card = db.prepare(`SELECT * FROM bank_cards WHERE id = ? AND user_id = ?`).get(input.bankCardId, userId) as any;
  if (!card) throw new ApiError(ErrCode.CARD_REQUIRED, '请先绑定收款银行卡');
  if (card.status !== 'active') throw new ApiError(ErrCode.CARD_INVALID, '银行卡状态异常，请更换');

  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId) as any;
  if (user.status !== 'active') throw new ApiError(ErrCode.ACCOUNT_FROZEN);

  const available = Math.max(0, user.credit_limit_cents - user.used_limit_cents - user.frozen_limit_cents);
  if (available < q.amountCents) throw new ApiError(ErrCode.CREDIT_INSUFFICIENT);

  const processing = db
    .prepare(`SELECT id FROM loans WHERE user_id = ? AND status IN ('reviewing','disbursing') LIMIT 1`)
    .get(userId);
  if (processing) throw new ApiError(ErrCode.LOAN_PROCESSING);

  assertLoanRisk(userId, q.amountCents);

  const now = nowIso();
  const loanNo = genNo('UC');
  const scheduleItems = buildSchedule(q.amountCents, q.rateBp, q.termMonths).items;
  if (q.couponDiscount > 0) applyCashDiscount(scheduleItems, q.couponDiscount);
  const apr = irrAnnualBp(q.amountCents, scheduleItems.map((x) => x.totalCents));

  const loanId = tx(() => {
    const info = db
      .prepare(
        `INSERT INTO loans(loan_no, user_id, principal_cents, term_months, interest_rate_bp, apr_bp,
          total_interest_cents, total_repay_cents, monthly_payment_cents, coupon_id, coupon_discount_cents,
          bank_card_id, purpose, status, contract_no, signed_at, created_at, updated_at)
         VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        loanNo,
        userId,
        q.amountCents,
        q.termMonths,
        q.rateBp,
        apr,
        q.totalInterest,
        q.totalRepay,
        scheduleItems[0].totalCents,
        q.couponId,
        q.couponDiscount,
        input.bankCardId,
        input.purpose ?? null,
        'reviewing',
        `HT${loanNo}`,
        now,
        now,
        now
      );
    const id = Number(info.lastInsertRowid);

    if (q.couponId) {
      db.prepare(`UPDATE user_coupons SET status = 'used', loan_id = ?, used_at = ? WHERE user_id = ? AND coupon_id = ?`).run(
        id,
        now,
        userId,
        q.couponId
      );
      db.prepare('UPDATE coupons SET used_qty = used_qty + 1 WHERE id = ?').run(q.couponId);
    }

    db.prepare('UPDATE users SET frozen_limit_cents = frozen_limit_cents + ?, updated_at = ? WHERE id = ?').run(
      q.amountCents,
      now,
      userId
    );

    db.prepare(
      `INSERT INTO audit_logs(actor_type, actor_id, action, target_type, target_id, detail, created_at)
       VALUES('user', ?, 'loan.create', 'loan', ?, ?, ?)`
    ).run(userId, String(id), JSON.stringify({ amount: q.amountCents, term: q.termMonths }), now);

    return id;
  });

  // 提交后立即进入放款队列（异步）
  scheduleDisbursement(loanId);

  return getLoan(userId, loanId);
}

/** 放款任务：2 秒后执行，模拟渠道处理时延；服务重启后由 sweepDisbursing 兜底 */
export function scheduleDisbursement(loanId: number, delayMs = 2000) {
  setTimeout(() => {
    try {
      disburse(loanId);
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error('[disburse]', e);
    }
  }, delayMs);
}

export function sweepDisbursing() {
  const rows = db.prepare(`SELECT id FROM loans WHERE status = 'disbursing'`).all() as any[];
  for (const r of rows) disburse(r.id);
  const reviewing = db.prepare(`SELECT id FROM loans WHERE status = 'reviewing'`).all() as any[];
  for (const r of reviewing) scheduleDisbursement(r.id, 500);
}

export function disburse(loanId: number) {
  const loan = db.prepare('SELECT * FROM loans WHERE id = ?').get(loanId) as any;
  if (!loan || !['reviewing', 'disbursing'].includes(loan.status)) return;

  const card = db.prepare('SELECT * FROM bank_cards WHERE id = ?').get(loan.bank_card_id) as any;
  const now = nowIso();

  // 渠道失败模拟：卡状态异常，或卡号尾号 0000
  if (!card || card.status !== 'active' || card.card_no_mask.endsWith('0000')) {
    tx(() => {
      db.prepare(`UPDATE loans SET status='failed', fail_code='E1024', fail_reason=?, updated_at=? WHERE id=?`).run(
        '银行卡状态异常，放款失败（E1024）',
        now,
        loanId
      );
      db.prepare('UPDATE users SET frozen_limit_cents = MAX(0, frozen_limit_cents - ?), updated_at=? WHERE id=?').run(
        loan.principal_cents,
        now,
        loan.user_id
      );
    });
    notify(loan.user_id, 'loan', '放款失败', `您的借款 ${loan.loan_no} 放款失败（E1024 银行卡状态异常），请更换银行卡后重试。`, loan.loan_no);
    return;
  }

  tx(() => {
    const disbursedDate = todayDateStr();
    const dueDates = buildDueDates(disbursedDate, loan.term_months);
    const items = buildSchedule(loan.principal_cents, loan.interest_rate_bp, loan.term_months).items;
    if (loan.coupon_discount_cents > 0) applyCashDiscount(items, loan.coupon_discount_cents);
    const insertSch = db.prepare(
      `INSERT INTO loan_schedules(loan_id, period_no, due_date, principal_cents, interest_cents, total_cents, status)
       VALUES(?,?,?,?,?,?,'unpaid')`
    );
    items.forEach((it, idx) => insertSch.run(loanId, it.periodNo, dueDates[idx], it.principalCents, it.interestCents, it.totalCents));

    db.prepare(
      `UPDATE loans SET status='active', disbursed_at=?, first_due_date=?, updated_at=? WHERE id=?`
    ).run(now, dueDates[0], now, loanId);

    db.prepare(
      `UPDATE users SET frozen_limit_cents = MAX(0, frozen_limit_cents - ?), used_limit_cents = used_limit_cents + ?, updated_at=? WHERE id=?`
    ).run(loan.principal_cents, loan.principal_cents, now, loan.user_id);
  });

  notify(
    loan.user_id,
    'loan',
    '放款成功',
    `您的借款 ¥${(loan.principal_cents / 100).toFixed(2)} 已放款至${card.bank_name}（${card.card_no_mask}），首期还款日 ${buildDueDates(todayDateStr(), loan.term_months)[0]}。`,
    loan.loan_no
  );
}

/** 放款失败后更换银行卡重试 */
export function retryDisburse(userId: number, loanId: number, bankCardId: number) {
  const loan = db.prepare('SELECT * FROM loans WHERE id = ? AND user_id = ?').get(loanId, userId) as any;
  if (!loan) throw new ApiError(ErrCode.NOT_FOUND, '借款记录不存在');
  if (loan.status !== 'failed') throw new ApiError(ErrCode.CONFLICT, '当前状态不支持重试');
  const card = db.prepare('SELECT * FROM bank_cards WHERE id = ? AND user_id = ?').get(bankCardId, userId) as any;
  if (!card) throw new ApiError(ErrCode.CARD_REQUIRED);
  if (card.status !== 'active') throw new ApiError(ErrCode.CARD_INVALID);

  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId) as any;
  if (user.credit_limit_cents - user.used_limit_cents - user.frozen_limit_cents < loan.principal_cents) {
    throw new ApiError(ErrCode.CREDIT_INSUFFICIENT);
  }

  tx(() => {
    db.prepare(`UPDATE loans SET bank_card_id=?, status='reviewing', fail_code=NULL, fail_reason=NULL, updated_at=? WHERE id=?`).run(
      bankCardId,
      nowIso(),
      loanId
    );
    db.prepare('UPDATE users SET frozen_limit_cents = frozen_limit_cents + ?, updated_at=? WHERE id=?').run(
      loan.principal_cents,
      nowIso(),
      userId
    );
  });
  scheduleDisbursement(loanId, 1500);
  return getLoan(userId, loanId);
}

export function getLoan(userId: number, loanId: number) {
  const loan = db.prepare('SELECT * FROM loans WHERE id = ? AND user_id = ?').get(loanId, userId) as any;
  if (!loan) throw new ApiError(ErrCode.NOT_FOUND, '借款记录不存在');
  return decorateLoan(loan);
}

export function decorateLoan(loan: any) {
  const schedules = db
    .prepare('SELECT * FROM loan_schedules WHERE loan_id = ? ORDER BY period_no ASC')
    .all(loan.id) as any[];
  const paidPrincipal = schedules.reduce((s, x) => s + x.paid_principal_cents, 0);
  const paidInterest = schedules.reduce((s, x) => s + x.paid_interest_cents, 0);
  const paidPenalty = schedules.reduce((s, x) => s + x.penalty_cents, 0);
  const remainingPrincipal = loan.principal_cents - paidPrincipal;
  return {
    id: loan.id,
    loanNo: loan.loan_no,
    principalCents: loan.principal_cents,
    termMonths: loan.term_months,
    rateBp: loan.interest_rate_bp,
    aprBp: loan.apr_bp,
    totalInterestCents: loan.total_interest_cents,
    totalRepayCents: loan.total_repay_cents,
    monthlyPaymentCents: loan.monthly_payment_cents,
    status: loan.status,
    purpose: loan.purpose,
    failCode: loan.fail_code,
    failReason: loan.fail_reason,
    contractNo: loan.contract_no,
    disbursedAt: loan.disbursed_at,
    firstDueDate: loan.first_due_date,
    settledAt: loan.settled_at,
    overdueDays: loan.overdue_days,
    createdAt: loan.created_at,
    paidPrincipalCents: paidPrincipal,
    paidInterestCents: paidInterest,
    paidPenaltyCents: paidPenalty,
    remainingPrincipalCents: remainingPrincipal,
    schedules: schedules.map((s) => ({
      id: s.id,
      periodNo: s.period_no,
      dueDate: s.due_date,
      principalCents: s.principal_cents,
      interestCents: s.interest_cents,
      totalCents: s.total_cents,
      paidPrincipalCents: s.paid_principal_cents,
      paidInterestCents: s.paid_interest_cents,
      penaltyCents: s.penalty_cents,
      status: s.status,
      paidAt: s.paid_at,
    })),
  };
}

export function listLoans(userId: number, status?: string) {
  let sql = 'SELECT * FROM loans WHERE user_id = ?';
  const params: any[] = [userId];
  if (status === 'active') sql += ` AND status IN ('reviewing','disbursing','active','overdue')`;
  else if (status === 'settled') sql += ` AND status = 'settled'`;
  else if (status === 'failed') sql += ` AND status IN ('failed','rejected')`;
  sql += ' ORDER BY id DESC LIMIT 50';
  const rows = db.prepare(sql).all(...params) as any[];
  return rows.map((r) => ({
    id: r.id,
    loanNo: r.loan_no,
    principalCents: r.principal_cents,
    termMonths: r.term_months,
    status: r.status,
    aprBp: r.apr_bp,
    monthlyPaymentCents: r.monthly_payment_cents,
    createdAt: r.created_at,
    disbursedAt: r.disbursed_at,
    overdueDays: r.overdue_days,
    remainingPrincipalCents: r.principal_cents - (db.prepare('SELECT COALESCE(SUM(paid_principal_cents),0) s FROM loan_schedules WHERE loan_id=?').get(r.id) as any).s,
  }));
}

export function currentLoanSummary(userId: number) {
  const loan = db
    .prepare(`SELECT * FROM loans WHERE user_id = ? AND status IN ('active','overdue') ORDER BY id DESC LIMIT 1`)
    .get(userId) as any;
  if (!loan) return null;
  const next = db
    .prepare(`SELECT * FROM loan_schedules WHERE loan_id = ? AND status != 'paid' ORDER BY period_no ASC LIMIT 1`)
    .get(loan.id) as any;
  if (!next) return null;
  const paid = db.prepare(`SELECT COUNT(*) c FROM loan_schedules WHERE loan_id = ? AND status = 'paid'`).get(loan.id) as any;
  return {
    loanId: loan.id,
    loanNo: loan.loan_no,
    principalCents: loan.principal_cents,
    termMonths: loan.term_months,
    paidPeriods: paid.c,
    nextPeriod: next.period_no,
    nextDueDate: next.due_date,
    nextAmountCents: next.total_cents - next.paid_principal_cents - next.paid_interest_cents + next.penalty_cents,
    status: loan.status,
    overdueDays: loan.overdue_days,
  };
}

export { SETTLE_PENALTY_BP, addMonthsClamped };
