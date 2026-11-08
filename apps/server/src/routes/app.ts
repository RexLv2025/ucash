import { Router } from 'express';
import { z } from 'zod';
import { db, tx, getSetting } from '../db.js';
import { ApiError, ErrCode, ok } from '../lib/http.js';
import { nowIso, todayDateStr, todayStr } from '../lib/date.js';
import { maskPhone, maskIdCard, encryptPII, validateIdCard, birthYearFromId, genderFromId, maskBankCard } from '../lib/security.js';
import { requireUser, type AuthedRequest } from '../middleware/auth.js';
import { assertVerified, currentCredit, refreshLimit, submitCredit } from '../services/credit.js';
import { createLoan, getLoan, listLoans, quote, retryDisburse, currentLoanSummary } from '../services/loan.js';
import { getBills, listRepayments, repay, repayQuote, markOverdue } from '../services/repay.js';
import { notify } from '../services/notify.js';

export const appRouter = Router();
appRouter.use(requireUser);

/** 幂等：同一 Idempotency-Key 在 24h 内复用首次响应，防止双击/重放导致重复扣款 */
function idempotent<T>(req: AuthedRequest, scope: string, fn: () => T): T {
  const key = req.header('Idempotency-Key');
  if (!key) return fn();
  const uid = req.user!.sub;
  const existing = db.prepare('SELECT response FROM idempotency_keys WHERE key = ? AND user_id = ?').get(key, uid) as any;
  if (existing) return JSON.parse(existing.response) as T;
  const result = fn();
  db.prepare('INSERT OR REPLACE INTO idempotency_keys(key, user_id, scope, response, created_at) VALUES(?,?,?,?,?)').run(
    key,
    uid,
    scope,
    JSON.stringify(result),
    nowIso()
  );
  return result;
}

// ==================== KYC 认证 ====================

appRouter.get('/kyc/status', (req: AuthedRequest, res) => {
  const p = db.prepare('SELECT * FROM user_profiles WHERE user_id = ?').get(req.user!.sub) as any;
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user!.sub) as any;
  const steps = [
    { key: 'realname', title: '实名认证', done: Boolean(p?.realname_verified) },
    { key: 'face', title: '人脸识别', done: Boolean(p?.face_verified) },
    { key: 'contacts', title: '紧急联系人', done: Boolean(p?.contacts_verified) },
  ];
  ok(res, {
    name: user.name,
    idCardMask: user.id_card_mask,
    gender: p?.gender,
    birthYear: p?.birth_year,
    city: p?.city,
    occupation: p?.occupation,
    company: p?.company,
    monthlyIncomeCents: p?.monthly_income_cents,
    steps,
    doneCount: steps.filter((s) => s.done).length,
    allDone: steps.every((s) => s.done),
    boosts: {
      provider: Boolean(p?.provider_verified),
      fund: Boolean(p?.fund_verified),
      cardbill: Boolean(p?.cardbill_verified),
    },
    contacts: p?.contacts_verified
      ? [
          { name: p.contact1_name, phone: maskPhone(p.contact1_phone) },
          { name: p.contact2_name, phone: maskPhone(p.contact2_phone) },
        ]
      : [],
  });
});

appRouter.post('/kyc/realname', (req: AuthedRequest, res) => {
  const body = z
    .object({
      realName: z.string().min(2).max(20),
      idCard: z.string().min(15).max(18),
      city: z.string().optional(),
      occupation: z.string().optional(),
      company: z.string().optional(),
      monthlyIncomeCents: z.number().int().min(0).optional(),
    })
    .parse(req.body);
  if (!validateIdCard(body.idCard)) throw new ApiError(ErrCode.PARAM, '身份证号校验不通过');
  const age = new Date().getFullYear() - (birthYearFromId(body.idCard) ?? 1990);
  if (age < 22 || age > 55) throw new ApiError(ErrCode.UNDERAGE, '年龄需在 22-55 周岁之间');
  if (body.occupation && body.occupation.includes('学生')) throw new ApiError(ErrCode.UNDERAGE);

  const dup = db.prepare('SELECT id FROM users WHERE id_card_mask = ? AND id != ?').get(maskIdCard(body.idCard), req.user!.sub) as any;
  if (dup) throw new ApiError(ErrCode.ID_BOUND);

  const now = nowIso();
  tx(() => {
    db.prepare('UPDATE users SET name = ?, id_card_enc = ?, id_card_mask = ?, updated_at = ? WHERE id = ?').run(
      body.realName,
      encryptPII(body.idCard),
      maskIdCard(body.idCard),
      now,
      req.user!.sub
    );
    db.prepare(
      `UPDATE user_profiles SET gender = ?, birth_year = ?, city = COALESCE(?, city), occupation = COALESCE(?, occupation),
       company = COALESCE(?, company), monthly_income_cents = COALESCE(?, monthly_income_cents),
       realname_verified = 1, updated_at = ? WHERE user_id = ?`
    ).run(
      genderFromId(body.idCard),
      birthYearFromId(body.idCard),
      body.city ?? null,
      body.occupation ?? null,
      body.company ?? null,
      body.monthlyIncomeCents ?? null,
      now,
      req.user!.sub
    );
    db.prepare(
      `INSERT INTO kyc_records(user_id, real_name, id_card_enc, id_card_mask, status, created_at) VALUES(?,?,?,?,?,?)`
    ).run(req.user!.sub, body.realName, encryptPII(body.idCard), maskIdCard(body.idCard), 'passed', now);
  });
  ok(res, { next: 'face' }, '实名认证通过');
});

appRouter.post('/kyc/face', (req: AuthedRequest, res) => {
  const body = z.object({ score: z.number().min(0).max(100).optional(), liveness: z.boolean().optional() }).parse(req.body ?? {});
  const score = body.score ?? 92;
  const liveness = body.liveness ?? true;
  if (!liveness || score < 60) {
    db.prepare(`INSERT INTO kyc_records(user_id, real_name, id_card_enc, id_card_mask, face_score, face_liveness, status, reject_code, reject_reason, created_at)
                VALUES(?,?,?,?,?,?,'rejected','FACE_FAILED','活体检测未通过',?)`).run(
      req.user!.sub,
      '',
      '',
      '',
      score,
      liveness ? 1 : 0,
      nowIso()
    );
    throw new ApiError(ErrCode.FACE_FAILED);
  }
  tx(() => {
    db.prepare('UPDATE user_profiles SET face_verified = 1, updated_at = ? WHERE user_id = ?').run(nowIso(), req.user!.sub);
    db.prepare(`UPDATE kyc_records SET face_score = ?, face_liveness = 1 WHERE user_id = ?`).run(score, req.user!.sub);
  });
  ok(res, { score, next: 'contacts' }, '人脸识别通过');
});

appRouter.post('/kyc/contacts', (req: AuthedRequest, res) => {
  const phone = z.string().regex(/^1[3-9]\d{9}$/);
  const body = z
    .object({
      contact1Name: z.string().min(1).max(20),
      contact1Phone: phone,
      contact2Name: z.string().min(1).max(20),
      contact2Phone: phone,
    })
    .parse(req.body);
  const me = db.prepare('SELECT phone FROM users WHERE id = ?').get(req.user!.sub) as any;
  if (body.contact1Phone === me.phone || body.contact2Phone === me.phone) throw new ApiError(ErrCode.PARAM, '联系人不能填写本人手机号');
  if (body.contact1Phone === body.contact2Phone) throw new ApiError(ErrCode.PARAM, '两位联系人不能重复');
  db.prepare(
    `UPDATE user_profiles SET contact1_name=?, contact1_phone=?, contact2_name=?, contact2_phone=?, contacts_verified=1, updated_at=?
     WHERE user_id=?`
  ).run(body.contact1Name, body.contact1Phone, body.contact2Name, body.contact2Phone, nowIso(), req.user!.sub);
  ok(res, { next: 'credit' }, '联系人授权成功');
});

/** 提额认证（运营商 / 公积金 / 信用卡账单） */
appRouter.post('/kyc/boost', (req: AuthedRequest, res) => {
  const body = z.object({ type: z.enum(['provider', 'fund', 'cardbill']) }).parse(req.body);
  const map: Record<string, string> = { provider: 'provider_verified', fund: 'fund_verified', cardbill: 'cardbill_verified' };
  db.prepare(`UPDATE user_profiles SET ${map[body.type]} = 1, updated_at = ? WHERE user_id = ?`).run(nowIso(), req.user!.sub);
  const r = refreshLimit(req.user!.sub);
  ok(res, { type: body.type, limitBeforeCents: r.before, limitAfterCents: r.after }, r.before > 0 ? '认证成功，额度已更新' : '认证成功，额度将在授信通过后生效');
});

// ==================== 授信 ====================

appRouter.get('/credit', (req: AuthedRequest, res) => {
  ok(res, currentCredit(req.user!.sub));
});

appRouter.post('/credit/applications', (req: AuthedRequest, res) => {
  const body = z.object({ amountCents: z.number().int().min(50000).max(20000000), purpose: z.string().optional() }).parse(req.body);
  const r = submitCredit(req.user!.sub, body);
  const credit = currentCredit(req.user!.sub);
  ok(res, { ...r, credit }, r.status === 'approved' ? '额度已激活' : r.status === 'rejected' ? '本次申请未通过' : '申请已提交，等待审核');
});

appRouter.get('/credit/applications/:id', (req: AuthedRequest, res) => {
  const app = db.prepare('SELECT * FROM credit_applications WHERE id = ? AND user_id = ?').get(req.params.id, req.user!.sub) as any;
  if (!app) throw new ApiError(ErrCode.NOT_FOUND);
  const snapshot = app.risk_snapshot ? JSON.parse(app.risk_snapshot) : null;
  ok(res, {
    id: app.id,
    status: app.status,
    score: app.score,
    approvedLimitCents: app.approved_limit_cents,
    interestRateBp: app.interest_rate_bp,
    rejectCode: app.reject_code,
    rejectReason: app.reject_reason,
    expiresAt: app.expires_at,
    createdAt: app.created_at,
    hitRules: snapshot?.hitRules ?? [],
  });
});

// ==================== 借款 ====================

appRouter.post('/loans/quote', (req: AuthedRequest, res) => {
  const body = z
    .object({
      amountCents: z.number().int(),
      termMonths: z.number().int(),
      couponId: z.number().int().nullable().optional(),
    })
    .parse(req.body);
  ok(res, quote(req.user!.sub, body));
});

appRouter.post('/loans', (req: AuthedRequest, res) => {
  const body = z
    .object({
      quoteToken: z.string().min(10),
      bankCardId: z.number().int(),
      purpose: z.string().optional(),
      contractSigned: z.boolean(),
    })
    .parse(req.body);
  const data = idempotent(req, 'loan.create', () => createLoan(req.user!.sub, body));
  ok(res, data, '借款申请已提交');
});

appRouter.get('/loans', (req: AuthedRequest, res) => {
  ok(res, { list: listLoans(req.user!.sub, req.query.status as string | undefined) });
});

appRouter.get('/loans/summary/current', (req: AuthedRequest, res) => {
  ok(res, currentLoanSummary(req.user!.sub));
});

appRouter.get('/loans/:id', (req: AuthedRequest, res) => {
  ok(res, getLoan(req.user!.sub, Number(req.params.id)));
});

appRouter.post('/loans/:id/retry', (req: AuthedRequest, res) => {
  const body = z.object({ bankCardId: z.number().int() }).parse(req.body);
  ok(res, retryDisburse(req.user!.sub, Number(req.params.id), body.bankCardId), '已重新提交放款');
});

// ==================== 账单与还款 ====================

appRouter.get('/bills', (req: AuthedRequest, res) => {
  ok(res, getBills(req.user!.sub));
});

appRouter.get('/repayments/quote', (req: AuthedRequest, res) => {
  const loanId = Number(req.query.loanId);
  const type = (req.query.type as string) === 'settle' ? 'settle' : 'normal';
  if (!loanId) throw new ApiError(ErrCode.PARAM);
  ok(res, repayQuote(req.user!.sub, loanId, type));
});

appRouter.post('/repayments', (req: AuthedRequest, res) => {
  const body = z
    .object({ loanId: z.number().int(), type: z.enum(['normal', 'settle']), bankCardId: z.number().int() })
    .parse(req.body);
  const data = idempotent(req, 'repay.create', () => repay(req.user!.sub, body));
  ok(res, data, '还款成功');
});

appRouter.get('/repayments', (req: AuthedRequest, res) => {
  ok(res, { list: listRepayments(req.user!.sub) });
});

// ==================== 我的 ====================

appRouter.get('/me/profile', (req: AuthedRequest, res) => {
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user!.sub) as any;
  const p = db.prepare('SELECT * FROM user_profiles WHERE user_id = ?').get(req.user!.sub) as any;
  const credit = currentCredit(req.user!.sub);
  const couponCount = (db.prepare(`SELECT COUNT(*) c FROM user_coupons WHERE user_id = ? AND status='unused'`).get(req.user!.sub) as any).c;
  const unread = (db.prepare(`SELECT COUNT(*) c FROM messages WHERE user_id = ? AND read_at IS NULL`).get(req.user!.sub) as any).c;
  const inviteCount = (db.prepare(`SELECT COUNT(*) c FROM invitations WHERE inviter_id = ?`).get(req.user!.sub) as any).c;
  ok(res, {
    user: {
      id: user.id,
      phone: maskPhone(user.phone),
      name: user.name,
      idCardMask: user.id_card_mask,
      inviteCode: user.invite_code,
      riskLevel: user.risk_level,
      status: user.status,
    },
    profile: {
      gender: p?.gender,
      birthYear: p?.birth_year,
      city: p?.city,
      occupation: p?.occupation,
      company: p?.company,
      monthlyIncomeCents: p?.monthly_income_cents,
      verified: {
        realname: Boolean(p?.realname_verified),
        face: Boolean(p?.face_verified),
        contacts: Boolean(p?.contacts_verified),
      },
      boosts: { provider: Boolean(p?.provider_verified), fund: Boolean(p?.fund_verified), cardbill: Boolean(p?.cardbill_verified) },
    },
    credit,
    counters: { coupons: couponCount, unreadMessages: unread, invitations: inviteCount },
  });
});

appRouter.patch('/me/profile', (req: AuthedRequest, res) => {
  const body = z
    .object({ city: z.string().optional(), occupation: z.string().optional(), company: z.string().optional(), monthlyIncomeCents: z.number().int().optional() })
    .parse(req.body);
  db.prepare(
    `UPDATE user_profiles SET city=COALESCE(?,city), occupation=COALESCE(?,occupation), company=COALESCE(?,company),
     monthly_income_cents=COALESCE(?,monthly_income_cents), updated_at=? WHERE user_id=?`
  ).run(body.city ?? null, body.occupation ?? null, body.company ?? null, body.monthlyIncomeCents ?? null, nowIso(), req.user!.sub);
  ok(res, null, '资料已更新');
});

// ==================== 银行卡 ====================

appRouter.get('/cards', (req: AuthedRequest, res) => {
  const rows = db.prepare('SELECT * FROM bank_cards WHERE user_id = ? ORDER BY is_default DESC, id ASC').all(req.user!.sub) as any[];
  ok(res, {
    list: rows.map((r) => ({
      id: r.id,
      bankName: r.bank_name,
      bankCode: r.bank_code,
      cardNoMask: r.card_no_mask,
      holderName: r.holder_name,
      isDefault: Boolean(r.is_default),
      status: r.status,
    })),
  });
});

appRouter.post('/cards', (req: AuthedRequest, res) => {
  const body = z
    .object({
      bankName: z.string().min(2),
      cardNo: z.string().regex(/^\d{16,19}$/, '银行卡号格式不正确'),
      holderName: z.string().min(2),
      phone: z.string().regex(/^1[3-9]\d{9}$/),
      isDefault: z.boolean().optional(),
    })
    .parse(req.body);
  const now = nowIso();
  const id = tx(() => {
    if (body.isDefault) db.prepare('UPDATE bank_cards SET is_default = 0 WHERE user_id = ?').run(req.user!.sub);
    const info = db
      .prepare(
        `INSERT INTO bank_cards(user_id, bank_name, bank_code, card_no_enc, card_no_mask, holder_name, phone, is_default, status, created_at)
         VALUES(?,?,?,?,?,?,?,?,'active',?)`
      )
      .run(
        req.user!.sub,
        body.bankName,
        body.bankName.slice(0, 3),
        encryptPII(body.cardNo),
        maskBankCard(body.cardNo),
        body.holderName,
        body.phone,
        body.isDefault ? 1 : 0,
        now
      );
    return Number(info.lastInsertRowid);
  });
  ok(res, { id }, '银行卡已添加');
});

appRouter.post('/cards/:id/default', (req: AuthedRequest, res) => {
  tx(() => {
    db.prepare('UPDATE bank_cards SET is_default = 0 WHERE user_id = ?').run(req.user!.sub);
    db.prepare('UPDATE bank_cards SET is_default = 1 WHERE id = ? AND user_id = ?').run(req.params.id, req.user!.sub);
  });
  ok(res, null, '已设为默认卡');
});

appRouter.delete('/cards/:id', (req: AuthedRequest, res) => {
  const active = db.prepare(`SELECT COUNT(*) c FROM loans WHERE user_id = ? AND status IN ('active','overdue')`).get(req.user!.sub) as any;
  const count = (db.prepare('SELECT COUNT(*) c FROM bank_cards WHERE user_id = ?').get(req.user!.sub) as any).c;
  if (count <= 1) throw new ApiError(ErrCode.CONFLICT, '至少保留一张银行卡');
  db.prepare('DELETE FROM bank_cards WHERE id = ? AND user_id = ?').run(req.params.id, req.user!.sub);
  ok(res, { activeLoans: active.c }, '银行卡已解绑');
});

// ==================== 优惠券 ====================

appRouter.get('/coupons', (req: AuthedRequest, res) => {
  const status = (req.query.status as string) || 'unused';
  const rows = db
    .prepare(
      `SELECT uc.id, uc.status, uc.received_at, uc.used_at, c.code, c.name, c.type, c.amount_cents, c.rate_off_bp,
              c.min_amount_cents, c.term_limit, c.valid_from, c.valid_to
       FROM user_coupons uc JOIN coupons c ON c.id = uc.coupon_id
       WHERE uc.user_id = ? AND uc.status = ? ORDER BY uc.id DESC`
    )
    .all(req.user!.sub, status) as any[];
  const available = db
    .prepare(
      `SELECT c.* FROM coupons c WHERE c.status='active' AND c.valid_to >= ? AND c.id NOT IN
       (SELECT coupon_id FROM user_coupons WHERE user_id = ?)`
    )
    .all(todayDateStr(), req.user!.sub) as any[];
  ok(res, {
    list: rows.map((r) => ({
      id: r.id,
      couponId: r.code,
      name: r.name,
      type: r.type,
      amountCents: r.amount_cents,
      rateOffBp: r.rate_off_bp,
      minAmountCents: r.min_amount_cents,
      termLimit: r.term_limit,
      validFrom: r.valid_from,
      validTo: r.valid_to,
      status: r.status,
    })),
    available: available.map((c) => ({
      id: c.id,
      code: c.code,
      name: c.name,
      type: c.type,
      amountCents: c.amount_cents,
      rateOffBp: c.rate_off_bp,
      minAmountCents: c.min_amount_cents,
      termLimit: c.term_limit,
    })),
  });
});

appRouter.post('/coupons/:id/receive', (req: AuthedRequest, res) => {
  const coupon = db.prepare(`SELECT * FROM coupons WHERE id = ? AND status='active'`).get(req.params.id) as any;
  if (!coupon) throw new ApiError(ErrCode.NOT_FOUND, '优惠券不存在');
  const exist = db.prepare('SELECT 1 FROM user_coupons WHERE user_id = ? AND coupon_id = ?').get(req.user!.sub, coupon.id);
  if (exist) throw new ApiError(ErrCode.CONFLICT, '您已领取该优惠券');
  db.prepare(`INSERT INTO user_coupons(user_id, coupon_id, status, received_at) VALUES(?,?,'unused',?)`).run(
    req.user!.sub,
    coupon.id,
    nowIso()
  );
  ok(res, null, '领取成功');
});

// ==================== 邀请 ====================

appRouter.get('/invitations', (req: AuthedRequest, res) => {
  const user = db.prepare('SELECT invite_code FROM users WHERE id = ?').get(req.user!.sub) as any;
  const rows = db.prepare('SELECT * FROM invitations WHERE inviter_id = ? ORDER BY id DESC').all(req.user!.sub) as any[];
  const granted = rows.filter((r) => r.reward_status === 'granted').reduce((s, r) => s + r.reward_cents, 0);
  ok(res, {
    inviteCode: user.invite_code,
    totalInvited: rows.length,
    totalRewardCents: granted,
    pendingRewardCents: rows.filter((r) => r.reward_status === 'pending').reduce((s, r) => s + r.reward_cents, 0),
    list: rows.map((r) => ({ phone: maskPhone(r.invitee_phone), status: r.status, rewardCents: r.reward_cents, createdAt: r.created_at })),
  });
});

appRouter.post('/invitations/bind', (req: AuthedRequest, res) => {
  const body = z.object({ inviteCode: z.string().length(6) }).parse(req.body);
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user!.sub) as any;
  if (user.invited_by) throw new ApiError(ErrCode.CONFLICT, '已绑定邀请关系');
  const inviter = db.prepare('SELECT * FROM users WHERE invite_code = ?').get(body.inviteCode) as any;
  if (!inviter || inviter.id === user.id) throw new ApiError(ErrCode.PARAM, '邀请码无效');
  db.prepare('UPDATE users SET invited_by = ? WHERE id = ?').run(inviter.id, user.id);
  db.prepare(`UPDATE invitations SET invitee_id = ? WHERE invitee_phone = ? AND invitee_id IS NULL`).run(user.id, user.phone);
  ok(res, null, '邀请关系已绑定');
});

// ==================== 消息 ====================

appRouter.get('/messages', (req: AuthedRequest, res) => {
  const rows = db.prepare('SELECT * FROM messages WHERE user_id = ? ORDER BY id DESC LIMIT 100').all(req.user!.sub) as any[];
  ok(res, {
    list: rows.map((r) => ({
      id: r.id,
      type: r.type,
      title: r.title,
      content: r.content,
      read: Boolean(r.read_at),
      createdAt: r.created_at,
    })),
    unread: rows.filter((r) => !r.read_at).length,
  });
});

appRouter.post('/messages/:id/read', (req: AuthedRequest, res) => {
  db.prepare('UPDATE messages SET read_at = ? WHERE id = ? AND user_id = ?').run(nowIso(), req.params.id, req.user!.sub);
  ok(res, null);
});

appRouter.post('/messages/read-all', (req: AuthedRequest, res) => {
  db.prepare('UPDATE messages SET read_at = ? WHERE user_id = ? AND read_at IS NULL').run(nowIso(), req.user!.sub);
  ok(res, null, '已全部标为已读');
});

// ==================== 公共配置 ====================

appRouter.get('/settings', (req: AuthedRequest, res) => {
  ok(res, {
    servicePhone: getSetting('service_phone', '400-000-8888'),
    serviceTime: getSetting('service_time', '09:00-21:00'),
    banners: getSetting('banners', []),
    notice: getSetting('notice', ''),
    agreements: getSetting('agreements', {}),
    minAmountCents: 50000,
    maxAmountCents: 5000000,
    terms: [3, 6, 12],
    appVersion: getSetting('app_version', '2.4.0'),
  });
});

/** 逾期扫描（测试与运营手动触发） */
appRouter.post('/internal/overdue-scan', (req: AuthedRequest, res) => {
  ok(res, markOverdue());
});
