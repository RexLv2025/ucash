import { Router } from 'express';
import { z } from 'zod';
import { db, tx, getSetting, setSetting, audit } from '../db.js';
import { ApiError, ErrCode, ok } from '../lib/http.js';
import { nowIso, todayDateStr } from '../lib/date.js';
import { maskPhone, maskIdCard, verifyPassword } from '../lib/security.js';
import { requireAdmin, signAdminToken, type AuthedRequest } from '../middleware/auth.js';
import { reviewCredit } from '../services/credit.js';
import { disburse } from '../services/loan.js';
import { markOverdue } from '../services/repay.js';
import { notify } from '../services/notify.js';

export const adminRouter = Router();

// 登录失败锁定：同一 IP+账号 5 次失败锁定 15 分钟
const loginFails = new Map<string, { count: number; lockUntil: number }>();
const MAX_LOGIN_FAILS = 5;
const LOCK_MS = 15 * 60 * 1000;

adminRouter.post('/login', (req, res) => {
  const body = z.object({ username: z.string(), password: z.string() }).parse(req.body);
  const key = `${req.ip}:${body.username}`;
  const rec = loginFails.get(key);
  if (rec && rec.lockUntil > Date.now()) {
    const mins = Math.ceil((rec.lockUntil - Date.now()) / 60000);
    throw new ApiError(ErrCode.RATE_LIMIT, `登录失败次数过多，请 ${mins} 分钟后再试`);
  }
  const admin = db.prepare('SELECT * FROM admins WHERE username = ?').get(body.username) as any;
  if (!admin || admin.status !== 'active' || !verifyPassword(body.password, admin.password_hash)) {
    const count = (rec?.count ?? 0) + 1;
    loginFails.set(key, { count, lockUntil: count >= MAX_LOGIN_FAILS ? Date.now() + LOCK_MS : 0 });
    const left = Math.max(0, MAX_LOGIN_FAILS - count);
    throw new ApiError(ErrCode.PASSWORD, left > 0 ? `账号或密码错误，还可尝试 ${left} 次` : '登录失败次数过多，账号已锁定 15 分钟');
  }
  loginFails.delete(key);
  db.prepare('UPDATE admins SET last_login_at = ? WHERE id = ?').run(nowIso(), admin.id);
  audit('admin', admin.id, 'admin.login', 'admin', admin.id, null, req.ip);
  ok(res, { token: signAdminToken(admin.id, admin.username, admin.role), admin: { id: admin.id, name: admin.name, role: admin.role } });
});

adminRouter.use(requireAdmin('ops'));

// ==================== 工作台 ====================

adminRouter.get('/dashboard', (_req, res) => {
  const today = todayDateStr();
  const q = (sql: string, ...p: any[]) => (db.prepare(sql).get(...p) as any) ?? {};
  const todayReg = q(`SELECT COUNT(*) c FROM users WHERE substr(created_at,1,10) = ?`, today).c;
  const todayApply = q(`SELECT COUNT(*) c FROM credit_applications WHERE substr(created_at,1,10) = ?`, today).c;
  const todayLoans = q(`SELECT COUNT(*) c, COALESCE(SUM(principal_cents),0) s FROM loans WHERE status IN ('active','settled','overdue') AND substr(disbursed_at,1,10)=?`, today);
  const todayRepay = q(`SELECT COUNT(*) c, COALESCE(SUM(amount_cents),0) s FROM repayments WHERE status='success' AND substr(paid_at,1,10)=?`, today);
  const inLoan = q(`SELECT COALESCE(SUM(principal_cents),0) s FROM loans WHERE status IN ('active','overdue')`);
  const paidPrincipal = q(`SELECT COALESCE(SUM(paid_principal_cents),0) s FROM loan_schedules s JOIN loans l ON l.id=s.loan_id WHERE l.status IN ('active','overdue')`);
  const overdue = q(`SELECT COUNT(*) c, COALESCE(SUM(s.total_cents - s.paid_principal_cents - s.paid_interest_cents),0) s
                     FROM loan_schedules s JOIN loans l ON l.id=s.loan_id WHERE s.status='overdue' AND l.status IN ('active','overdue')`);
  const totalUsers = q(`SELECT COUNT(*) c FROM users`).c;
  const approvedCredit = q(`SELECT COUNT(*) c FROM credit_applications WHERE status='approved'`).c;
  const allApply = q(`SELECT COUNT(*) c FROM credit_applications`).c;
  const totalLoans = q(`SELECT COUNT(*) c FROM loans WHERE status IN ('active','settled','overdue')`).c;
  const settledLoans = q(`SELECT COUNT(*) c FROM loans WHERE status='settled'`).c;
  const pendingCredit = q(`SELECT COUNT(*) c FROM credit_applications WHERE status IN ('manual','submitted','reviewing')`).c;
  const pendingLoan = q(`SELECT COUNT(*) c FROM loans WHERE status IN ('reviewing','disbursing')`).c;
  const balance = inLoan.s - paidPrincipal.s;

  ok(res, {
    today: {
      newUsers: todayReg,
      creditApplications: todayApply,
      loanCount: todayLoans.c,
      loanAmountCents: todayLoans.s,
      repayCount: todayRepay.c,
      repayAmountCents: todayRepay.s,
    },
    portfolio: {
      totalUsers,
      balanceCents: Math.max(0, balance),
      inLoanPrincipalCents: inLoan.s,
      overdueCount: overdue.c,
      overdueAmountCents: overdue.s,
      overdueRate: balance > 0 ? Number(((overdue.s / balance) * 100).toFixed(2)) : 0,
      creditApprovalRate: allApply > 0 ? Number(((approvedCredit / allApply) * 100).toFixed(1)) : 0,
      settleRate: totalLoans > 0 ? Number(((settledLoans / totalLoans) * 100).toFixed(1)) : 0,
    },
    todo: { pendingCredit, pendingLoan },
    trend: Array.from({ length: 7 }, (_, i) => {
      const d = new Date();
      d.setDate(d.getDate() - (6 - i));
      const day = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
      const l = q(`SELECT COUNT(*) c, COALESCE(SUM(principal_cents),0) s FROM loans WHERE substr(created_at,1,10)=?`, day);
      const r = q(`SELECT COALESCE(SUM(amount_cents),0) s FROM repayments WHERE status='success' AND substr(paid_at,1,10)=?`, day);
      return { date: day, loanCount: l.c, loanAmountCents: l.s, repayAmountCents: r.s };
    }),
  });
});

// ==================== 授信审批 ====================

adminRouter.get('/credit-applications', (req, res) => {
  const status = (req.query.status as string) || '';
  const page = Math.max(1, Number(req.query.page) || 1);
  const size = Math.min(100, Number(req.query.size) || 20);
  const where: string[] = [];
  const params: any[] = [];
  if (status) {
    where.push('a.status = ?');
    params.push(status);
  }
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const total = (db.prepare(`SELECT COUNT(*) c FROM credit_applications a ${whereSql}`).get(...params) as any).c;
  const rows = db
    .prepare(
      `SELECT a.*, u.phone, u.name, u.created_at AS user_created_at,
        (SELECT COUNT(*) FROM loans l WHERE l.user_id = u.id) AS loan_count
       FROM credit_applications a JOIN users u ON u.id = a.user_id
       ${whereSql} ORDER BY a.id DESC LIMIT ? OFFSET ?`
    )
    .all(...params, size, (page - 1) * size) as any[];
  ok(res, {
    total,
    page,
    size,
    list: rows.map((r) => ({
      id: r.id,
      userId: r.user_id,
      phone: maskPhone(r.phone),
      name: r.name,
      applyAmountCents: r.apply_amount_cents,
      status: r.status,
      score: r.score,
      approvedLimitCents: r.approved_limit_cents,
      interestRateBp: r.interest_rate_bp,
      rejectCode: r.reject_code,
      rejectReason: r.reject_reason,
      createdAt: r.created_at,
      reviewedAt: r.reviewed_at,
      loanCount: r.loan_count,
    })),
  });
});

adminRouter.get('/credit-applications/:id', (req, res) => {
  const r = db
    .prepare(`SELECT a.*, u.phone, u.name, u.id_card_mask FROM credit_applications a JOIN users u ON u.id=a.user_id WHERE a.id=?`)
    .get(req.params.id) as any;
  if (!r) throw new ApiError(ErrCode.NOT_FOUND);
  ok(res, {
    id: r.id,
    userId: r.user_id,
    phone: maskPhone(r.phone),
    name: r.name,
    idCardMask: r.id_card_mask,
    applyAmountCents: r.apply_amount_cents,
    status: r.status,
    score: r.score,
    approvedLimitCents: r.approved_limit_cents,
    interestRateBp: r.interest_rate_bp,
    rejectReason: r.reject_reason,
    risk: r.risk_snapshot ? JSON.parse(r.risk_snapshot) : null,
    createdAt: r.created_at,
  });
});

adminRouter.post('/credit-applications/:id/review', requireAdmin('approver'), (req: AuthedRequest, res) => {
  const body = z
    .object({ pass: z.boolean(), limitCents: z.number().int().optional(), rateBp: z.number().int().optional(), reason: z.string().optional() })
    .parse(req.body);
  const r = reviewCredit(req.admin!.sub, Number(req.params.id), body.pass, body.limitCents, body.rateBp, body.reason);
  audit('admin', req.admin!.sub, 'credit.review', 'credit_application', req.params.id, body, req.ip);
  ok(res, r, body.pass ? '已通过并激活额度' : '已拒绝');
});

// ==================== 借款订单 ====================

adminRouter.get('/loans', (req, res) => {
  const status = (req.query.status as string) || '';
  const keyword = (req.query.keyword as string) || '';
  const page = Math.max(1, Number(req.query.page) || 1);
  const size = Math.min(100, Number(req.query.size) || 20);
  const where: string[] = [];
  const params: any[] = [];
  if (status) {
    where.push('l.status = ?');
    params.push(status);
  }
  if (keyword) {
    where.push('(l.loan_no LIKE ? OR u.phone LIKE ?)');
    params.push(`%${keyword}%`, `%${keyword}%`);
  }
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const total = (db.prepare(`SELECT COUNT(*) c FROM loans l JOIN users u ON u.id=l.user_id ${whereSql}`).get(...params) as any).c;
  const rows = db
    .prepare(
      `SELECT l.*, u.phone, u.name,
        (SELECT COALESCE(SUM(s.paid_principal_cents),0) FROM loan_schedules s WHERE s.loan_id=l.id) AS paid_principal
       FROM loans l JOIN users u ON u.id=l.user_id ${whereSql} ORDER BY l.id DESC LIMIT ? OFFSET ?`
    )
    .all(...params, size, (page - 1) * size) as any[];
  ok(res, {
    total,
    page,
    size,
    list: rows.map((r) => ({
      id: r.id,
      loanNo: r.loan_no,
      phone: maskPhone(r.phone),
      name: r.name,
      principalCents: r.principal_cents,
      termMonths: r.term_months,
      rateBp: r.interest_rate_bp,
      aprBp: r.apr_bp,
      totalRepayCents: r.total_repay_cents,
      status: r.status,
      overdueDays: r.overdue_days,
      disbursedAt: r.disbursed_at,
      createdAt: r.created_at,
      remainingPrincipalCents: r.principal_cents - r.paid_principal,
      failCode: r.fail_code,
    })),
  });
});

adminRouter.get('/loans/:id', (req, res) => {
  const l = db.prepare(`SELECT l.*, u.phone, u.name FROM loans l JOIN users u ON u.id=l.user_id WHERE l.id=?`).get(req.params.id) as any;
  if (!l) throw new ApiError(ErrCode.NOT_FOUND);
  const schedules = db.prepare('SELECT * FROM loan_schedules WHERE loan_id=? ORDER BY period_no').all(l.id);
  const repayments = db.prepare('SELECT * FROM repayments WHERE loan_id=? ORDER BY id DESC').all(l.id);
  ok(res, {
    loan: {
      id: l.id,
      loanNo: l.loan_no,
      phone: maskPhone(l.phone),
      name: l.name,
      principalCents: l.principal_cents,
      termMonths: l.term_months,
      rateBp: l.interest_rate_bp,
      aprBp: l.apr_bp,
      totalInterestCents: l.total_interest_cents,
      totalRepayCents: l.total_repay_cents,
      status: l.status,
      failCode: l.fail_code,
      failReason: l.fail_reason,
      disbursedAt: l.disbursed_at,
      firstDueDate: l.first_due_date,
      overdueDays: l.overdue_days,
      contractNo: l.contract_no,
      createdAt: l.created_at,
    },
    schedules,
    repayments,
  });
});

adminRouter.post('/loans/:id/disburse', requireAdmin('approver'), (req: AuthedRequest, res) => {
  disburse(Number(req.params.id));
  audit('admin', req.admin!.sub, 'loan.disburse', 'loan', req.params.id, null, req.ip);
  ok(res, null, '已触发放款');
});

adminRouter.post('/loans/:id/reject', requireAdmin('approver'), (req: AuthedRequest, res) => {
  const body = z.object({ reason: z.string().default('人工审核未通过') }).parse(req.body);
  const loan = db.prepare('SELECT * FROM loans WHERE id=?').get(req.params.id) as any;
  if (!loan) throw new ApiError(ErrCode.NOT_FOUND);
  if (!['reviewing', 'disbursing'].includes(loan.status)) throw new ApiError(ErrCode.CONFLICT);
  tx(() => {
    db.prepare(`UPDATE loans SET status='rejected', fail_code='MANUAL_REJECT', fail_reason=?, updated_at=? WHERE id=?`).run(
      body.reason,
      nowIso(),
      loan.id
    );
    db.prepare('UPDATE users SET frozen_limit_cents = MAX(0, frozen_limit_cents - ?), updated_at=? WHERE id=?').run(
      loan.principal_cents,
      nowIso(),
      loan.user_id
    );
  });
  notify(loan.user_id, 'loan', '借款未通过', `您的借款申请 ${loan.loan_no} 未通过：${body.reason}`, loan.loan_no);
  audit('admin', req.admin!.sub, 'loan.reject', 'loan', req.params.id, body, req.ip);
  ok(res, null, '已拒绝');
});

// ==================== 账单与逾期台账 ====================

adminRouter.get('/bills', (req, res) => {
  const status = (req.query.status as string) || '';
  const page = Math.max(1, Number(req.query.page) || 1);
  const size = Math.min(100, Number(req.query.size) || 20);
  const where: string[] = [];
  const params: any[] = [];
  if (status === 'overdue') where.push(`s.status='overdue'`);
  else if (status === 'unpaid') where.push(`s.status IN ('unpaid','partial','overdue')`);
  else if (status === 'paid') where.push(`s.status='paid'`);
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const total = (db.prepare(`SELECT COUNT(*) c FROM loan_schedules s ${whereSql}`).get(...params) as any).c;
  const rows = db
    .prepare(
      `SELECT s.*, l.loan_no, u.phone, u.name FROM loan_schedules s
       JOIN loans l ON l.id=s.loan_id JOIN users u ON u.id=l.user_id
       ${whereSql} ORDER BY s.due_date ASC LIMIT ? OFFSET ?`
    )
    .all(...params, size, (page - 1) * size) as any[];
  ok(res, {
    total,
    page,
    size,
    list: rows.map((r) => ({
      id: r.id,
      loanId: r.loan_id,
      loanNo: r.loan_no,
      phone: maskPhone(r.phone),
      name: r.name,
      periodNo: r.period_no,
      dueDate: r.due_date,
      principalCents: r.principal_cents,
      interestCents: r.interest_cents,
      totalCents: r.total_cents,
      paidPrincipalCents: r.paid_principal_cents,
      paidInterestCents: r.paid_interest_cents,
      penaltyCents: r.penalty_cents,
      status: r.status,
      paidAt: r.paid_at,
    })),
  });
});

adminRouter.post('/bills/overdue-scan', (req: AuthedRequest, res) => {
  const r = markOverdue();
  audit('admin', req.admin!.sub, 'bill.overdue_scan', 'system', null, r, req.ip);
  ok(res, r);
});

adminRouter.post('/bills/:id/penalty-waive', requireAdmin('approver'), (req: AuthedRequest, res) => {
  const bill = db.prepare('SELECT * FROM loan_schedules WHERE id=?').get(req.params.id) as any;
  if (!bill) throw new ApiError(ErrCode.NOT_FOUND);
  db.prepare('UPDATE loan_schedules SET penalty_cents=0 WHERE id=?').run(bill.id);
  audit('admin', req.admin!.sub, 'bill.penalty_waive', 'loan_schedule', req.params.id, { before: bill.penalty_cents }, req.ip);
  ok(res, null, '罚息已减免');
});

// ==================== 还款流水 ====================

adminRouter.get('/repayments', (req, res) => {
  const page = Math.max(1, Number(req.query.page) || 1);
  const size = Math.min(100, Number(req.query.size) || 20);
  const total = (db.prepare('SELECT COUNT(*) c FROM repayments').get() as any).c;
  const rows = db
    .prepare(
      `SELECT r.*, l.loan_no, u.phone, u.name FROM repayments r
       JOIN loans l ON l.id=r.loan_id JOIN users u ON u.id=r.user_id
       ORDER BY r.id DESC LIMIT ? OFFSET ?`
    )
    .all(size, (page - 1) * size) as any[];
  ok(res, {
    total,
    page,
    size,
    list: rows.map((r) => ({
      id: r.id,
      repaymentNo: r.repayment_no,
      loanNo: r.loan_no,
      phone: maskPhone(r.phone),
      name: r.name,
      type: r.type,
      amountCents: r.amount_cents,
      principalCents: r.principal_cents,
      interestCents: r.interest_cents,
      penaltyCents: r.penalty_cents,
      status: r.status,
      paidAt: r.paid_at,
    })),
  });
});

// ==================== 用户管理 ====================

adminRouter.get('/users', (req, res) => {
  const keyword = (req.query.keyword as string) || '';
  const page = Math.max(1, Number(req.query.page) || 1);
  const size = Math.min(100, Number(req.query.size) || 20);
  const where = keyword ? `WHERE (u.phone LIKE ? OR u.name LIKE ? OR u.invite_code LIKE ?)` : '';
  const params = keyword ? [`%${keyword}%`, `%${keyword}%`, `%${keyword}%`] : [];
  const total = (db.prepare(`SELECT COUNT(*) c FROM users u ${where}`).get(...params) as any).c;
  const rows = db
    .prepare(
      `SELECT u.*, (SELECT COUNT(*) FROM loans l WHERE l.user_id=u.id AND l.status IN ('active','overdue')) AS active_loans,
        (SELECT COALESCE(SUM(l.principal_cents),0) FROM loans l WHERE l.user_id=u.id AND l.status IN ('active','overdue')) AS in_loan
       FROM users u ${where} ORDER BY u.id DESC LIMIT ? OFFSET ?`
    )
    .all(...params, size, (page - 1) * size) as any[];
  ok(res, {
    total,
    page,
    size,
    list: rows.map((r) => ({
      id: r.id,
      phone: maskPhone(r.phone),
      name: r.name,
      idCardMask: r.id_card_mask,
      status: r.status,
      creditLimitCents: r.credit_limit_cents,
      usedLimitCents: r.used_limit_cents,
      frozenLimitCents: r.frozen_limit_cents,
      riskLevel: r.risk_level,
      blacklist: Boolean(r.blacklist),
      activeLoans: r.active_loans,
      inLoanCents: r.in_loan,
      createdAt: r.created_at,
    })),
  });
});

adminRouter.post('/users/:id/limit', requireAdmin('approver'), (req: AuthedRequest, res) => {
  const body = z.object({ creditLimitCents: z.number().int().min(0).max(20000000), reason: z.string().optional() }).parse(req.body);
  const user = db.prepare('SELECT * FROM users WHERE id=?').get(req.params.id) as any;
  if (!user) throw new ApiError(ErrCode.NOT_FOUND);
  db.prepare('UPDATE users SET credit_limit_cents=?, updated_at=? WHERE id=?').run(body.creditLimitCents, nowIso(), user.id);
  notify(user.id, 'risk', '额度调整通知', `您的额度已调整为 ¥${(body.creditLimitCents / 100).toFixed(2)}。`);
  audit('admin', req.admin!.sub, 'user.limit_adjust', 'user', req.params.id, { before: user.credit_limit_cents, ...body }, req.ip);
  ok(res, null, '额度已调整');
});

adminRouter.post('/users/:id/status', requireAdmin('approver'), (req: AuthedRequest, res) => {
  const body = z.object({ status: z.enum(['active', 'frozen']), blacklist: z.boolean().optional(), reason: z.string().optional() }).parse(req.body);
  const user = db.prepare('SELECT * FROM users WHERE id=?').get(req.params.id) as any;
  if (!user) throw new ApiError(ErrCode.NOT_FOUND);
  db.prepare('UPDATE users SET status=?, blacklist=COALESCE(?,blacklist), updated_at=? WHERE id=?').run(
    body.status,
    body.blacklist == null ? null : body.blacklist ? 1 : 0,
    nowIso(),
    user.id
  );
  audit('admin', req.admin!.sub, 'user.status', 'user', req.params.id, body, req.ip);
  ok(res, null, '状态已更新');
});

// ==================== 风控规则 ====================

adminRouter.get('/risk-rules', (_req, res) => {
  const rows = db.prepare('SELECT * FROM risk_rules ORDER BY priority ASC').all() as any[];
  ok(res, { list: rows });
});

adminRouter.patch('/risk-rules/:id', requireAdmin('risk'), (req: AuthedRequest, res) => {
  const body = z
    .object({ enabled: z.boolean().optional(), value: z.string().optional(), action: z.string().optional(), scoreDelta: z.number().int().optional(), priority: z.number().int().optional() })
    .parse(req.body);
  const rule = db.prepare('SELECT * FROM risk_rules WHERE id=?').get(req.params.id) as any;
  if (!rule) throw new ApiError(ErrCode.NOT_FOUND);
  db.prepare(
    `UPDATE risk_rules SET enabled=COALESCE(?,enabled), value=COALESCE(?,value), action=COALESCE(?,action),
     score_delta=COALESCE(?,score_delta), priority=COALESCE(?,priority), updated_at=? WHERE id=?`
  ).run(
    body.enabled == null ? null : body.enabled ? 1 : 0,
    body.value ?? null,
    body.action ?? null,
    body.scoreDelta ?? null,
    body.priority ?? null,
    nowIso(),
    rule.id
  );
  audit('admin', req.admin!.sub, 'risk_rule.update', 'risk_rule', rule.id, body, req.ip);
  ok(res, null, '规则已更新');
});

adminRouter.get('/risk-decisions', (req, res) => {
  const rows = db
    .prepare(
      `SELECT d.*, u.phone FROM risk_decisions d JOIN users u ON u.id=d.user_id ORDER BY d.id DESC LIMIT 100`
    )
    .all() as any[];
  ok(res, {
    list: rows.map((r) => ({
      id: r.id,
      phone: maskPhone(r.phone),
      scene: r.scene,
      score: r.score,
      decision: r.decision,
      hitRules: r.hit_rules ? JSON.parse(r.hit_rules) : [],
      createdAt: r.created_at,
    })),
  });
});

// ==================== 优惠券 ====================

adminRouter.get('/coupons', (_req, res) => {
  ok(res, { list: db.prepare('SELECT * FROM coupons ORDER BY id DESC').all() });
});

adminRouter.post('/coupons', requireAdmin('ops'), (req: AuthedRequest, res) => {
  const body = z
    .object({
      code: z.string().min(2),
      name: z.string().min(2),
      type: z.enum(['cash', 'rate']),
      amountCents: z.number().int().min(0).default(0),
      rateOffBp: z.number().int().min(0).default(0),
      minAmountCents: z.number().int().min(0).default(0),
      termLimit: z.number().int().min(0).default(0),
      validFrom: z.string(),
      validTo: z.string(),
      totalQty: z.number().int().min(0).default(0),
    })
    .parse(req.body);
  const info = db
    .prepare(
      `INSERT INTO coupons(code,name,type,amount_cents,rate_off_bp,min_amount_cents,term_limit,valid_from,valid_to,total_qty,status,created_at)
       VALUES(?,?,?,?,?,?,?,?,?,?,'active',?)`
    )
    .run(
      body.code,
      body.name,
      body.type,
      body.amountCents,
      body.rateOffBp,
      body.minAmountCents,
      body.termLimit,
      body.validFrom,
      body.validTo,
      body.totalQty,
      nowIso()
    );
  audit('admin', req.admin!.sub, 'coupon.create', 'coupon', Number(info.lastInsertRowid), body, req.ip);
  ok(res, { id: Number(info.lastInsertRowid) }, '优惠券已创建');
});

adminRouter.patch('/coupons/:id', requireAdmin('ops'), (req: AuthedRequest, res) => {
  const body = z.object({ status: z.enum(['active', 'inactive']) }).parse(req.body);
  db.prepare('UPDATE coupons SET status=? WHERE id=?').run(body.status, req.params.id);
  audit('admin', req.admin!.sub, 'coupon.status', 'coupon', req.params.id, body, req.ip);
  ok(res, null, '已更新');
});

// ==================== 运营配置 ====================

adminRouter.get('/settings', (_req, res) => {
  const rows = db.prepare('SELECT * FROM settings').all() as any[];
  const out: Record<string, string> = {};
  for (const r of rows) out[r.key] = r.value;
  ok(res, { settings: out });
});

adminRouter.put('/settings', requireAdmin('ops'), (req: AuthedRequest, res) => {
  const body = z.record(z.string()).parse(req.body);
  for (const [k, v] of Object.entries(body)) {
    let parsed: unknown = v;
    try {
      parsed = JSON.parse(v);
    } catch {
      /* 保持字符串 */
    }
    setSetting(k, parsed);
  }
  audit('admin', req.admin!.sub, 'settings.update', 'settings', null, body, req.ip);
  ok(res, null, '配置已保存');
});

adminRouter.get('/audit-logs', (req, res) => {
  const rows = db.prepare('SELECT * FROM audit_logs ORDER BY id DESC LIMIT 200').all();
  ok(res, { list: rows });
});
