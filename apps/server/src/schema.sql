-- UCash 数据库结构（SQLite）
-- 金额统一使用「整数分」存储；时间统一 ISO8601 字符串（本地时区 +08:00）

PRAGMA foreign_keys = ON;

-- ========== 用户与账户 ==========
CREATE TABLE IF NOT EXISTS users (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  phone             TEXT NOT NULL UNIQUE,
  password_hash     TEXT,
  name              TEXT,
  id_card_enc       TEXT,
  id_card_mask      TEXT,
  status            TEXT NOT NULL DEFAULT 'active',      -- active | frozen | closed
  credit_limit_cents INTEGER NOT NULL DEFAULT 0,          -- 总额度
  used_limit_cents  INTEGER NOT NULL DEFAULT 0,           -- 已用额度（在贷本金余额）
  frozen_limit_cents INTEGER NOT NULL DEFAULT 0,          -- 冻结额度（审批中订单占用）
  blacklist         INTEGER NOT NULL DEFAULT 0,
  risk_level        TEXT NOT NULL DEFAULT 'NR',           -- NR | A | B | C | D
  invite_code       TEXT UNIQUE,
  invited_by        INTEGER REFERENCES users(id),
  last_login_at     TEXT,
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS user_profiles (
  user_id            INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  gender             TEXT,
  birth_year         INTEGER,
  city               TEXT,
  occupation         TEXT,
  company            TEXT,
  monthly_income_cents INTEGER,
  education          TEXT,
  marital            TEXT,
  contact1_name      TEXT,
  contact1_phone     TEXT,
  contact2_name      TEXT,
  contact2_phone     TEXT,
  realname_verified  INTEGER NOT NULL DEFAULT 0,
  face_verified      INTEGER NOT NULL DEFAULT 0,
  contacts_verified  INTEGER NOT NULL DEFAULT 0,
  provider_verified  INTEGER NOT NULL DEFAULT 0,   -- 运营商认证（提额）
  fund_verified      INTEGER NOT NULL DEFAULT 0,   -- 公积金认证（提额）
  cardbill_verified  INTEGER NOT NULL DEFAULT 0,   -- 信用卡账单认证（提额）
  updated_at         TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS kyc_records (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id       INTEGER NOT NULL REFERENCES users(id),
  real_name     TEXT NOT NULL,
  id_card_enc   TEXT NOT NULL,
  id_card_mask  TEXT NOT NULL,
  face_score    INTEGER,        -- 活体相似度 0-100
  face_liveness INTEGER,        -- 活体检测通过 0/1
  status        TEXT NOT NULL,  -- pending | passed | rejected
  reject_code   TEXT,
  reject_reason TEXT,
  created_at    TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS bank_cards (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id        INTEGER NOT NULL REFERENCES users(id),
  bank_name      TEXT NOT NULL,
  bank_code      TEXT NOT NULL,
  card_no_enc    TEXT NOT NULL,
  card_no_mask   TEXT NOT NULL,
  holder_name    TEXT,
  phone          TEXT,
  is_default     INTEGER NOT NULL DEFAULT 0,
  status         TEXT NOT NULL DEFAULT 'active',  -- active | invalid
  created_at     TEXT NOT NULL
);

-- ========== 授信 ==========
CREATE TABLE IF NOT EXISTS credit_applications (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id               INTEGER NOT NULL REFERENCES users(id),
  apply_amount_cents    INTEGER NOT NULL,
  purpose               TEXT,
  status                TEXT NOT NULL,   -- submitted | reviewing | approved | rejected | manual
  decision              TEXT,            -- approve | reject | manual
  score                 INTEGER,
  approved_limit_cents INTEGER,
  interest_rate_bp      INTEGER,         -- 合同年利率，基点（1660 = 16.60%）
  reject_code           TEXT,
  reject_reason         TEXT,
  risk_snapshot         TEXT,            -- JSON
  reviewer_id           INTEGER,
  reviewed_at           TEXT,
  expires_at            TEXT,            -- 额度有效期
  created_at            TEXT NOT NULL,
  updated_at            TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_credit_user ON credit_applications(user_id, status);

-- ========== 借据 ==========
CREATE TABLE IF NOT EXISTS loans (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  loan_no               TEXT NOT NULL UNIQUE,
  user_id               INTEGER NOT NULL REFERENCES users(id),
  application_id        INTEGER REFERENCES credit_applications(id),
  principal_cents       INTEGER NOT NULL,
  term_months           INTEGER NOT NULL,
  interest_rate_bp      INTEGER NOT NULL,   -- 合同年利率（名义，等额本息）
  apr_bp                INTEGER NOT NULL,   -- 综合年化（IRR），展示用
  total_interest_cents  INTEGER NOT NULL,
  total_repay_cents     INTEGER NOT NULL,
  monthly_payment_cents INTEGER NOT NULL,
  coupon_id             INTEGER REFERENCES coupons(id),
  coupon_discount_cents INTEGER NOT NULL DEFAULT 0,
  bank_card_id          INTEGER REFERENCES bank_cards(id),
  purpose               TEXT,
  status                TEXT NOT NULL,   -- reviewing | disbursing | active | settled | overdue | rejected | failed
  fail_code             TEXT,
  fail_reason           TEXT,
  risk_snapshot         TEXT,
  contract_no           TEXT,
  signed_at             TEXT,
  disbursed_at          TEXT,
  first_due_date        TEXT,
  settled_at            TEXT,
  overdue_days          INTEGER NOT NULL DEFAULT 0,
  created_at            TEXT NOT NULL,
  updated_at            TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_loan_user ON loans(user_id, status);
CREATE INDEX IF NOT EXISTS idx_loan_status ON loans(status);

CREATE TABLE IF NOT EXISTS loan_schedules (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  loan_id              INTEGER NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
  period_no            INTEGER NOT NULL,
  due_date             TEXT NOT NULL,
  principal_cents      INTEGER NOT NULL,
  interest_cents       INTEGER NOT NULL,
  total_cents          INTEGER NOT NULL,
  paid_principal_cents INTEGER NOT NULL DEFAULT 0,
  paid_interest_cents  INTEGER NOT NULL DEFAULT 0,
  penalty_cents        INTEGER NOT NULL DEFAULT 0,
  status               TEXT NOT NULL DEFAULT 'unpaid',  -- unpaid | partial | paid | overdue
  paid_at              TEXT,
  UNIQUE(loan_id, period_no)
);
CREATE INDEX IF NOT EXISTS idx_schedule_loan ON loan_schedules(loan_id, period_no);
CREATE INDEX IF NOT EXISTS idx_schedule_due ON loan_schedules(status, due_date);

CREATE TABLE IF NOT EXISTS repayments (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  repayment_no   TEXT NOT NULL UNIQUE,
  user_id        INTEGER NOT NULL REFERENCES users(id),
  loan_id        INTEGER NOT NULL REFERENCES loans(id),
  type           TEXT NOT NULL,     -- normal | advance | settle
  amount_cents   INTEGER NOT NULL,
  principal_cents INTEGER NOT NULL,
  interest_cents INTEGER NOT NULL,
  penalty_cents  INTEGER NOT NULL DEFAULT 0,
  channel        TEXT NOT NULL,     -- bankcard
  bank_card_id   INTEGER,
  status         TEXT NOT NULL,     -- pending | success | failed
  period_from    INTEGER,
  period_to      INTEGER,
  fail_reason    TEXT,
  paid_at        TEXT,
  created_at     TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_repay_user ON repayments(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_repay_loan ON repayments(loan_id);

-- ========== 营销 ==========
CREATE TABLE IF NOT EXISTS coupons (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  code              TEXT NOT NULL UNIQUE,
  name              TEXT NOT NULL,
  type              TEXT NOT NULL,        -- cash（满减）| rate（免息/降息）
  amount_cents      INTEGER NOT NULL DEFAULT 0,
  rate_off_bp       INTEGER NOT NULL DEFAULT 0,  -- 降息基点（年化）
  min_amount_cents  INTEGER NOT NULL DEFAULT 0,
  term_limit        INTEGER NOT NULL DEFAULT 0,  -- 0 不限
  valid_from        TEXT NOT NULL,
  valid_to          TEXT NOT NULL,
  total_qty         INTEGER NOT NULL DEFAULT 0,
  used_qty          INTEGER NOT NULL DEFAULT 0,
  status            TEXT NOT NULL DEFAULT 'active',
  created_at        TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS user_coupons (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     INTEGER NOT NULL REFERENCES users(id),
  coupon_id   INTEGER NOT NULL REFERENCES coupons(id),
  status      TEXT NOT NULL DEFAULT 'unused',  -- unused | used | expired
  loan_id     INTEGER,
  received_at TEXT NOT NULL,
  used_at     TEXT,
  UNIQUE(user_id, coupon_id)
);

CREATE TABLE IF NOT EXISTS invitations (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  inviter_id     INTEGER NOT NULL REFERENCES users(id),
  invitee_id     INTEGER REFERENCES users(id),
  invitee_phone  TEXT NOT NULL,
  status         TEXT NOT NULL DEFAULT 'registered', -- registered | credited | borrowed | rewarded
  reward_cents   INTEGER NOT NULL DEFAULT 0,
  reward_status  TEXT NOT NULL DEFAULT 'pending',    -- pending | granted
  created_at     TEXT NOT NULL,
  updated_at     TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS messages (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id    INTEGER NOT NULL REFERENCES users(id),
  type       TEXT NOT NULL,   -- system | loan | repay | risk | marketing
  title      TEXT NOT NULL,
  content    TEXT NOT NULL,
  biz_no     TEXT,
  read_at    TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_msg_user ON messages(user_id, created_at);

-- ========== 风控 ==========
CREATE TABLE IF NOT EXISTS risk_rules (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  code        TEXT NOT NULL UNIQUE,
  name        TEXT NOT NULL,
  field       TEXT NOT NULL,
  operator    TEXT NOT NULL,   -- gte | lte | eq | neq | in | not_in | gt | lt
  value       TEXT NOT NULL,
  action      TEXT NOT NULL,   -- reject | manual | pass | score
  score_delta INTEGER NOT NULL DEFAULT 0,
  priority    INTEGER NOT NULL DEFAULT 100,
  enabled     INTEGER NOT NULL DEFAULT 1,
  description TEXT,
  updated_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS risk_decisions (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id        INTEGER NOT NULL REFERENCES users(id),
  scene          TEXT NOT NULL,       -- credit | loan
  application_id INTEGER,
  loan_id        INTEGER,
  score          INTEGER NOT NULL,
  decision       TEXT NOT NULL,       -- approve | reject | manual
  hit_rules      TEXT,                -- JSON
  snapshot       TEXT,                -- JSON 入参快照
  created_at     TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_risk_user ON risk_decisions(user_id, created_at);

-- ========== 运营后台 ==========
CREATE TABLE IF NOT EXISTS admins (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  username      TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  name          TEXT NOT NULL,
  role          TEXT NOT NULL,   -- super | approver | risk | ops
  status        TEXT NOT NULL DEFAULT 'active',
  last_login_at TEXT,
  created_at    TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS audit_logs (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  actor_type  TEXT NOT NULL,   -- user | admin | system
  actor_id    INTEGER,
  action      TEXT NOT NULL,
  target_type TEXT,
  target_id   TEXT,
  detail      TEXT,
  ip          TEXT,
  created_at  TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_logs(created_at);

CREATE TABLE IF NOT EXISTS settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  remark     TEXT,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS idempotency_keys (
  key         TEXT PRIMARY KEY,
  user_id     INTEGER,
  scope       TEXT NOT NULL,
  response    TEXT NOT NULL,
  created_at  TEXT NOT NULL
);
