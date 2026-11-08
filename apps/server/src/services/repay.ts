import { db, tx } from '../db.js';
import { ApiError, ErrCode } from '../lib/http.js';
import { diffDays, nowIso, todayDateStr } from '../lib/date.js';
import { genNo } from '../lib/id.js';
import { notify } from './notify.js';

const PENALTY_DAILY_BP = 5; // 日罚息万分之五 = 0.05%/日
const SETTLE_PENALTY_RATE_BP = 0; // 提前结清违约金，0 表示免收

export interface BillItem {
  scheduleId: number;
  loanId: number;
  loanNo: string;
  periodNo: number;
  termMonths: number;
  dueDate: string;
  principalCents: number;
  interestCents: number;
  totalCents: number;
  paidPrincipalCents: number;
  paidInterestCents: number;
  penaltyCents: number;
  payableCents: number;
  status: string;
  overdueDays: number;
}

function overdueDaysOf(dueDate: string): number {
  const d = diffDays(dueDate, todayDateStr());
  return d > 0 ? d : 0;
}

function toBillItem(row: any): BillItem {
  const status = row.status === 'paid' ? 'paid' : overdueDaysOf(row.due_date) > 0 ? 'overdue' : row.status;
  const payable =
    row.principal_cents - row.paid_principal_cents + (row.interest_cents - row.paid_interest_cents) + row.penalty_cents;
  return {
    scheduleId: row.id,
    loanId: row.loan_id,
    loanNo: row.loan_no,
    periodNo: row.period_no,
    termMonths: row.term_months,
    dueDate: row.due_date,
    principalCents: row.principal_cents,
    interestCents: row.interest_cents,
    totalCents: row.total_cents,
    paidPrincipalCents: row.paid_principal_cents,
    paidInterestCents: row.paid_interest_cents,
    penaltyCents: row.penalty_cents,
    payableCents: Math.max(0, payable),
    status,
    overdueDays: status === 'overdue' ? overdueDaysOf(row.due_date) : 0,
  };
}

export function getBills(userId: number) {
  const rows = db
    .prepare(
      `SELECT s.*, l.loan_no, l.term_months, l.status AS loan_status
       FROM loan_schedules s JOIN loans l ON l.id = s.loan_id
       WHERE l.user_id = ? AND l.status IN ('active','overdue','settled')
       ORDER BY s.due_date ASC, s.period_no ASC`
    )
    .all(userId) as any[];

  const items = rows.map(toBillItem);
  const unpaid = items.filter((x) => x.status !== 'paid');
  const paid = items.filter((x) => x.status === 'paid').sort((a, b) => (a.dueDate < b.dueDate ? 1 : -1));
  const overdue = unpaid.filter((x) => x.status === 'overdue');
  const next = unpaid[0] ?? null;

  return {
    summary: {
      totalUnpaidCents: unpaid.reduce((s, x) => s + x.payableCents, 0),
      unpaidCount: unpaid.length,
      overdueCents: overdue.reduce((s, x) => s + x.payableCents, 0),
      overdueCount: overdue.length,
      nextDueDate: next?.dueDate ?? null,
      nextPayableCents: next?.payableCents ?? 0,
      paidCount: paid.length,
    },
    next,
    unpaid,
    paid,
    all: [...unpaid, ...paid],
  };
}

export function repayQuote(userId: number, loanId: number, type: 'normal' | 'settle') {
  const loan = db.prepare('SELECT * FROM loans WHERE id = ? AND user_id = ?').get(loanId, userId) as any;
  if (!loan) throw new ApiError(ErrCode.NOT_FOUND, '借款记录不存在');
  if (loan.status === 'settled') throw new ApiError(ErrCode.ALREADY_SETTLED);

  const schedules = db
    .prepare(`SELECT * FROM loan_schedules WHERE loan_id = ? AND status != 'paid' ORDER BY period_no ASC`)
    .all(loanId) as any[];
  if (!schedules.length) throw new ApiError(ErrCode.ALREADY_SETTLED);

  const remainingPrincipal = schedules.reduce((s, x) => s + (x.principal_cents - x.paid_principal_cents), 0);

  if (type === 'normal') {
    const s = schedules[0];
    const item = toBillItem({ ...s, loan_no: loan.loan_no, term_months: loan.term_months });
    return {
      type,
      loanId,
      loanNo: loan.loan_no,
      periodNo: s.period_no,
      dueDate: s.due_date,
      principalCents: s.principal_cents - s.paid_principal_cents,
      interestCents: s.interest_cents - s.paid_interest_cents,
      penaltyCents: s.penalty_cents,
      totalCents: item.payableCents,
      remainingPrincipalCents: remainingPrincipal,
    };
  }

  // 提前结清：剩余本金 + 当期未付利息 + 已产生罚息，后续期利息免除
  const next = schedules[0];
  const lastPaid = db
    .prepare(`SELECT MAX(paid_at) d FROM loan_schedules WHERE loan_id = ? AND paid_at IS NOT NULL`)
    .get(loanId) as any;
  const fromDate = lastPaid?.d ? lastPaid.d.slice(0, 10) : (loan.disbursed_at ?? loan.created_at).slice(0, 10);
  const days = Math.max(diffDays(fromDate, todayDateStr()), 1);
  const penalty = schedules.reduce((s, x) => s + x.penalty_cents, 0);
  const nextInterest = Math.max(0, next.interest_cents - next.paid_interest_cents);
  const settlePenalty = Math.round((remainingPrincipal * SETTLE_PENALTY_RATE_BP) / 10000);
  const total = remainingPrincipal + nextInterest + penalty + settlePenalty;

  return {
    type: 'settle',
    loanId,
    loanNo: loan.loan_no,
    periodNo: next.period_no,
    dueDate: next.due_date,
    principalCents: remainingPrincipal,
    interestCents: nextInterest,
    penaltyCents: penalty,
    settlePenaltyCents: settlePenalty,
    savedInterestCents: schedules.slice(1).reduce((s, x) => s + (x.interest_cents - x.paid_interest_cents), 0),
    daysAccrued: days,
    totalCents: total,
    remainingPrincipalCents: remainingPrincipal,
  };
}

export interface RepayInput {
  loanId: number;
  type: 'normal' | 'settle';
  bankCardId: number;
}

export function repay(userId: number, input: RepayInput) {
  const loan = db.prepare('SELECT * FROM loans WHERE id = ? AND user_id = ?').get(input.loanId, userId) as any;
  if (!loan) throw new ApiError(ErrCode.NOT_FOUND, '借款记录不存在');
  if (loan.status === 'settled') throw new ApiError(ErrCode.ALREADY_SETTLED);
  if (!['active', 'overdue'].includes(loan.status)) throw new ApiError(ErrCode.CONFLICT, '当前借款状态不支持还款');

  const card = db.prepare('SELECT * FROM bank_cards WHERE id = ? AND user_id = ?').get(input.bankCardId, userId) as any;
  if (!card) throw new ApiError(ErrCode.CARD_REQUIRED, '请选择还款银行卡');
  if (card.status !== 'active' || card.card_no_mask.endsWith('0000')) {
    throw new ApiError(ErrCode.CARD_INVALID, '银行卡状态异常，请更换银行卡');
  }

  const q = repayQuote(userId, input.loanId, input.type);
  const now = nowIso();
  const repaymentNo = genNo('RP');

  // 幂等兜底：同一借据同类型还款 5 秒内重复提交，视为重复点击
  const dup = db
    .prepare(
      `SELECT id FROM repayments WHERE loan_id = ? AND type = ? AND status = 'success' AND created_at > ?
       ORDER BY id DESC LIMIT 1`
    )
    .get(input.loanId, input.type, new Date(Date.now() - 5000).toISOString()) as any;
  if (dup) throw new ApiError(ErrCode.REPAY_PROCESSING, '还款正在处理，请勿重复提交');

  const result = tx(() => {
    const schedules = db
      .prepare(`SELECT * FROM loan_schedules WHERE loan_id = ? AND status != 'paid' ORDER BY period_no ASC`)
      .all(input.loanId) as any[];

    let principalPaid = 0;
    let interestPaid = 0;
    let penaltyPaid = 0;

    if (input.type === 'normal') {
      const s = schedules[0];
      principalPaid = s.principal_cents - s.paid_principal_cents;
      interestPaid = s.interest_cents - s.paid_interest_cents;
      penaltyPaid = s.penalty_cents;
      db.prepare(
        `UPDATE loan_schedules SET paid_principal_cents = principal_cents, paid_interest_cents = interest_cents,
         status = 'paid', paid_at = ? WHERE id = ?`
      ).run(now, s.id);
    } else {
      // 提前结清：本金全额收回，只实收当期利息，未来期利息减免（置 0）
      principalPaid = q.principalCents;
      interestPaid = q.interestCents;
      penaltyPaid = q.penaltyCents;
      schedules.forEach((s, idx) => {
        if (idx === 0) {
          db.prepare(
            `UPDATE loan_schedules SET paid_principal_cents = principal_cents, paid_interest_cents = interest_cents,
             status = 'paid', paid_at = ? WHERE id = ?`
          ).run(now, s.id);
        } else {
          db.prepare(
            `UPDATE loan_schedules SET paid_principal_cents = principal_cents, paid_interest_cents = 0,
             interest_cents = 0, total_cents = principal_cents, status = 'paid', paid_at = ? WHERE id = ?`
          ).run(now, s.id);
        }
      });
    }

    const info = db
      .prepare(
        `INSERT INTO repayments(repayment_no, user_id, loan_id, type, amount_cents, principal_cents, interest_cents,
          penalty_cents, channel, bank_card_id, status, paid_at, created_at)
         VALUES(?,?,?,?,?,?,?,?,?,?,'success',?,?)`
      )
      .run(
        repaymentNo,
        userId,
        input.loanId,
        input.type,
        q.totalCents,
        principalPaid,
        interestPaid,
        penaltyPaid,
        'bankcard',
        input.bankCardId,
        now,
        now
      );

    db.prepare('UPDATE users SET used_limit_cents = MAX(0, used_limit_cents - ?), updated_at = ? WHERE id = ?').run(
      principalPaid,
      now,
      userId
    );

    const left = db.prepare(`SELECT COUNT(*) c FROM loan_schedules WHERE loan_id = ? AND status != 'paid'`).get(input.loanId) as any;
    if (left.c === 0) {
      db.prepare(`UPDATE loans SET status='settled', settled_at=?, updated_at=? WHERE id=?`).run(now, now, input.loanId);
    } else if (input.type === 'settle') {
      db.prepare(`UPDATE loans SET status='settled', settled_at=?, updated_at=? WHERE id=?`).run(now, now, input.loanId);
    }

    return Number(info.lastInsertRowid);
  });

  notify(
    userId,
    'repay',
    input.type === 'settle' ? '提前结清成功' : '还款成功',
    `借款 ${loan.loan_no} 已${input.type === 'settle' ? '提前结清' : '还款'} ¥${(q.totalCents / 100).toFixed(2)}，感谢您的守信。`,
    loan.loan_no
  );

  return {
    repaymentId: result,
    repaymentNo,
    loanId: input.loanId,
    amountCents: q.totalCents,
    principalCents: q.principalCents,
    interestCents: q.interestCents,
    penaltyCents: q.penaltyCents,
    paidAt: now,
    loanStatus: db.prepare('SELECT status FROM loans WHERE id = ?').get(input.loanId),
  };
}

export function listRepayments(userId: number) {
  const rows = db
    .prepare(
      `SELECT r.*, l.loan_no FROM repayments r JOIN loans l ON l.id = r.loan_id
       WHERE r.user_id = ? ORDER BY r.id DESC LIMIT 100`
    )
    .all(userId) as any[];
  return rows.map((r) => ({
    id: r.id,
    repaymentNo: r.repayment_no,
    loanId: r.loan_id,
    loanNo: r.loan_no,
    type: r.type,
    amountCents: r.amount_cents,
    principalCents: r.principal_cents,
    interestCents: r.interest_cents,
    penaltyCents: r.penalty_cents,
    channel: r.channel,
    status: r.status,
    paidAt: r.paid_at,
  }));
}

/** 逾期扫描：标记逾期账单、计提罚息、更新借据逾期天数（每日定时 + 手动触发） */
export function markOverdue() {
  const today = todayDateStr();
  const now = nowIso();
  const rows = db
    .prepare(
      `SELECT s.*, l.id AS loan_id, l.user_id FROM loan_schedules s JOIN loans l ON l.id = s.loan_id
       WHERE s.status != 'paid' AND s.due_date < ? AND l.status IN ('active','overdue')`
    )
    .all(today) as any[];

  let affected = 0;
  for (const s of rows) {
    const days = diffDays(s.due_date, today);
    const base = s.principal_cents - s.paid_principal_cents + (s.interest_cents - s.paid_interest_cents);
    const penalty = Math.round((base * PENALTY_DAILY_BP * days) / 10000);
    db.prepare(`UPDATE loan_schedules SET status='overdue', penalty_cents=? WHERE id=?`).run(penalty, s.id);
    db.prepare(`UPDATE loans SET status='overdue', overdue_days=?, updated_at=? WHERE id=?`).run(days, now, s.loan_id);
    affected++;
  }
  return { affected, date: today };
}
