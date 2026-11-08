import { Router } from 'express';
import { z } from 'zod';
import { db, tx } from '../db.js';
import { ApiError, ErrCode, ok } from '../lib/http.js';
import { genInviteCode, genSmsCode } from '../lib/id.js';
import { nowIso } from '../lib/date.js';
import { hashPassword, maskPhone, verifyPassword, encryptPII, maskIdCard, validateIdCard } from '../lib/security.js';
import { requireUser, signUserToken, type AuthedRequest } from '../middleware/auth.js';
import { notify } from '../services/notify.js';

export const authRouter = Router();

const smsStore = new Map<string, { code: string; expireAt: number; sentAt: number }>();
const SMS_TTL = 5 * 60 * 1000;

function issueSms(phone: string) {
  const code = genSmsCode();
  smsStore.set(phone, { code, expireAt: Date.now() + SMS_TTL, sentAt: Date.now() });
  return code;
}

function verifySms(phone: string, code: string) {
  const rec = smsStore.get(phone);
  // 开发环境允许万能码 123456，便于联调与自动化测试
  const devBypass = process.env.NODE_ENV !== 'production' && code === '123456';
  if (devBypass) return true;
  if (!rec || rec.expireAt < Date.now() || rec.code !== code) return false;
  smsStore.delete(phone);
  return true;
}

/** 发送验证码（演示环境直接返回，生产对接短信网关） */
authRouter.post('/sms-code', (req, res) => {
  const body = z.object({ phone: z.string().regex(/^1[3-9]\d{9}$/, '手机号格式不正确'), scene: z.string().optional() }).parse(req.body);
  const prev = smsStore.get(body.phone);
  if (prev && Date.now() - prev.sentAt < 60_000) throw new ApiError(ErrCode.SMS_TOO_FREQUENT);
  const code = issueSms(body.phone);
  ok(res, { phone: maskPhone(body.phone), expireIn: 300, devCode: code });
});

/** 注册 / 登录（验证码） */
authRouter.post('/login', (req, res) => {
  const body = z
    .object({
      phone: z.string().regex(/^1[3-9]\d{9}$/),
      code: z.string().length(6),
      inviteCode: z.string().optional(),
      agreed: z.boolean().optional(),
    })
    .parse(req.body);
  if (!verifySms(body.phone, body.code)) throw new ApiError(ErrCode.SMS_CODE);

  let user = db.prepare('SELECT * FROM users WHERE phone = ?').get(body.phone) as any;
  const now = nowIso();

  if (!user) {
    const newId = tx(() => {
      let inviteCode = genInviteCode();
      while (db.prepare('SELECT 1 FROM users WHERE invite_code = ?').get(inviteCode)) inviteCode = genInviteCode();
      let inviterId: number | null = null;
      if (body.inviteCode) {
        const inviter = db.prepare('SELECT * FROM users WHERE invite_code = ?').get(body.inviteCode) as any;
        if (inviter) inviterId = inviter.id;
      }
      const info = db
        .prepare(
          `INSERT INTO users(phone, invite_code, invited_by, status, created_at, updated_at, last_login_at)
           VALUES(?,?,?,'active',?,?,?)`
        )
        .run(body.phone, inviteCode, inviterId, now, now, now);
      const id = Number(info.lastInsertRowid);
      db.prepare(`INSERT INTO user_profiles(user_id, updated_at) VALUES(?,?)`).run(id, now);
      db.prepare(`INSERT INTO bank_cards(user_id, bank_name, bank_code, card_no_enc, card_no_mask, holder_name, phone, is_default, status, created_at)
                  VALUES(?,?,?,?,?,?,?,1,'active',?)`).run(
        id,
        '招商银行',
        'CMB',
        encryptPII(`622588${String(1000000000000 + id).slice(-13)}`),
        '**** **** **** ' + String(1000 + (id % 9000)),
        null,
        body.phone,
        now
      );
      db.prepare(
        `INSERT INTO user_coupons(user_id, coupon_id, status, received_at)
         SELECT ?, id, 'unused', ? FROM coupons WHERE status='active' AND code IN ('NEW20','RATE01')`
      ).run(id, now);
      if (inviterId) {
        db.prepare(
          `INSERT INTO invitations(inviter_id, invitee_id, invitee_phone, status, reward_cents, reward_status, created_at, updated_at)
           VALUES(?,?,?,'registered',0,'pending',?,?)`
        ).run(inviterId, id, body.phone, now, now);
        notify(inviterId, 'marketing', '邀请好友已注册', `您邀请的好友 ${maskPhone(body.phone)} 已完成注册，待其完成首借后发放奖励。`);
      }
      return id;
    });
    user = db.prepare('SELECT * FROM users WHERE id = ?').get(newId);
  } else {
    if (user.status === 'frozen') throw new ApiError(ErrCode.ACCOUNT_FROZEN);
    if (user.status === 'closed') throw new ApiError(ErrCode.ACCOUNT_CLOSED);
    db.prepare('UPDATE users SET last_login_at = ?, updated_at = ? WHERE id = ?').run(now, now, user.id);
  }

  const token = signUserToken(user.id, user.phone);
  ok(res, {
    token,
    user: {
      id: user.id,
      phone: maskPhone(user.phone),
      name: user.name,
      inviteCode: user.invite_code,
      status: user.status,
      isNew: !user.name,
    },
  });
});

/** 密码登录 */
authRouter.post('/login-password', (req, res) => {
  const body = z.object({ phone: z.string(), password: z.string().min(6) }).parse(req.body);
  const user = db.prepare('SELECT * FROM users WHERE phone = ?').get(body.phone) as any;
  if (!user || !verifyPassword(body.password, user.password_hash)) throw new ApiError(ErrCode.PASSWORD);
  if (user.status === 'frozen') throw new ApiError(ErrCode.ACCOUNT_FROZEN);
  if (user.status === 'closed') throw new ApiError(ErrCode.ACCOUNT_CLOSED);
  db.prepare('UPDATE users SET last_login_at = ? WHERE id = ?').run(nowIso(), user.id);
  ok(res, { token: signUserToken(user.id, user.phone), user: { id: user.id, phone: maskPhone(user.phone), name: user.name } });
});

authRouter.post('/password', requireUser, (req: AuthedRequest, res) => {
  const body = z.object({ oldPassword: z.string().optional(), password: z.string().min(6).max(20) }).parse(req.body);
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user!.sub) as any;
  if (user.password_hash && body.oldPassword && !verifyPassword(body.oldPassword, user.password_hash)) {
    throw new ApiError(ErrCode.PASSWORD, '原密码不正确');
  }
  db.prepare('UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?').run(hashPassword(body.password), nowIso(), user.id);
  ok(res, null, '设置成功');
});

authRouter.get('/me', requireUser, (req: AuthedRequest, res) => {
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user!.sub) as any;
  if (!user) throw new ApiError(ErrCode.UNAUTHORIZED);
  ok(res, {
    id: user.id,
    phone: maskPhone(user.phone),
    name: user.name,
    idCardMask: user.id_card_mask,
    status: user.status,
    inviteCode: user.invite_code,
    riskLevel: user.risk_level,
    createdAt: user.created_at,
  });
});

/** 注销账户（冷静期 7 天，此处直接标记） */
authRouter.post('/close', requireUser, (req: AuthedRequest, res) => {
  const userId = req.user!.sub;
  const active = db.prepare(`SELECT COUNT(*) c FROM loans WHERE user_id = ? AND status IN ('active','overdue')`).get(userId) as any;
  if (active.c > 0) throw new ApiError(ErrCode.CONFLICT, '存在未结清借款，暂无法注销');
  db.prepare(`UPDATE users SET status='closed', updated_at=? WHERE id=?`).run(nowIso(), userId);
  ok(res, null, '账户已注销');
});
