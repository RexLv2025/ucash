> **【变更说明 2026-11-08】** 客户端技术栈已由 React Native + Expo 调整为 **Flutter（Android 原生）**，详见 `docs/04-flutter-adr.md`。本文档中涉及 RN 的客户端实现细节以该 ADR 为准；业务中台、数据模型、API 契约与运营后台不受影响。

# UCash 技术架构与研发方案

> 文档编号：03-tech-arch
> 适用项目：UCash —— 线上小额现金贷 App（真实业务闭环，非界面演示）
> 技术栈基线（已锁定，不得擅自替换）：
> React Native + Expo SDK 51+ / TypeScript / expo-router / react-native-web ；
> Node 22 + Express + TypeScript + better-sqlite3 + JWT + zod + node-cron ；
> Vite + React + TypeScript（Admin SPA）；npm workspaces monorepo。
> 本文所有结论可直接用于编码，含 DDL、状态机、接口契约、算法伪代码、目录文件级清单。

---

## 0. 业务假设与范围冻结（编码前必须对齐）

PRD 文档尚未落盘，为避免研发返工，本节先冻结本方案覆盖的业务范围。PRD 定稿后如有冲突，以本文接口/表结构为准做增量修订（不推翻）。

| 项 | 冻结内容 |
|---|---|
| 客群 | 22~55 周岁、有稳定收入的中国大陆自然人；仅移动端 App |
| 产品形态 | 小额现金贷，授信额度制，循环额度；单笔 500~20000 元；期限 7/14/30 天（单期）与 3/6/12 期（等额本息） |
| 计息方式 | 按日计息，日利率 3~8 bp（0.03%~0.08%/日），年化单利 10.95%~29.2%，综合年化（IRR）必须 ≤ 36% |
| 费用 | 无前置砍头息；可选「账户管理费」按笔一次性收取（整数分），计入综合年化 |
| 还款方式 | 主动还款（余额/银行卡）、到期自动代扣、提前结清、逾期罚息 |
| 获客 | 自然注册 + 邀请码裂变（邀请返现，二审后发放） |
| 后台 | 授信审批、放款审核、账单与还款管理、风控规则配置、优惠券与消息运营、审计 |
| 明确不做（当期） | 多资金方路由、ABS、征信上报、催收外呼系统、多租户 |
| 合规红线 | 不放款给在校学生；不向未成年人服务；综合年化超 36% 拒绝放款；全链路留痕可回溯 |

---

## 1. 技术选型总表

| 层 | 选型 | 版本 | 一句话理由 |
|---|---|---|---|
| 移动端 | React Native + Expo | SDK 51，RN 0.74 | 一套代码跑 iOS/Android/web，产品验证期用 `expo start --web` 即可在浏览器评审 |
| 移动端路由 | expo-router | v3 | 文件路由，页面结构即目录结构，减少样板 |
| 移动端状态 | zustand + AsyncStorage persist | 4.x | 轻量、无 Provider 嵌套，适合表单/登录态这类局部全局态 |
| 移动端 UI | 自研组件 + theme tokens | — | 现金贷视觉强定制，组件库改造成本高于自研；规避 web 兼容坑 |
| 服务端 | Node 22 + Express | 4.19 | 团队技术栈同构，生态成熟，单体足够支撑验证期 |
| 服务端语言 | TypeScript 5.5（strict） | — | 与 shared 包共享类型，接口契约编译期校验 |
| 数据库 | better-sqlite3（WAL） | 11.x | 同步 API 让事务代码线性可读，零运维；生产切 MySQL 时保留仓储层 |
| 参数校验 | zod | 3.x | Schema 即类型，请求体/环境变量/规则 DSL 三处复用 |
| 认证 | jsonwebtoken（HS256）+ bcrypt | — | Access 2h + Refresh 30d 轮换，符合基线 |
| 定时任务 | node-cron | 3.x | 逾期标记、罚息计提、额度过期、消息推送，单进程足够 |
| 后台 | Vite 5 + React 18 + TS + Ant Design 5 | — | 中后台表单/表格密集，antd 省 60% 工作量 |
| 日志 | pino + pino-pretty | — | 结构化 JSON，便于后续接 ELK |
| 测试 | vitest（算法/服务） + supertest（接口） | — | 与 Vite 同源，零额外配置 |
| 包管理 | npm workspaces | npm 10 | 单一 lockfile，shared 包软链，零额外工具 |
| 镜像 | registry.npmmirror.com | — | 国内网络稳定性 |

**为什么 SQLite 可以**：本期是单机、单进程、验证期（并发 < 100），SQLite WAL 读写并发足够；表结构与仓储层完全按 MySQL 可迁移设计（不自增依赖、不用 SQLite 独有语法糖、时间统一 TEXT），迁移成本可控。生产多实例时必须切 MySQL，见 §13。

---

## 2. 系统架构

### 2.1 架构总览

```
┌──────────────────────────┐        ┌──────────────────────────┐
│   UCash App (Expo RN)    │        │  UCash Admin (Vite React) │
│  iOS / Android / Web     │        │  Chrome / Edge            │
│  expo-router / zustand   │        │  antd / react-router      │
└────────────┬─────────────┘        └────────────┬─────────────┘
             │ HTTPS  JSON  /api/v1               │ /api/v1/admin
             │ Authorization: Bearer <JWT>        │ Authorization: Bearer <AdminJWT>
             ▼                                    ▼
┌───────────────────────────────────────────────────────────────────────┐
│                      API Gateway 层（Express 单进程）                  │
│  requestId → pino日志 → cors → helmet → body(json 1mb) → rateLimit    │
│  → auth(JWT) → adminGuard(角色) → zod校验 → 路由 → 统一错误处理        │
└───────────────────────────────────┬───────────────────────────────────┘
                                    │ 仅调用 service，不直连 db
        ┌───────────────────────────┼───────────────────────────┐
        ▼                           ▼                           ▼
┌───────────────┐         ┌───────────────────┐       ┌──────────────────┐
│  领域服务层    │         │   风控引擎         │       │  运营/配置服务     │
│ auth 认证      │◄───────►│ rule DSL 求值器    │       │ product 产品       │
│ user 用户      │         │ A卡评分卡         │       │ coupon 优惠券      │
│ kyc 实名       │         │ 多头/黑名单/设备   │       │ message 消息       │
│ credit 授信    │         │ 决策落库+快照      │       │ invite 邀请        │
│ loan 借据      │         └─────────┬─────────┘       │ settings 配置      │
│ bill 账单      │                   │                 │ audit 审计        │
│ repay 还款     │                   │                 └────────┬─────────┘
└───────┬───────┘                   │                          │
        │                           │                          │
        ▼                           ▼                          ▼
┌───────────────────────────────────────────────────────────────────────┐
│                        仓储层 Repository（唯一碰 SQL 的地方）           │
│  事务边界：db.transaction()；金额 INTEGER 分；软删除；乐观锁 version     │
└───────────────────────────────────┬───────────────────────────────────┘
                                    ▼
┌───────────────────────────────────────────────────────────────────────┐
│                    SQLite (WAL)  ucash.db + ucash.db-wal              │
│  users / profiles / kyc / credit_* / loans / schedules / repayments … │
└───────────────────────────────────────────────────────────────────────┘

        适配层（接口 + Mock 实现，env 一键切真实厂商）
┌──────────┬──────────┬──────────────┬──────────────┬──────────────┐
│ SMS 短信  │ 人脸活体  │ 征信/多头数据  │ 支付/代扣     │ 电子合同      │
│ SmsProv. │ FaceProv.│ BureauProv.  │ PaymentProv. │ ContractProv.│
└──────────┴──────────┴──────────────┴──────────────┴──────────────┘

        后台任务（node-cron，同进程，带分布式锁表防重入）
┌────────────────┬────────────────┬────────────────┬────────────────┐
│ 00:05 逾期标记   │ 00:10 罚息计提   │ 01:00 额度过期   │ 09:00 还款提醒  │
└────────────────┴────────────────┴────────────────┴────────────────┘
```

### 2.2 分层与依赖规则（禁止循环依赖）

依赖方向严格单向：`router → controller → service → repository → db`，`service` 之间禁止互相 `import`（跨域协作通过 service 暴露的只读方法 + 事件回调注册表，见 §2.4）。`shared` 包不依赖任何 runtime 包，只能被依赖。

| 层 | 允许依赖 | 禁止 |
|---|---|---|
| router | controller、middleware | 直接 import db / repository |
| controller | service、zod schema、shared 类型 | 写业务判断、直接 SQL |
| service | repository、adapters、shared、utils | import 另一个 service 的写方法、express 的 req/res |
| repository | db、shared 类型 | 业务规则判断（只做数据映射） |
| adapters | 无内部依赖 | 依赖 db |

ESLint 用 `import/no-restricted-paths` 固化以上规则，违规构建失败。

### 2.3 核心请求链路

**链路 A：借款申请（最关键路径，必须全事务）**

```
POST /api/v1/loans  Idempotency-Key: <uuid>
 1 requestId 注入 → pino 记录入参摘要
 2 authGuard 解析 JWT → req.userId
 3 zod 校验 { amountCents, termCount, productId, couponId?, bankCardId? }
 4 idempotencyGuard 查 idempotency_keys，命中直接回放 response
 5 creditService.assertAvailable(userId, amountCents)      // 额度/状态/过期
 6 kycService.assertLevel(userId, 2)                        // 实名+人脸
 7 riskService.decide({ scene:'borrow', userId, amountCents, device }) 
      └─ 命中 reject → 落 risk_decisions → 返回 50006/70002
      └─ 命中 review → 借据直接置 created 并挂人工队列（跳过 8~9 自动放款）
 8 tx.begin()
      8.1 冻结额度 credit_limits.frozen += amount（乐观锁 version）
      8.2 插入 loans(status=created) + loan_schedules(按算法生成)
      8.3 插入 risk_decisions 快照
    tx.commit()
 9 loanService.submit(loanId) → status=reviewing（自动审批则直接走 10）
10 paymentAdapter.disburse() → 成功 status=disbursing → active
      └─ 失败 status=failed，释放冻结额度，记 fail_reason
11 生成 messages（放款成功/失败），返回借据详情
```

**链路 B：还款（幂等要求最高）**

```
POST /api/v1/repayments → 创建还款单(pending)，锁定应付金额快照
POST /api/v1/repayments/:id/pay → 调支付适配层 → 拿到 gateway_trade_no
    └─ 同步回调：paymentCallback 验签 → 按 repayment_no 幂等
       → tx: repayments.status=success → 按「罚息>费用>利息>本金」顺序核销
             → loan_schedules 累加 paid_* / remain_principal，状态重算
             → 全部期次结清则 loans.status=settled，释放额度 used
       → 失败：status=failed + fail_reason，额度不变
```

**链路 C：逾期（定时任务）**

```
00:05 overdue.job   → 扫 due_date < today 且 status in (unpaid,partial) 的期次
                    → schedule.status=overdue, overdue_days 重算
                    → loans.status=overdue, overdue_days = max(期次逾期天数)
                    → 首日逾期生成 messages + 更新 user 风险标签
00:10 penalty.job   → 对 overdue 期次按日计提 penalty_accrued_cents（幂等键 day+scheduleId）
```

### 2.4 模块间协作（避免循环依赖）

跨域只读查询走 `service` 暴露的窄接口；跨域「副作用」走事件总线（进程内 `EventEmitter`，同步派发、失败不影响主事务，写入 `outbox_events` 由 job 重试）。

| 事件 | 生产者 | 消费者 |
|---|---|---|
| `loan.disbursed` | loan | message（放款通知）、risk（额度使用埋点） |
| `repayment.succeeded` | repayment | loan（结清判断）、coupon（核销）、invite（首借返现） |
| `loan.overdue` | bill/job | message、risk（风险标签）、admin 待办 |
| `kyc.passed` | kyc | user（kyc_level 升级）、credit（可发起授信） |

### 2.5 适配层契约（接口 + Mock）

所有外部能力只在 `apps/server/src/adapters/` 出现，`.env` 的 `*_PROVIDER=mock|real` 决定装配哪个实现，业务代码只依赖接口。

```ts
// adapters/types.ts
export interface SmsProvider {
  send(phone: string, scene: 'login'|'repay'|'notice', code: string): Promise<{ msgId: string }>;
}
export interface FaceProvider {
  liveness(params: { userId: number; imageBase64: string }): Promise<{ pass: boolean; score: number; providerReqId: string }>;
  compare(params: { userId: number; idPhotoUrl: string; selfieBase64: string }): Promise<{ pass: boolean; similarity: number }>;
}
export interface BureauProvider {
  queryMultiLoan(idCardHash: string, phoneHash: string): Promise<{ orgCount30d: number; queryCount90d: number; blacklist: boolean; raw: unknown }>;
}
export interface PaymentProvider {
  disburse(p: { loanNo: string; amountCents: number; bankCardToken: string }): Promise<{ ok: boolean; tradeNo?: string; code?: string; msg?: string }>;
  repay(p: { repaymentNo: string; amountCents: number; bankCardToken: string }): Promise<{ ok: boolean; tradeNo?: string; code?: string; msg?: string }>;
  verifyCallback(headers: Record<string,string>, rawBody: string): boolean;
}
export interface ContractProvider {
  generate(p: { loanNo: string; userId: number; amountCents: number; termCount: number; rateBp: number; signerName: string }): Promise<{ contractNo: string; url: string; sha256: string }>;
}
```

Mock 行为（必须可预测，便于自动化测试）：
- SMS：验证码固定 `123456`（`MOCK_SMS_FIXED=123456`），同时写 `sms_codes` 表，日志打印 `[MOCK SMS] phone=138****8888 code=123456`。
- Face：自拍照 base64 长度 > 1KB 即通过，score 固定 0.98；`MOCK_FACE_FAIL=1` 时永远失败（用于测拒绝分支）。
- Bureau：读 `MOCK_BUREAU_JSON` 或默认 `{orgCount30d:1,queryCount90d:2,blacklist:false}`；`MOCK_BUREAU_BLACKLIST=1` 触发黑名单。
- Payment：放款/还款默认 800ms 后成功；`MOCK_PAY_FAIL_RATE=0` 可配失败率；支持 `POST /api/v1/mock/pay-callback` 手动触发异步回调。
- Contract：生成 HTML 存 `storage/contracts/{loanNo}.html`，返回 `sha256`，前端 web 用 iframe，原生用 WebView 展示。

---

## 3. 仓库与目录结构（文件级）

```
UCash/
├─ package.json                       # workspaces 根，scripts 聚合
├─ package-lock.json
├─ .npmrc                             # registry=https://registry.npmmirror.com
├─ tsconfig.base.json                 # strict / paths: @ucash/shared
├─ .env.example                       # 全量环境变量样例（见 §11.2）
├─ .gitignore
├─ README.md
├─ docs/
│  ├─ 01-platform-selection.md
│  ├─ 02-product-design.md
│  ├─ 03-tech-arch.md                 # 本文
│  └─ 04-api.md                       # 由本文 §7 生成的 OpenAPI 说明
├─ scripts/
│  ├─ dev.sh                          # 一键起 server+admin+mobile(web)
│  ├─ reset-db.sh                     # 删库并重建+种子
│  ├─ seed-demo.ts                    # 造 20 个用户/借据/账单的演示数据
│  └─ gen-openapi.ts                  # 由 zod schema 生成 openapi.json
├─ storage/                           # 运行时产物（gitignore）
│  ├─ contracts/                      # Mock 合同 HTML
│  └─ uploads/                        # Mock 身份证/自拍图
├─ packages/
│  └─ shared/
│     ├─ package.json                 # name: @ucash/shared, main: src/index.ts
│     ├─ tsconfig.json
│     └─ src/
│        ├─ index.ts                  # 统一导出
│        ├─ enums.ts                  # 全部状态枚举 + 中文映射
│        ├─ error-codes.ts            # 错误码常量 + HTTP 映射
│        ├─ types/api.ts              # ApiResponse / PageResult / 分页入参
│        ├─ types/domain.ts           # User/Loan/Schedule/Repayment DTO
│        ├─ money.ts                  # 分↔元、万分比换算、roundCents
│        ├─ date.ts                   # Asia/Shanghai 日期工具、dayDiff、addDays
│        ├─ amortization.ts           # 等额本息 + 单期计息（纯函数，前后端共用）
│        ├─ irr.ts                    # IRR / XIRR 牛顿+二分
│        └─ constants.ts              # 产品默认值、限额、正则（身份证/手机号/卡号）
└─ apps/
   ├─ server/
   │  ├─ package.json                 # dev: tsx watch src/index.ts
   │  ├─ tsconfig.json
   │  ├─ vitest.config.ts
   │  └─ src/
   │     ├─ index.ts                  # 启动：迁移→种子→jobs→listen
   │     ├─ app.ts                    # express 装配（可被 supertest 复用）
   │     ├─ config/
   │     │  ├─ env.ts                 # zod 校验 process.env，缺项启动失败
   │     │  └─ constants.ts
   │     ├─ db/
   │     │  ├─ index.ts               # 连接、PRAGMA、DbAdapter 抽象
   │     │  ├─ migrate.ts             # 按文件名顺序执行 sql/
   │     │  ├─ seed.ts                # 幂等种子（settings/risk_rules/products/admin）
   │     │  └─ sql/
   │     │     ├─ 001_init.sql        # 全量 DDL（§5.3）
   │     │     ├─ 002_index.sql       # 索引（也可并入 001）
   │     │     └─ 003_seed.sql        # 基础配置
   │     ├─ middleware/
   │     │  ├─ requestId.ts           # X-Request-Id 透传/生成
   │     │  ├─ auth.ts                # JWT 验签 → req.user
   │     │  ├─ adminAuth.ts           # Admin JWT + 角色守卫
   │     │  ├─ validate.ts            # zod：body/query/params 三合一
   │     │  ├─ idempotency.ts         # Idempotency-Key 落库回放
   │     │  ├─ rateLimit.ts           # 内存令牌桶（IP/手机号/用户三维）
   │     │  ├─ audit.ts               # Admin 写操作自动落 audit_logs
   │     │  └─ error.ts               # 统一异常 → {code,message,data}
   │     ├─ modules/
   │     │  ├─ auth/       router.ts controller.ts service.ts repo.ts schema.ts
   │     │  ├─ user/       router.ts controller.ts service.ts repo.ts schema.ts
   │     │  ├─ kyc/        router.ts controller.ts service.ts repo.ts schema.ts
   │     │  ├─ credit/     router.ts controller.ts service.ts repo.ts schema.ts
   │     │  ├─ loan/       router.ts controller.ts service.ts repo.ts schema.ts
   │     │  ├─ bill/       router.ts controller.ts service.ts repo.ts schema.ts
   │     │  ├─ repayment/  router.ts controller.ts service.ts repo.ts schema.ts
   │     │  ├─ bankcard/   router.ts controller.ts service.ts repo.ts schema.ts
   │     │  ├─ coupon/     router.ts controller.ts service.ts repo.ts schema.ts
   │     │  ├─ invite/     router.ts controller.ts service.ts repo.ts schema.ts
   │     │  ├─ message/    router.ts controller.ts service.ts repo.ts schema.ts
   │     │  ├─ product/    router.ts controller.ts service.ts repo.ts schema.ts
   │     │  ├─ settings/   router.ts controller.ts service.ts repo.ts schema.ts
   │     │  └─ admin/      router.ts（聚合 admin 子路由）controller.ts service.ts
   │     ├─ risk/
   │     │  ├─ engine.ts              # 规则求值主流程
   │     │  ├─ operators.ts           # 算子注册表
   │     │  ├─ fields.ts              # 字段白名单 + 取值器
   │     │  ├─ scorecard.ts           # A 卡评分
   │     │  ├─ features.ts            # 特征装配（含缓存）
   │     │  └─ presets.ts             # 默认规则集
   │     ├─ services/
   │     │  ├─ amortization.service.ts# 包装 shared 纯函数 + 落库结构
   │     │  ├─ settle.service.ts      # 提前结清试算/执行
   │     │  ├─ allocation.service.ts  # 还款核销顺序
   │     │  └─ event-bus.ts
   │     ├─ adapters/
   │     │  ├─ index.ts               # 工厂装配
   │     │  ├─ sms/{types.ts,mock.ts,real.ts}
   │     │  ├─ face/{types.ts,mock.ts}
   │     │  ├─ bureau/{types.ts,mock.ts}
   │     │  ├─ payment/{types.ts,mock.ts}
   │     │  └─ contract/{types.ts,mock.ts}
   │     ├─ jobs/
   │     │  ├─ scheduler.ts           # 注册全部 cron + job_locks 防重入
   │     │  ├─ overdue.job.ts
   │     │  ├─ penalty.job.ts
   │     │  ├─ limit-expire.job.ts
   │     │  ├─ remind.job.ts
   │     │  └─ outbox.job.ts
   │     ├─ utils/
   │     │  ├─ crypto.ts              # AES-256-GCM / HMAC 盲索引 / mask
   │     │  ├─ password.ts            # bcrypt hash/compare
   │     │  ├─ jwt.ts                 # sign/verify access+refresh
   │     │  ├─ ids.ts                 # userNo/loanNo/repaymentNo 生成
   │     │  ├─ logger.ts              # pino + 脱敏 serializer
   │     │  └─ assert.ts              # BizError 抛出
   │     └─ __tests__/
   │        ├─ amortization.spec.ts
   │        ├─ irr.spec.ts
   │        ├─ settle.spec.ts
   │        ├─ risk-engine.spec.ts
   │        └─ api.e2e.spec.ts
   ├─ admin/
   │  ├─ package.json                 # vite dev --port 5173
   │  ├─ vite.config.ts               # proxy /api → localhost:4000
   │  ├─ index.html
   │  └─ src/
   │     ├─ main.tsx  App.tsx  router.tsx
   │     ├─ api/client.ts             # fetch 封装：token 注入/401 跳登录/统一错误
   │     ├─ api/{auth,users,kyc,credit,loans,repayments,risk,products,coupons,settings,audit}.ts
   │     ├─ layouts/AdminLayout.tsx   # 侧边栏 + 面包屑 + 角色菜单过滤
   │     ├─ components/{StatCard,StatusTag,MoneyText,DataTable,RuleEditor,JsonViewer}.tsx
   │     ├─ hooks/{useAuth,useTable,usePolling}.ts
   │     └─ pages/
   │        ├─ login/index.tsx
   │        ├─ dashboard/index.tsx
   │        ├─ users/{list.tsx,detail.tsx}
   │        ├─ kyc/list.tsx
   │        ├─ credit/{applications.tsx,detail.tsx,limits.tsx}
   │        ├─ loans/{list.tsx,detail.tsx,review.tsx}
   │        ├─ bills/{list.tsx,overdue.tsx,detail.tsx}
   │        ├─ repayments/{list.tsx,detail.tsx}
   │        ├─ risk/{rules.tsx,decisions.tsx,sandbox.tsx}
   │        ├─ products/list.tsx
   │        ├─ coupons/{list.tsx,issue.tsx}
   │        ├─ settings/index.tsx
   │        ├─ admins/list.tsx
   │        └─ audit/list.tsx
   └─ mobile/
      ├─ package.json                 # expo start --web --port 8081
      ├─ app.json                     # scheme: ucash, 权限文案
      ├─ metro.config.js              # watchFolders: ../../packages, ../../node_modules
      ├─ babel.config.js
      └─ src/
         ├─ app/
         │  ├─ _layout.tsx            # 根 Stack + AuthProvider + Toast 容器
         │  ├─ index.tsx              # 启动分流：未登录→/login，未实名→/kyc，未授信→/activate
         │  ├─ (auth)/login.tsx
         │  ├─ (tabs)/_layout.tsx     # 底部 4 tab
         │  ├─ (tabs)/index.tsx       # 首页：额度卡片 + 立即借款 + 待还提醒
         │  ├─ (tabs)/borrow.tsx      # 借款：金额滑块/期限选择/费用明细/协议
         │  ├─ (tabs)/bills.tsx       # 账单：待还/已还/逾期 分组
         │  ├─ (tabs)/profile.tsx     # 我的：额度/卡/优惠券/邀请/消息/设置
         │  ├─ kyc/index.tsx          # 实名引导
         │  ├─ kyc/idcard.tsx         # 身份证正反面上传 + OCR 回填
         │  ├─ kyc/face.tsx           # 活体检测（web 降级为上传自拍）
         │  ├─ kyc/bankcard.tsx       # 绑卡四要素
         │  ├─ activate/index.tsx     # 额度激活：授权协议 + 提交授信
         │  ├─ activate/result.tsx    # 审批中/通过/拒绝/转人工
         │  ├─ loan/confirm.tsx       # 借款确认：合同 + 费用 + 验证码
         │  ├─ loan/result.tsx        # 放款成功/失败/审核中
         │  ├─ loan/[id].tsx          # 借据详情 + 还款计划表
         │  ├─ bill/[id].tsx          # 账单详情 + 去还款
         │  ├─ repay/index.tsx        # 还款收银台（选卡/选券/支付）
         │  ├─ repay/result.tsx
         │  ├─ prepay/index.tsx       # 提前结清试算
         │  ├─ coupon/index.tsx
         │  ├─ invite/index.tsx
         │  ├─ message/index.tsx
         │  └─ settings/{index.tsx,about.tsx,agreements.tsx}
         ├─ api/{client.ts,auth.ts,user.ts,kyc.ts,credit.ts,loan.ts,bill.ts,repay.ts,misc.ts}
         ├─ store/{auth.ts,app.ts}
         ├─ components/
         │  ├─ AmountCard.tsx  AmountInput.tsx  TermPicker.tsx
         │  ├─ PrimaryButton.tsx  EmptyState.tsx  LoadingMask.tsx
         │  ├─ StatusBadge.tsx  StepBar.tsx  CountdownText.tsx
         │  ├─ ScheduleTable.tsx  FeeBreakdown.tsx  AgreementCheckbox.tsx
         │  └─ SafeArea.tsx（web 兼容）
         ├─ theme/{tokens.ts,typography.ts}
         ├─ hooks/{useCountdown.ts,useRequest.ts,useAppState.ts}
         └─ utils/{format.ts,storage.ts,platform.ts}
```

**Metro + workspaces 关键配置**（否则 `@ucash/shared` 在 web 端解析失败）：

```js
// apps/mobile/metro.config.js
const { getDefaultConfig } = require('expo/metro-config');
const path = require('path');
const root = path.resolve(__dirname, '../..');
const config = getDefaultConfig(__dirname);
config.watchFolders = [path.resolve(root, 'packages'), path.resolve(root, 'node_modules')];
config.resolver.nodeModulesPaths = [
  path.resolve(__dirname, 'node_modules'),
  path.resolve(root, 'node_modules'),
];
config.resolver.disableHierarchicalLookup = true;
module.exports = config;
```

---

## 4. 数据模型

### 4.1 全局约定

| 约定 | 规则 |
|---|---|
| 主键 | `INTEGER PRIMARY KEY AUTOINCREMENT`（SQLite 行id 别名）；业务编号另设 `*_no` 唯一键 |
| 金额 | 一律 `INTEGER` 分（cent）。**禁止 REAL 存钱**。字段名后缀 `_cents` |
| 利率 | 一律 `INTEGER` 万分比/基点（bp）。`day_rate_bp=5` 表示 0.05%/日。字段名后缀 `_bp` |
| 时间 | `TEXT` UTC ISO-8601（`2026-11-08T13:00:00.000Z`），应用层 `new Date().toISOString()` 写入 |
| 业务日期 | `TEXT` `YYYY-MM-DD`（Asia/Shanghai），如 `due_date` |
| 布尔 | `INTEGER` 0/1，字段名 `is_*` |
| 删除 | 仅 `users`/`bank_cards` 用 `deleted_at` 软删除；业务单据禁止删除 |
| 外键 | 全部声明 `REFERENCES`，启动 `PRAGMA foreign_keys = ON` |
| 并发 | 额度/借据/期次带 `version INTEGER`，更新语句 `WHERE id=? AND version=?`，影响行数 0 抛 `CONFLICT` |
| 命名 | 表名复数 snake_case；索引 `idx_{表}_{列}`；唯一索引 `uk_{表}_{列}` |

### 4.2 ER 关系

```
users 1─1 user_profiles
users 1─N kyc_records
users 1─N credit_applications ─N─1 loan_products
users 1─1 credit_limits（一个用户同时仅一条 active）
users 1─N loans ─N─1 credit_limits
loans 1─N loan_schedules
loans 1─N repayments
loan_schedules 1─N repayments（部分还款时关联当期；提前结清 schedule_id 为 NULL）
users 1─N bank_cards
users 1─N user_coupons ─N─1 coupons
users 1─N invitations（inviter/invitee 双向）
users 1─N messages
users 1─N risk_decisions
risk_rules 1─N risk_decisions（通过 rule_version 弱关联，保留历史版本）
admins 1─N audit_logs（actor）
```

### 4.3 DDL（`apps/server/src/db/sql/001_init.sql`）

> 建表顺序：`users → user_profiles → kyc_records → loan_products → credit_applications → credit_limits → loans → loan_schedules → repayments → bank_cards → coupons → user_coupons → invitations → messages → risk_rules → risk_decisions → admins → audit_logs → settings`。
> 说明：SQLite 允许建表时引用「尚未创建」的表（如 `credit_applications.risk_decision_id → risk_decisions`、`*.reviewer_id → admins`），错误只在 DML 时暴露；迁移脚本按 001→002→003 顺序执行即可全部就绪。若切 MySQL，必须先调整建表顺序或延后添加外键。

```sql
-- ============ 连接期设置（在 db/index.ts 执行，此处注释说明） ============
-- PRAGMA journal_mode = WAL;
-- PRAGMA foreign_keys = ON;
-- PRAGMA busy_timeout = 5000;
-- PRAGMA synchronous = NORMAL;

-- ---------------------------------------------------------------- 用户
CREATE TABLE users (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  user_no           TEXT    NOT NULL UNIQUE,                 -- U + yyMMdd + 8位随机
  phone_enc         TEXT    NOT NULL,                        -- AES-256-GCM(手机号)
  phone_hash        TEXT    NOT NULL UNIQUE,                 -- HMAC-SHA256 盲索引（登录查询用）
  phone_tail        TEXT    NOT NULL,                        -- 后4位，展示用
  password_hash     TEXT,                                    -- bcrypt(cost=12)，短信登录可为 NULL
  nickname          TEXT,
  avatar_url        TEXT,
  status            TEXT    NOT NULL DEFAULT 'active'
                            CHECK (status IN ('active','frozen','closed')),
  kyc_level         INTEGER NOT NULL DEFAULT 0 CHECK (kyc_level BETWEEN 0 AND 3),
                     -- 0未实名 1身份证 2身份证+人脸 3+银行卡四要素
  credit_status     TEXT    NOT NULL DEFAULT 'none'
                            CHECK (credit_status IN ('none','applying','approved','rejected','frozen')),
  invite_code       TEXT    UNIQUE,
  invited_by        INTEGER REFERENCES users(id),
  register_channel  TEXT    NOT NULL DEFAULT 'app',
  register_ip       TEXT,
  last_login_at     TEXT,
  last_login_ip     TEXT,
  created_at        TEXT    NOT NULL,
  updated_at        TEXT    NOT NULL,
  deleted_at        TEXT
);
CREATE INDEX idx_users_created_at ON users(created_at);
CREATE INDEX idx_users_invited_by ON users(invited_by);
CREATE INDEX idx_users_credit_status ON users(credit_status);

CREATE TABLE user_profiles (
  user_id            INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  real_name_enc      TEXT,                                   -- AES-GCM
  real_name_mask     TEXT,                                   -- 张*
  id_card_enc        TEXT,
  id_card_hash       TEXT UNIQUE,                            -- HMAC 盲索引（唯一性/反查）
  id_card_tail       TEXT,                                   -- 后4位
  birth_date         TEXT,                                   -- YYYY-MM-DD
  gender             TEXT CHECK (gender IN ('M','F','U')),
  education          TEXT,                                   -- primary/high/college/bachelor/master+
  marital_status     TEXT CHECK (marital_status IN ('single','married','divorced','widowed','U')),
  province           TEXT,
  city               TEXT,
  district           TEXT,
  address_enc        TEXT,
  company_name       TEXT,
  industry           TEXT,
  occupation         TEXT,
  monthly_income_cents INTEGER CHECK (monthly_income_cents >= 0),
  work_years         INTEGER CHECK (work_years >= 0),
  emergency_name_enc TEXT,
  emergency_phone_enc TEXT,
  emergency_relation TEXT,
  completeness       INTEGER NOT NULL DEFAULT 0,             -- 0~100
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL
);
CREATE INDEX idx_profiles_income ON user_profiles(monthly_income_cents);

-- ---------------------------------------------------------------- 实名/KYC
CREATE TABLE kyc_records (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id        INTEGER NOT NULL REFERENCES users(id),
  kyc_type       TEXT    NOT NULL CHECK (kyc_type IN
                   ('idcard_ocr','liveness','face_compare','bankcard_verify','operator','bureau')),
  provider       TEXT    NOT NULL DEFAULT 'mock',
  provider_req_id TEXT,
  status         TEXT    NOT NULL CHECK (status IN ('pending','success','failed')),
  score          REAL,                                        -- 人脸相似度等 0~1
  result_json    TEXT,                                        -- 原始返回（脱敏后）
  fail_code      TEXT,
  fail_reason    TEXT,
  image_urls     TEXT,                                        -- JSON 数组
  created_at     TEXT    NOT NULL
);
CREATE INDEX idx_kyc_user_type ON kyc_records(user_id, kyc_type, created_at DESC);
CREATE INDEX idx_kyc_status ON kyc_records(status, created_at);

-- ---------------------------------------------------------------- 产品
CREATE TABLE loan_products (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  code               TEXT    NOT NULL UNIQUE,                 -- e.g. CASH_30D
  name               TEXT    NOT NULL,
  min_amount_cents   INTEGER NOT NULL,
  max_amount_cents   INTEGER NOT NULL,
  min_term           INTEGER NOT NULL,                        -- 期数
  max_term           INTEGER NOT NULL,
  period_days        INTEGER NOT NULL,                        -- 每期天数（30 天/期）
  repay_method       TEXT    NOT NULL DEFAULT 'equal_installment'
                     CHECK (repay_method IN ('equal_installment','single_installment','interest_first')),
  default_day_rate_bp INTEGER NOT NULL,
  penalty_day_rate_bp INTEGER NOT NULL DEFAULT 10,            -- 逾期日罚息 0.1%/日
  max_penalty_bp      INTEGER NOT NULL DEFAULT 2000,          -- 罚息上限（相对本金 20%）
  prepay_fee_bp       INTEGER NOT NULL DEFAULT 0,             -- 提前结清违约金
  prepay_waive_ratio  INTEGER NOT NULL DEFAULT 100,           -- 未到期利息减免比例 %
  fee_cents           INTEGER NOT NULL DEFAULT 0,             -- 一次性管理费（可选）
  need_manual_review  INTEGER NOT NULL DEFAULT 0,             -- 1=全部转人工
  status             TEXT    NOT NULL DEFAULT 'active' CHECK (status IN ('active','offline')),
  sort_order         INTEGER NOT NULL DEFAULT 0,
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL
);

-- ---------------------------------------------------------------- 授信
CREATE TABLE credit_applications (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  app_no                TEXT    NOT NULL UNIQUE,              -- CA + yyMMdd + 10位
  user_id               INTEGER NOT NULL REFERENCES users(id),
  product_id            INTEGER NOT NULL REFERENCES loan_products(id),
  apply_amount_cents    INTEGER NOT NULL,
  apply_term            INTEGER NOT NULL,
  status                TEXT    NOT NULL DEFAULT 'draft'
                        CHECK (status IN ('draft','submitted','reviewing','approved','rejected','manual')),
  score                 INTEGER,                              -- 300~850
  score_detail_json     TEXT,                                 -- 各特征得分快照
  risk_decision_id      INTEGER REFERENCES risk_decisions(id),
  approved_amount_cents INTEGER,
  approved_rate_bp      INTEGER,
  approved_max_term     INTEGER,
  reject_code           TEXT,
  reject_reason         TEXT,
  reviewer_id           INTEGER REFERENCES admins(id),
  reviewed_at           TEXT,
  submitted_at          TEXT,
  created_at            TEXT NOT NULL,
  updated_at            TEXT NOT NULL
);
CREATE INDEX idx_credit_app_user ON credit_applications(user_id, created_at DESC);
CREATE INDEX idx_credit_app_status ON credit_applications(status, submitted_at);

CREATE TABLE credit_limits (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id            INTEGER NOT NULL REFERENCES users(id),
  application_id     INTEGER REFERENCES credit_applications(id),
  total_amount_cents INTEGER NOT NULL CHECK (total_amount_cents >= 0),
  used_amount_cents  INTEGER NOT NULL DEFAULT 0 CHECK (used_amount_cents >= 0),
  frozen_amount_cents INTEGER NOT NULL DEFAULT 0 CHECK (frozen_amount_cents >= 0),
  day_rate_bp        INTEGER NOT NULL,
  max_term           INTEGER NOT NULL,
  status             TEXT    NOT NULL DEFAULT 'active'
                     CHECK (status IN ('active','frozen','closed')),
  expire_at          TEXT,                                    -- 额度有效期
  version            INTEGER NOT NULL DEFAULT 1,
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL,
  CHECK (used_amount_cents + frozen_amount_cents <= total_amount_cents)
);
-- 一个用户仅一条 active 额度
CREATE UNIQUE INDEX uk_credit_limits_user_active
  ON credit_limits(user_id) WHERE status = 'active';

-- ---------------------------------------------------------------- 借据
CREATE TABLE loans (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  loan_no             TEXT    NOT NULL UNIQUE,                 -- L + yyMMdd + 12位
  user_id             INTEGER NOT NULL REFERENCES users(id),
  credit_limit_id     INTEGER NOT NULL REFERENCES credit_limits(id),
  application_id      INTEGER REFERENCES credit_applications(id),
  product_id          INTEGER NOT NULL REFERENCES loan_products(id),
  principal_cents     INTEGER NOT NULL CHECK (principal_cents > 0),
  term_count          INTEGER NOT NULL CHECK (term_count >= 1),
  period_days         INTEGER NOT NULL,
  day_rate_bp         INTEGER NOT NULL,
  repay_method        TEXT    NOT NULL,
  rate_snapshot_json  TEXT    NOT NULL,                        -- 利率/费率快照，防产品改价影响存量
  total_interest_cents INTEGER NOT NULL DEFAULT 0,
  total_fee_cents     INTEGER NOT NULL DEFAULT 0,
  coupon_discount_cents INTEGER NOT NULL DEFAULT 0,
  total_repay_cents   INTEGER NOT NULL,
  status              TEXT    NOT NULL DEFAULT 'created'
                      CHECK (status IN ('created','reviewing','disbursing','active','settled','overdue','rejected','failed')),
  purpose             TEXT,                                    -- 借款用途
  apply_at            TEXT,
  review_at           TEXT,
  review_by           INTEGER REFERENCES admins(id),
  disburse_at         TEXT,
  disburse_trade_no   TEXT,
  first_due_date      TEXT,                                    -- YYYY-MM-DD
  final_due_date      TEXT,
  last_settle_at      TEXT,                                    -- 最近一次成功核销时间（提前结清应计利息起算点）
  settled_at          TEXT,
  overdue_days        INTEGER NOT NULL DEFAULT 0,
  overdue_amount_cents INTEGER NOT NULL DEFAULT 0,
  reject_code         TEXT,
  fail_reason         TEXT,
  idempotency_key     TEXT UNIQUE,
  created_at          TEXT NOT NULL,
  updated_at          TEXT NOT NULL
);
CREATE INDEX idx_loans_user_status ON loans(user_id, status, created_at DESC);
CREATE INDEX idx_loans_status_due ON loans(status, final_due_date);
CREATE INDEX idx_loans_created ON loans(created_at);

CREATE TABLE loan_schedules (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  loan_id               INTEGER NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
  period_no             INTEGER NOT NULL,
  due_date              TEXT    NOT NULL,                      -- YYYY-MM-DD
  principal_cents       INTEGER NOT NULL,
  interest_cents        INTEGER NOT NULL,
  fee_cents             INTEGER NOT NULL DEFAULT 0,
  total_cents           INTEGER NOT NULL,
  paid_principal_cents  INTEGER NOT NULL DEFAULT 0,
  paid_interest_cents   INTEGER NOT NULL DEFAULT 0,
  paid_fee_cents        INTEGER NOT NULL DEFAULT 0,
  paid_penalty_cents    INTEGER NOT NULL DEFAULT 0,
  remain_principal_cents INTEGER NOT NULL,
  penalty_accrued_cents INTEGER NOT NULL DEFAULT 0,
  penalty_waived_cents  INTEGER NOT NULL DEFAULT 0,
  status                TEXT    NOT NULL DEFAULT 'unpaid'
                        CHECK (status IN ('unpaid','partial','paid','overdue')),
  overdue_days          INTEGER NOT NULL DEFAULT 0,
  paid_at               TEXT,
  version               INTEGER NOT NULL DEFAULT 1,
  created_at            TEXT NOT NULL,
  updated_at            TEXT NOT NULL,
  UNIQUE (loan_id, period_no)
);
CREATE INDEX idx_sched_due ON loan_schedules(status, due_date);
CREATE INDEX idx_sched_loan ON loan_schedules(loan_id, period_no);

-- ---------------------------------------------------------------- 还款
CREATE TABLE repayments (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  repayment_no        TEXT    NOT NULL UNIQUE,                 -- R + yyMMdd + 12位
  user_id             INTEGER NOT NULL REFERENCES users(id),
  loan_id             INTEGER NOT NULL REFERENCES loans(id),
  schedule_id         INTEGER REFERENCES loan_schedules(id),   -- 提前结清为 NULL
  type                TEXT    NOT NULL CHECK (type IN ('normal','prepay','penalty_only')),
  amount_cents        INTEGER NOT NULL CHECK (amount_cents > 0),   -- 用户应付总额
  principal_cents     INTEGER NOT NULL DEFAULT 0,
  interest_cents      INTEGER NOT NULL DEFAULT 0,
  fee_cents           INTEGER NOT NULL DEFAULT 0,
  penalty_cents       INTEGER NOT NULL DEFAULT 0,
  coupon_discount_cents INTEGER NOT NULL DEFAULT 0,
  channel             TEXT    NOT NULL DEFAULT 'bankcard'
                      CHECK (channel IN ('bankcard','balance','manual')),
  bank_card_id        INTEGER REFERENCES bank_cards(id),
  status              TEXT    NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending','success','failed','refunded')),
  gateway_trade_no    TEXT,
  fail_reason         TEXT,
  idempotency_key     TEXT UNIQUE,
  operator_id         INTEGER REFERENCES admins(id),           -- 后台代还/退款操作人
  remark              TEXT,
  paid_at             TEXT,
  created_at          TEXT NOT NULL,
  updated_at          TEXT NOT NULL
);
CREATE INDEX idx_repay_user ON repayments(user_id, created_at DESC);
CREATE INDEX idx_repay_loan ON repayments(loan_id, status);
CREATE INDEX idx_repay_status ON repayments(status, created_at);

CREATE TABLE bank_cards (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id        INTEGER NOT NULL REFERENCES users(id),
  bank_name      TEXT    NOT NULL,
  bank_code      TEXT,
  card_no_enc    TEXT    NOT NULL,
  card_no_hash   TEXT    NOT NULL,
  card_no_tail   TEXT    NOT NULL,
  holder_name_enc TEXT   NOT NULL,
  phone_enc      TEXT,
  card_type      TEXT    NOT NULL DEFAULT 'debit' CHECK (card_type IN ('debit','credit')),
  is_default     INTEGER NOT NULL DEFAULT 0,
  status         TEXT    NOT NULL DEFAULT 'verified'
                 CHECK (status IN ('pending','verified','unbound')),
  created_at     TEXT NOT NULL,
  updated_at     TEXT NOT NULL,
  deleted_at     TEXT
);
CREATE UNIQUE INDEX uk_bankcard_user_card ON bank_cards(user_id, card_no_hash) WHERE deleted_at IS NULL;
CREATE INDEX idx_bankcard_user ON bank_cards(user_id, status);

-- ---------------------------------------------------------------- 优惠券
CREATE TABLE coupons (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  code               TEXT    NOT NULL UNIQUE,
  name               TEXT    NOT NULL,
  type               TEXT    NOT NULL CHECK (type IN ('discount_amount','discount_rate','interest_free')),
  value              INTEGER NOT NULL,                         -- discount_amount: 分；discount_rate: 折后利率bp；interest_free: 0
  min_amount_cents   INTEGER NOT NULL DEFAULT 0,               -- 起用门槛
  max_discount_cents INTEGER NOT NULL DEFAULT 0,               -- 封顶（0=不限）
  scope              TEXT    NOT NULL DEFAULT 'all'
                     CHECK (scope IN ('all','product','term')),
  scope_value        TEXT,                                     -- JSON，如 {"productIds":[1]}
  total_qty          INTEGER NOT NULL DEFAULT -1,              -- -1 不限
  issued_qty         INTEGER NOT NULL DEFAULT 0,
  used_qty           INTEGER NOT NULL DEFAULT 0,
  valid_from         TEXT NOT NULL,
  valid_to           TEXT NOT NULL,
  status             TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','offline')),
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL
);

CREATE TABLE user_coupons (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     INTEGER NOT NULL REFERENCES users(id),
  coupon_id   INTEGER NOT NULL REFERENCES coupons(id),
  serial_no   TEXT    NOT NULL UNIQUE,
  status      TEXT    NOT NULL DEFAULT 'unused' CHECK (status IN ('unused','used','expired')),
  source      TEXT    NOT NULL DEFAULT 'manual',               -- register/invite/activity/manual
  loan_id     INTEGER REFERENCES loans(id),
  used_at     TEXT,
  expire_at   TEXT    NOT NULL,
  created_at  TEXT    NOT NULL
);
CREATE INDEX idx_ucoupon_user ON user_coupons(user_id, status, expire_at);

-- ---------------------------------------------------------------- 邀请
CREATE TABLE invitations (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  inviter_id    INTEGER NOT NULL REFERENCES users(id),
  invitee_id    INTEGER NOT NULL REFERENCES users(id),
  invite_code   TEXT    NOT NULL,
  status        TEXT    NOT NULL DEFAULT 'registered'
                CHECK (status IN ('registered','activated','rewarded','invalid')),
  reward_cents  INTEGER NOT NULL DEFAULT 0,
  rewarded_at   TEXT,
  created_at    TEXT NOT NULL,
  UNIQUE (invitee_id)
);
CREATE INDEX idx_invite_inviter ON invitations(inviter_id, status);

-- ---------------------------------------------------------------- 消息
CREATE TABLE messages (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id    INTEGER NOT NULL REFERENCES users(id),
  type       TEXT    NOT NULL CHECK (type IN ('system','bill','repay','credit','marketing')),
  title      TEXT    NOT NULL,
  content    TEXT    NOT NULL,
  biz_type   TEXT,
  biz_id     INTEGER,
  is_read    INTEGER NOT NULL DEFAULT 0,
  read_at    TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_msg_user ON messages(user_id, is_read, created_at DESC);

-- ---------------------------------------------------------------- 风控
CREATE TABLE risk_rules (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  code          TEXT    NOT NULL,
  name          TEXT    NOT NULL,
  scene         TEXT    NOT NULL CHECK (scene IN ('register','apply','borrow','repay','withdraw')),
  priority      INTEGER NOT NULL DEFAULT 100,
  condition_json TEXT   NOT NULL,                              -- DSL（§8.2）
  action_json   TEXT    NOT NULL,                              -- {"type":"reject","reason":"BLACKLIST"}
  weight        INTEGER NOT NULL DEFAULT 0,
  version       INTEGER NOT NULL DEFAULT 1,
  status        TEXT    NOT NULL DEFAULT 'enabled' CHECK (status IN ('enabled','disabled')),
  description   TEXT,
  created_by    INTEGER REFERENCES admins(id),
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL,
  UNIQUE (code, version)
);
CREATE INDEX idx_risk_rules_scene ON risk_rules(scene, status, priority);

CREATE TABLE risk_decisions (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  decision_no     TEXT    NOT NULL UNIQUE,
  user_id         INTEGER NOT NULL REFERENCES users(id),
  scene           TEXT    NOT NULL,
  biz_type        TEXT,                                        -- credit_application / loan / repayment
  biz_id          INTEGER,
  rule_version    TEXT    NOT NULL,                            -- "max:17" 规则集版本快照
  features_json   TEXT    NOT NULL,                            -- 入模特征全量快照
  score           INTEGER,
  pd              REAL,
  level           TEXT,                                        -- A/B/C/D
  decision        TEXT    NOT NULL CHECK (decision IN ('approve','reject','review')),
  hit_rules_json  TEXT,                                        -- [{code,action,weight}]
  device_id       TEXT,
  ip              TEXT,
  latency_ms      INTEGER,
  created_at      TEXT NOT NULL
);
CREATE INDEX idx_decision_user ON risk_decisions(user_id, scene, created_at DESC);
CREATE INDEX idx_decision_biz ON risk_decisions(biz_type, biz_id);

-- ---------------------------------------------------------------- 系统
CREATE TABLE admins (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  username        TEXT    NOT NULL UNIQUE,
  password_hash   TEXT    NOT NULL,
  real_name       TEXT    NOT NULL,
  role            TEXT    NOT NULL CHECK (role IN ('super','admin','auditor','finance','cs')),
                  -- super 全权 / admin 运营 / auditor 审批 / finance 财务 / cs 客服只读
  phone_enc       TEXT,
  status          TEXT    NOT NULL DEFAULT 'active' CHECK (status IN ('active','disabled')),
  failed_attempts INTEGER NOT NULL DEFAULT 0,
  locked_until    TEXT,
  last_login_at   TEXT,
  last_login_ip   TEXT,
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL
);

CREATE TABLE audit_logs (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  actor_type  TEXT NOT NULL CHECK (actor_type IN ('admin','user','system')),
  actor_id    INTEGER,
  actor_name  TEXT,
  action      TEXT NOT NULL,                                   -- loan.review / credit.adjust …
  target_type TEXT,
  target_id   INTEGER,
  before_json TEXT,
  after_json  TEXT,
  ip          TEXT,
  ua          TEXT,
  request_id  TEXT,
  created_at  TEXT NOT NULL
);
CREATE INDEX idx_audit_created ON audit_logs(created_at DESC);
CREATE INDEX idx_audit_actor ON audit_logs(actor_type, actor_id, created_at DESC);
CREATE INDEX idx_audit_target ON audit_logs(target_type, target_id);

CREATE TABLE settings (
  key         TEXT PRIMARY KEY,
  value       TEXT NOT NULL,                                   -- JSON 或纯文本
  value_type  TEXT NOT NULL DEFAULT 'string' CHECK (value_type IN ('string','int','bool','json')),
  group_name  TEXT NOT NULL DEFAULT 'general',
  description TEXT,
  is_public   INTEGER NOT NULL DEFAULT 0,                      -- 1=C 端可读（app-config）
  updated_by  INTEGER REFERENCES admins(id),
  updated_at  TEXT NOT NULL
);
```

### 4.4 辅助表（DDL 追加，用于闭环必需能力）

```sql
-- 短信验证码（登录/还款验证），发送即落库，验证后置 consumed
CREATE TABLE sms_codes (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  phone_hash TEXT NOT NULL,
  scene      TEXT NOT NULL,
  code_hash  TEXT NOT NULL,                                    -- HMAC(code)
  expires_at TEXT NOT NULL,
  consumed_at TEXT,
  attempts   INTEGER NOT NULL DEFAULT 0,
  ip         TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_sms_phone ON sms_codes(phone_hash, scene, created_at DESC);

-- Refresh Token 轮换（存哈希，登出/重放检测）
CREATE TABLE refresh_tokens (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_type   TEXT NOT NULL CHECK (user_type IN ('user','admin')),
  subject_id  INTEGER NOT NULL,
  token_hash  TEXT NOT NULL UNIQUE,
  parent_hash TEXT,
  expires_at  TEXT NOT NULL,
  revoked_at  TEXT,
  ua          TEXT,
  ip          TEXT,
  created_at  TEXT NOT NULL
);
CREATE INDEX idx_rt_subject ON refresh_tokens(user_type, subject_id, revoked_at);

-- 幂等键（统一拦截 POST）
CREATE TABLE idempotency_keys (
  key           TEXT PRIMARY KEY,
  scope         TEXT NOT NULL,                                 -- "POST /api/v1/loans"
  subject_id    INTEGER,
  request_hash  TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'processing'
                CHECK (status IN ('processing','done','failed')),
  response_json TEXT,
  http_status   INTEGER,
  created_at    TEXT NOT NULL,
  expire_at     TEXT NOT NULL
);
CREATE INDEX idx_idem_expire ON idempotency_keys(expire_at);

-- 事件外箱（跨模块副作用最终一致）
CREATE TABLE outbox_events (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  event_type   TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  status       TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','done','failed')),
  retry_count  INTEGER NOT NULL DEFAULT 0,
  next_retry_at TEXT,
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL
);
CREATE INDEX idx_outbox_pending ON outbox_events(status, next_retry_at);

-- 定时任务锁（单进程也要防重入/多实例防并发）
CREATE TABLE job_locks (
  job_name    TEXT PRIMARY KEY,
  locked_until TEXT NOT NULL,
  holder      TEXT NOT NULL,
  updated_at  TEXT NOT NULL
);

-- 罚息计提流水（保证按日计提幂等：unique(schedule_id, accrue_date)）
CREATE TABLE penalty_accruals (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  schedule_id INTEGER NOT NULL REFERENCES loan_schedules(id),
  loan_id     INTEGER NOT NULL,
  accrue_date TEXT NOT NULL,                                   -- YYYY-MM-DD
  base_cents  INTEGER NOT NULL,
  rate_bp     INTEGER NOT NULL,
  amount_cents INTEGER NOT NULL,
  created_at  TEXT NOT NULL,
  UNIQUE (schedule_id, accrue_date)
);

-- 资金流水（对账用，可延后至 D12）
CREATE TABLE account_transactions (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  txn_no       TEXT NOT NULL UNIQUE,
  user_id      INTEGER REFERENCES users(id),
  biz_type     TEXT NOT NULL,                                  -- disburse / repay / refund / coupon
  biz_id       INTEGER,
  direction    TEXT NOT NULL CHECK (direction IN ('in','out')),
  amount_cents INTEGER NOT NULL,
  balance_after_cents INTEGER,
  remark       TEXT,
  created_at   TEXT NOT NULL
);
```

### 4.5 索引设计说明（为什么这些索引）

| 索引 | 支撑场景 |
|---|---|
| `uk_users_phone_hash` | 短信登录按手机号查用户（唯一） |
| `uk_profiles_id_card_hash` | 身份证唯一性校验 + 反查重复注册 |
| `idx_loans_user_status` | C 端「我的借据」列表按状态过滤 + 时间倒序 |
| `idx_loans_status_due` | 逾期 job 扫「active/overdue 且 final_due_date < today」 |
| `idx_sched_due` | 每日逾期扫描 + 账单日历 |
| `idx_repay_status` | 支付回调对账、后台待处理队列 |
| `uk_credit_limits_user_active`（部分索引） | 强约束「一个用户只有一条生效额度」，防并发重复授信 |
| `uk_idem` / 各表 `idempotency_key` | 支付/借款重复提交防护 |
| `idx_risk_rules_scene` | 决策时按场景加载启用规则并按优先级排序 |
| `idx_decision_biz` | 后台从借据反查决策链路（可回溯） |

### 4.6 种子数据（`seed.ts` 幂等 upsert）

| 表 | 内容 |
|---|---|
| `loan_products` | `CASH_30D`（500~5000，1 期 30 天）、`CASH_90D_3`（1000~10000，3 期）、`CASH_180D_6`（2000~20000，6 期）、`CASH_360D_12`（5000~20000，12 期） |
| `admins` | `superadmin / Admin@123`（首次登录强制改密提示） |
| `settings` | `credit_tiers`、`scorecard_model`、`app_config`、`repay_allocation_order`、`risk_pass_score` |
| `risk_rules` | 8 条预设规则（§8.6） |
| `coupons` | 新人券「首借立减 10 元」、免息券 7 天 |

关键 `settings` 默认值：

```json
// credit_tiers
[
  {"tier":"A","minScore":720,"limitCents":2000000,"dayRateBp":3,"maxTerm":12},
  {"tier":"B","minScore":670,"limitCents":1000000,"dayRateBp":5,"maxTerm":6},
  {"tier":"C","minScore":620,"limitCents":500000,"dayRateBp":6,"maxTerm":3},
  {"tier":"D","minScore":0,  "limitCents":0,      "dayRateBp":8,"maxTerm":1}
]
// repay_allocation_order
["penalty","fee","interest","principal"]
// risk_pass_score
640
```

---

## 5. 状态机

### 5.1 授信申请 `credit_applications.status`

```
                 ┌──────── cancel（用户撤回，可延后）
                 ▼
 draft ──submit──► submitted ──autocheck──► reviewing ──┬─approve──► approved（终态，生成 credit_limits）
   ▲                    │                                ├─reject───► rejected（终态）
   │                    │                                └─manual───► manual ──┬─approve──► approved
   └── 用户补资料 ◄──────┘                                                      └─reject───► rejected
```

| 当前 | 事件 | 目标 | 守卫条件 | 副作用 |
|---|---|---|---|---|
| draft | 提交 | submitted | 资料完整度=100、kyc_level≥2、无进行中申请 | 写 submitted_at，触发风控 apply 场景 |
| submitted | 机审通过 | reviewing | 决策=approve | 异步跑评分卡（≤2s 内），实际同事务完成 |
| submitted | 机审拒绝 | rejected | 决策=reject | 写 reject_code，user.credit_status=rejected，30 天内禁止重申 |
| submitted | 转人工 | manual | 决策=review | 进后台待办，user.credit_status=applying |
| reviewing | 审批通过 | approved | 审计员角色，可调额/调价（不高于档位上限） | 创建 credit_limits（active），user.credit_status=approved |
| reviewing | 审批拒绝 | rejected | 必填 reject_reason | 同上 |
| manual | 审批通过 | approved | 同 reviewing | 同 reviewing |
| manual | 审批拒绝 | rejected | 同 reviewing | 同 reviewing |

**幂等/并发**：同一 `user_id` 存在 `status in (submitted,reviewing,manual)` 时再次提交返回 `40001 CREDIT_APPLY_EXISTS`。审批用 `UPDATE ... WHERE id=? AND status IN ('reviewing','manual')`，影响行数 0 → `80003 REVIEW_ALREADY_DONE`。

### 5.2 借据 `loans.status`

```
 created ──submit──► reviewing ──pass──► disbursing ──ok──► active ──┬─全部结清──► settled
    │                   │                    │                      └─有逾期期次──► overdue ──结清──► settled
    │                   │                    └─fail──► failed（释放冻结额度）
    │                   └─reject──► rejected（释放冻结额度）
    └─用户取消/超时未确认──► rejected（同上）
```

| 当前 | 事件 | 目标 | 守卫 | 副作用 |
|---|---|---|---|---|
| created | 提交审核 | reviewing | 额度已冻结、风控通过 | 写 review_at；`auto_approve=1` 时同事务直跳 disbursing |
| reviewing | 人工通过 | disbursing | 角色 auditor/admin | 调放款适配层；成功→active |
| reviewing | 人工拒绝 | rejected | 必填 reject_code | 解冻额度、通知用户 |
| disbursing | 放款成功 | active | tradeNo 非空 | 写 disburse_at、first/final_due_date；额度 used+=本金，frozen-=本金；生成 4 条消息 |
| disbursing | 放款失败 | failed | 适配层返回 ok=false | 解冻额度、fail_reason、人工重试入口 |
| active | 逾期 job | overdue | 任一期次 overdue_days>0 | overdue_days/overdue_amount 更新 |
| overdue | 全额结清 | settled | 所有期次 paid | settled_at，额度 used 释放，邀请返现触发 |
| active | 全额结清 | settled | 同上 | 同上 |

**不允许**：settled → 任何状态；rejected/failed → active（只能新建借据）。

### 5.3 账单期次 `loan_schedules.status`

```
 unpaid ──部分还款──► partial ──补齐──► paid
   │                     │
   └──逾期──► overdue ◄───┘ ──补齐（含罚息/减免）──► paid
```

| 当前 | 事件 | 目标 | 规则 |
|---|---|---|---|
| unpaid | 部分核销后 `paid_total < total+penalty` | partial | 按核销顺序记账 |
| unpaid/partial | 还款后 `paid_total >= total+penalty` | paid | 写 paid_at |
| unpaid/partial | `due_date < today`（job） | overdue | overdue_days 每日 +1 |
| overdue | 逾期结清 | paid | 同时清零 loans.overdue_days（若无其他逾期期次） |

**一致性约束**：`period_no` 递增还款（不允许跳期），提前结清除外（一次性把剩余所有期次置 paid 并把未到期利息按产品配置减免）。

### 5.4 还款单 `repayments.status`

```
 pending ──发起支付──► （同步结果）──► success ──退款──► refunded
    │                        └──────► failed ──重试──► pending（新建单，不复用）
    └─超时 30min 未支付──► failed（fail_reason=EXPIRED）
```

| 当前 | 事件 | 目标 | 守卫 |
|---|---|---|---|
| pending | 支付成功（回调/查询） | success | 校验金额 == amount_cents，回调验签通过 |
| pending | 支付失败 | failed | 记录 fail_reason，不允许改回 success |
| pending | 30 分钟未回调 | failed | job 轮询网关补单后仍无结果则关闭 |
| success | 财务退款 | refunded | 角色 finance/super，必须写 remark，生成反向流水 |

**幂等**：`repayments.repayment_no` 唯一；回调处理用 `UPDATE repayments SET status='success' WHERE id=? AND status='pending'`，0 行即已处理，直接返回成功（防第三方重复通知）。

---

## 6. API 契约

### 6.1 通用约定

| 项 | 约定 |
|---|---|
| Base | `http://localhost:4000/api/v1`（C 端）；`/api/v1/admin`（后台） |
| 编码 | UTF-8，`Content-Type: application/json` |
| 鉴权 | `Authorization: Bearer <accessToken>`；白名单接口见表格"鉴权=否" |
| 请求头 | `X-Request-Id`（可选，缺省服务端生成）、`X-Device-Id`（必传）、`X-Client-Version`、`Idempotency-Key`（写操作必传） |
| 响应体 | `{ code, message, data, requestId, timestamp }` |
| HTTP 状态 | 必须语义化：200 成功 / 400 参数 / 401 未认证 / 403 无权限 / 404 不存在 / 409 状态冲突 / 422 业务校验 / 429 限流 / 500 内部 / 502 第三方 |
| 分页 | 入参 `page`（默认 1）、`pageSize`（默认 20，上限 50）；出参 `{ list, total, page, pageSize, hasMore }` |
| 时间 | ISO-8601 UTC；展示由客户端转 Asia/Shanghai |
| 金额 | 全部整数分；前端展示统一 `MoneyText` 组件转元 |
| 枚举 | 用英文枚举值传输，中文映射在客户端 `enums.ts` |

```ts
// packages/shared/src/types/api.ts
export interface ApiResponse<T> {
  code: number;        // 0 = 成功
  message: string;
  data: T | null;
  requestId: string;
  timestamp: number;   // 毫秒
}
export interface PageResult<T> {
  list: T[]; total: number; page: number; pageSize: number; hasMore: boolean;
}
```

### 6.2 错误码分段

| 段 | 域 | 示例 |
|---|---|---|
| 0 | 成功 | `0 SUCCESS` |
| 10xxx | 通用/网关 | 10001 参数错误、10002 限流、10003 幂等冲突、10004 资源不存在、10005 内部错误、10006 第三方异常 |
| 20xxx | 认证 | 20001 未登录、20002 Token 非法、20003 Token 过期、20004 刷新令牌失效、20005 验证码错误、20006 验证码过期、20007 发送过频、20008 密码错误、20009 账号冻结、20010 账号锁定 |
| 30xxx | 用户/KYC | 30001 资料不完整、30002 身份证非法、30003 身份证已注册、30004 未通过实名、30005 人脸失败、30006 银行卡非法、30007 绑卡数量超限 |
| 40xxx | 授信 | 40001 已有进行中申请、40002 授信被拒（冷却期）、40003 授信冻结、40004 金额超范围、40005 无可用额度、40006 额度已过期 |
| 50xxx | 借据/放款 | 50001 超过可用额度、50002 期限非法、50003 状态不允许该操作、50004 借据不存在、50005 放款失败、50006 风控拒绝 |
| 60xxx | 账单/还款 | 60001 账单不存在、60002 已结清、60003 金额不匹配、60004 还款单状态非法、60005 支付失败、60006 优惠券不可用、60007 存在逾期需先结清 |
| 70xxx | 风控 | 70001 转人工审核、70002 命中黑名单、70003 设备异常 |
| 80xxx | 后台 | 80001 无操作权限、80002 登录失败、80003 审批已完成、80004 后台账号禁用 |
| 90xxx | 系统 | 90001 数据库异常、90002 配置错误、90003 任务执行失败 |

```ts
// packages/shared/src/error-codes.ts（片段）
export const ERR = {
  SUCCESS: 0,
  PARAM_INVALID: 10001,
  RATE_LIMITED: 10002,
  IDEMPOTENT_CONFLICT: 10003,
  NOT_FOUND: 10004,
  INTERNAL: 10005,
  THIRD_PARTY: 10006,
  TOKEN_MISSING: 20001,
  SMS_CODE_INVALID: 20005,
  KYC_NOT_PASSED: 30004,
  CREDIT_APPLY_EXISTS: 40001,
  LOAN_STATUS_ILLEGAL: 50003,
  RISK_REJECTED: 50006,
  BILL_ALREADY_PAID: 60002,
  REVIEW_ALREADY_DONE: 80003,
} as const;
export const ERR_HTTP: Record<number, number> = { 0:200, 10001:400, 10002:429, 10003:409, 10004:404, 10005:500, 10006:502, 20001:401, 20002:401, 20003:401, 20005:400, 20007:429, 30004:403, 40001:409, 50003:409, 50006:403, 60002:409, 80003:409 };
```

### 6.3 C 端接口清单

> 幂等列：✅ 表示必须带 `Idempotency-Key`；— 表示无需。

**认证 auth**

| 方法 | 路径 | 鉴权 | 幂等 | 入参要点 | 出参要点 | 主要错误 |
|---|---|---|---|---|---|---|
| POST | `/auth/sms/send` | 否 | — | `{phone, scene:'login'/'repay'/'bind'}` | `{expireIn:300, mockCode?}` | 10002 20007 |
| POST | `/auth/sms/login` | 否 | — | `{phone, code, deviceId, inviteCode?}` | `{accessToken, refreshToken, user, isNew}` | 20005 20006 20009 |
| POST | `/auth/password/login` | 否 | — | `{phone, password}` | 同上 | 20008 20010 |
| POST | `/auth/password/set` | 是 | — | `{password}` | `{}` | 10001 |
| POST | `/auth/refresh` | 否 | — | `{refreshToken}` | `{accessToken, refreshToken}` | 20004 |
| POST | `/auth/logout` | 是 | — | `{refreshToken?}` | `{}` | — |
| GET | `/auth/me` | 是 | — | — | `UserDTO` | 20001 20009 |

**用户 user**

| 方法 | 路径 | 鉴权 | 幂等 | 入参 | 出参 |
|---|---|---|---|---|---|
| GET | `/user/profile` | 是 | — | — | `{profile, kycLevel, completeness}` |
| PUT | `/user/profile` | 是 | — | 基本信息（不含身份证） | `{completeness}` |
| GET | `/user/agreements` | 是 | — | `?type=loan/privacy/credit` | `{title, content, version}` |
| POST | `/user/agreements/sign` | 是 | ✅ | `{type, version}` | `{signedAt}` |

**实名 KYC**

| 方法 | 路径 | 鉴权 | 幂等 | 入参 | 出参 |
|---|---|---|---|---|---|
| POST | `/kyc/idcard/ocr` | 是 | ✅ | `{frontBase64, backBase64}` | `{nameMask, idCardTail, gender, birthDate, address}` |
| POST | `/kyc/idcard/submit` | 是 | ✅ | `{name, idCard, address, ...}` | `{kycLevel}` |
| POST | `/kyc/face` | 是 | ✅ | `{imageBase64}` | `{pass, score}` |
| POST | `/kyc/bankcard` | 是 | ✅ | `{cardNo, holderName, phone, bankName, smsCode}` | `{cardId, tail}` |
| GET | `/kyc/status` | 是 | — | — | `{kycLevel, items:[{type,status,...}]}` |

**授信 credit**

| 方法 | 路径 | 鉴权 | 幂等 | 入参 | 出参 |
|---|---|---|---|---|---|
| GET | `/credit/products` | 是 | — | — | `ProductDTO[]`（含年化区间） |
| GET | `/credit/estimate` | 是 | — | `?amountCents&termCount&productId` | `{totalInterestCents, totalRepayCents, schedules, irrBp}` |
| POST | `/credit/applications` | 是 | ✅ | `{productId, amountCents, termCount, purpose}` | `{appNo, status, score?}` |
| GET | `/credit/applications/current` | 是 | — | — | `{status, rejectCode?, approvedAmountCents?}` |
| GET | `/credit/limit` | 是 | — | — | `{totalCents, usedCents, frozenCents, availableCents, dayRateBp, expireAt, status}` |

**借据 loan**

| 方法 | 路径 | 鉴权 | 幂等 | 入参 | 出参 |
|---|---|---|---|---|---|
| POST | `/loans/quote` | 是 | — | `{amountCents, termCount, productId, couponId?}` | `{principal, interest, fee, couponDiscount, totalRepay, irrBp, schedules}` |
| POST | `/loans` | 是 | ✅ | `{quoteToken, bankCardId, couponId?, smsCode, agreementVersion}` | `{loanNo, status}` |
| GET | `/loans` | 是 | — | `?status&page&pageSize` | `PageResult<LoanBrief>` |
| GET | `/loans/:id` | 是 | — | — | `LoanDetail`（含 schedules、contractUrl） |
| POST | `/loans/:id/prepay-quote` | 是 | — | — | `{remainPrincipal, accruedInterest, penalty, prepayFee, waived, total}` |
| POST | `/loans/:id/prepay` | 是 | ✅ | `{bankCardId, couponId?}` | `{repaymentNo, amountCents}` |

**账单 bill / 还款 repayment**

| 方法 | 路径 | 鉴权 | 幂等 | 入参 | 出参 |
|---|---|---|---|---|---|
| GET | `/bills` | 是 | — | `?status=unpaid/paid/overdue&page` | `PageResult<BillDTO>` |
| GET | `/bills/summary` | 是 | — | — | `{dueCents, overdueCents, nextDueDate, totalUnpaid}` |
| GET | `/bills/:id` | 是 | — | — | `BillDetail`（含费用拆解） |
| POST | `/repayments` | 是 | ✅ | `{loanId, scheduleId? 或 'prepay', bankCardId, couponId?}` | `{repaymentNo, amountCents, feeDetail}` |
| POST | `/repayments/:no/pay` | 是 | ✅ | `{smsCode?}` | `{status:'success'/'failed', tradeNo?}` |
| GET | `/repayments` | 是 | — | `?loanId&status&page` | `PageResult<RepaymentDTO>` |
| GET | `/repayments/:no` | 是 | — | — | `RepaymentDTO` |

**银行卡 / 优惠券 / 邀请 / 消息 / 公共**

| 方法 | 路径 | 鉴权 | 幂等 | 入参 | 出参 |
|---|---|---|---|---|---|
| GET | `/bank-cards` | 是 | — | — | `BankCardDTO[]` |
| POST | `/bank-cards` | 是 | ✅ | 同 kyc/bankcard | `{id}` |
| POST | `/bank-cards/:id/default` | 是 | — | — | `{}` |
| DELETE | `/bank-cards/:id` | 是 | — | — | `{}` |
| GET | `/coupons/available` | 是 | — | `?amountCents&productId&termCount` | `CouponDTO[]`（含 `usable`） |
| GET | `/coupons/mine` | 是 | — | `?status` | `UserCouponDTO[]` |
| POST | `/coupons/:id/claim` | 是 | ✅ | — | `{userCouponId}` |
| GET | `/invite/info` | 是 | — | — | `{inviteCode, invitedCount, rewardedCents, rules}` |
| POST | `/invite/bind` | 是 | ✅ | `{inviteCode}` | `{ok}` |
| GET | `/messages` | 是 | — | `?type&page` | `PageResult<MessageDTO>` |
| GET | `/messages/unread-count` | 是 | — | — | `{count}` |
| POST | `/messages/:id/read` | 是 | — | — | `{}` |
| GET | `/app-config` | 否 | — | — | `{version, hotline, agreements:[...], flags:{}}` |
| GET | `/health` | 否 | — | — | `{ok, db, uptime}` |

### 6.4 Admin 端接口清单

所有接口前缀 `/api/v1/admin`，鉴权=是（Admin JWT），写操作自动落 `audit_logs`。

| 模块 | 方法 | 路径 | 角色 | 入参/出参要点 |
|---|---|---|---|---|
| 认证 | POST | `/auth/login` | 公开 | `{username,password}` → `{accessToken,refreshToken,admin}`；失败 5 次锁 30 分钟 |
| 认证 | GET | `/auth/me` | 全部 | `{id,username,role,menus}` |
| 认证 | POST | `/auth/logout` | 全部 | — |
| 看板 | GET | `/dashboard/overview` | 全部 | `{userTotal,newToday,loanActive,disbursedTodayCents,repayTodayCents,overdueRate,overdueCents,pendingAudit}` |
| 看板 | GET | `/dashboard/trend?days=30` | 全部 | `[{date,disburseCents,repayCents,newUsers}]` |
| 用户 | GET | `/users` | 全部 | `?keyword(手机尾号/userNo)&kycLevel&creditStatus&page` |
| 用户 | GET | `/users/:id` | 全部 | 聚合：资料+额度+借据+还款+风控决策+消息 |
| 用户 | PATCH | `/users/:id/status` | admin/super | `{status,reason}` |
| 用户 | POST | `/users/:id/reset-pwd` | super | `{newPassword}` |
| KYC | GET | `/kyc` | 全部 | `?userId&type&status&page` |
| KYC | GET | `/kyc/:id` | 全部 | 含图片 URL、原始返回 |
| KYC | POST | `/kyc/:id/review` | auditor/admin | `{pass, reason?}`（人工兜底） |
| 授信 | GET | `/credit-applications` | 全部 | `?status&minScore&maxScore&page` |
| 授信 | GET | `/credit-applications/:id` | 全部 | 含评分卡各项、风控命中、历史 |
| 授信 | POST | `/credit-applications/:id/review` | auditor/admin | `{decision:'approve'/'reject', amountCents?, dayRateBp?, maxTerm?, reason}` |
| 额度 | GET | `/credit-limits` | 全部 | `?status&page` |
| 额度 | PATCH | `/credit-limits/:id` | admin/super | `{totalAmountCents?, dayRateBp?, status?, reason}` |
| 借据 | GET | `/loans` | 全部 | `?status&userId&dateFrom&dateTo&page` |
| 借据 | GET | `/loans/:id` | 全部 | 借据 + 期次 + 还款 + 决策 |
| 借据 | POST | `/loans/:id/review` | auditor/admin | `{decision:'approve'/'reject', reason}` → approve 触发放款 |
| 借据 | POST | `/loans/:id/retry-disburse` | finance/super | 失败重试 |
| 账单 | GET | `/schedules` | 全部 | `?status&overdue=1&dueFrom&dueTo&page` |
| 账单 | POST | `/schedules/:id/waive` | finance/super | `{penaltyCents?, interestCents?, reason}` 减免并落审计 |
| 还款 | GET | `/repayments` | 全部 | `?status&channel&dateFrom&dateTo&page` |
| 还款 | POST | `/repayments/:no/manual-confirm` | finance/super | `{tradeNo, remark}` 线下/异常单补登 |
| 还款 | POST | `/repayments/:no/refund` | finance/super | `{reason}` → refunded + 反向流水 |
| 风控 | GET | `/risk-rules` | 全部 | `?scene&status` |
| 风控 | POST | `/risk-rules` | admin/super | 创建（含 DSL 校验） |
| 风控 | PUT | `/risk-rules/:id` | admin/super | 修改 → version+1，旧版本保留 |
| 风控 | POST | `/risk-rules/:id/toggle` | admin/super | `{enabled}` |
| 风控 | POST | `/risk-rules/validate` | admin/super | `{condition}` → `{valid, error?, previewFields}` |
| 风控 | POST | `/risk-rules/sandbox` | admin/super | `{userId, scene, ruleOverride?}` → 决策全链路（不落库） |
| 风控 | GET | `/risk-decisions` | 全部 | `?userId&scene&decision&page` |
| 风控 | GET | `/risk-decisions/:id` | 全部 | 含 features 快照与命中明细 |
| 产品 | GET/POST/PUT | `/products` | admin/super | 上下架、调价（影响新借据，不影响存量） |
| 优惠券 | GET/POST/PUT | `/coupons` | admin/super | 创建/上下架/库存 |
| 优惠券 | POST | `/coupons/:id/issue` | admin/super | `{userIds? / 'all' / tier}` 批量发券 |
| 消息 | POST | `/messages/broadcast` | admin/super | `{segment, title, content}` |
| 配置 | GET | `/settings` | 全部 | 按 group 返回 |
| 配置 | PUT | `/settings` | super | `{key, value}`，JSON 校验 |
| 管理员 | GET/POST/PUT | `/admins` | super | 账号 CRUD（密码不返回） |
| 审计 | GET | `/audit-logs` | 全部（auditor 只读） | `?actorType&action&dateFrom&dateTo&page` |
| 对账 | GET | `/reconciliation/daily?date=` | finance/super | 放款/还款/退款汇总 + 差异单 |

### 6.5 关键接口详细契约

**① POST `/api/v1/loans/quote`（试算，前端借款页实时调用）**

```json
// 请求
{ "amountCents": 300000, "termCount": 3, "productId": 2, "couponId": null }
// 响应 data（数值已按 §7.2 算法核算：日利率 5bp、每期 30 天、每期利率 1.5%）
{
  "principalCents": 300000,
  "totalInterestCents": 9044,
  "totalFeeCents": 0,
  "couponDiscountCents": 0,
  "totalRepayCents": 309044,
  "dayRateBp": 5,
  "irrBp": 1956,                   // 月 IRR 1.5% → 年化 (1.015^12-1)=19.56%
  "quoteToken": "q_8f3a...",       // 10 分钟有效，绑定金额/期限/利率快照，防篡改
  "schedules": [
    { "periodNo":1, "dueDate":"2026-12-08", "principalCents":98515, "interestCents":4500, "totalCents":103015 },
    { "periodNo":2, "dueDate":"2027-01-08", "principalCents":99993, "interestCents":3022, "totalCents":103015 },
    { "periodNo":3, "dueDate":"2027-02-08", "principalCents":101492,"interestCents":1522, "totalCents":103014 }
  ]
}
```

**② POST `/api/v1/loans`（下单）**

```json
// 请求头
Authorization: Bearer xxx
Idempotency-Key: 3f2a1c0e-...
// 请求体
{
  "quoteToken": "q_8f3a...",
  "bankCardId": 12,
  "couponId": 5,
  "smsCode": "123456",
  "agreementVersion": "v2026-11"
}
// 响应（200）
{ "code":0, "message":"ok", "data":{ "loanNo":"L261108000001234567", "status":"reviewing", "needManual": false }, "requestId":"...", "timestamp":1762600000000 }
// 错误示例（403）
{ "code":50006, "message":"综合评估未通过，请 30 天后重试", "data":{"rejectCode":"MULTI_LOAN"}, "requestId":"...", "timestamp":1762600000000 }
```

**③ POST `/api/v1/repayments` + `/repayments/:no/pay`**

```json
// 创建
{ "loanId": 88, "scheduleId": 233, "bankCardId": 12, "couponId": null }
// 返回
{ "repaymentNo":"R261108000009991111", "amountCents":103015,
  "feeDetail":{"principalCents":98515,"interestCents":4500,"penaltyCents":0,"feeCents":0,"couponDiscountCents":0},
  "expireIn":1800 }

// 支付
{ "smsCode":"123456" }
// 成功
{ "status":"success", "tradeNo":"MOCKPAY20261108120001", "paidAt":"2026-11-08T04:00:00.000Z" }
// 失败
{ "code":60005, "message":"支付失败：银行卡余额不足", "data":{"repaymentNo":"R...","failReason":"INSUFFICIENT_BALANCE"} }
```

**④ GET `/api/v1/bills?status=unpaid&page=1&pageSize=20`**

```json
{ "code":0, "message":"ok", "data":{
  "list":[{
    "id":233, "loanId":88, "loanNo":"L261108000001234567", "periodNo":1,
    "dueDate":"2026-12-08", "totalCents":103015,
    "paidCents":0, "remainCents":103015, "penaltyCents":0,
    "status":"unpaid", "daysToDue":30, "canPrepay":true
  }],
  "total":1, "page":1, "pageSize":20, "hasMore":false
}, "requestId":"...", "timestamp":1762600000000 }
```

---

## 7. 核心算法

> 全部实现在 `packages/shared/src/{amortization,irr}.ts`，为纯函数、无 IO、100% 单测覆盖（随机 1000 组对拍）。

### 7.1 金额与利率基础

```ts
// money.ts
export const bpToRate = (bp: number) => bp / 10000;              // 5 -> 0.0005
export const roundCents = (x: number) => Math.round(x);          // 四舍五入到分
export const centsToYuan = (c: number) => (c / 100).toFixed(2);
// 禁止：parseFloat(金额字符串) 参与运算；禁止 Number 累加超过 2^53（业务上限 2000 万，安全）
```

### 7.2 等额本息（核心，必须逐期平账）

```ts
interface ScheduleRow {
  periodNo: number; dueDate: string;
  principalCents: number; interestCents: number; totalCents: number;
}

/**
 * @param principalCents 本金（分）
 * @param termCount      期数 n
 * @param dayRateBp      日利率（bp，5 = 0.05%/日）
 * @param periodDays     每期天数（默认 30）
 * @param firstDueDate   首期到期日 YYYY-MM-DD
 */
function buildEqualInstallment(
  principalCents: number, termCount: number, dayRateBp: number,
  periodDays: number, firstDueDate: string
): ScheduleRow[] {
  const i = bpToRate(dayRateBp) * periodDays;   // 每期利率（30 天期即 0.05%*30=1.5%）
  const n = termCount;
  const factor = Math.pow(1 + i, n);
  // 每期应还（分），四舍五入
  let A = i === 0
    ? Math.round(principalCents / n)
    : Math.round(principalCents * i * factor / (factor - 1));

  const rows: ScheduleRow[] = [];
  let remain = principalCents;

  for (let k = 1; k <= n; k++) {
    // 当期利息 = 剩余本金 × 期利率，先四舍五入到分
    const interest = Math.round(remain * i);
    let principalPart: number;
    let total: number;

    if (k === n) {
      // 末期平账：本金取剩余全部，总额 = 剩余本金 + 末期利息
      principalPart = remain;
      total = principalPart + interest;
    } else {
      principalPart = A - interest;
      // 防御：利率过低会导致本金不递减甚至为负
      if (principalPart <= 0) throw new Error('INVALID_RATE: principal not amortizing');
      if (principalPart >= remain) principalPart = remain;   // 末期提前收敛
      total = principalPart + interest;
    }

    rows.push({
      periodNo: k,
      dueDate: addMonths(firstDueDate, k - 1),   // 到期日按自然月顺延（如 1/31 → 2/28）
      principalCents: principalPart,
      interestCents: interest,
      totalCents: total,
    });
    remain -= principalPart;
  }

  if (remain !== 0) throw new Error('AMORTIZATION_NOT_BALANCED'); // 断言：必须严格为 0
  // 校验：Σ principal === 原本金
  return rows;
}
```

**精度说明**
- 每期利息独立四舍五入，末期本金兜底，因此 `Σ total` 与 `A × n` 最多相差 `(n-1)` 分，这是行业标准做法（末期平账），不做二次摊派。
- 单测断言：`Σ principalCents === principalCents`；`Σ (principal+interest) === 总应还`；`最后一行 remain === 0`。
- 单期产品（7/14/30 天）走 `buildSingleInstallment`：`interest = Math.round(P * bpToRate(dayRateBp) * days)`，一期一还。

### 7.3 IRR（综合年化，监管口径）

```ts
/**
 * 按期现金流求月 IRR：CF = [-P, A1, A2, ..., An]
 * 牛顿迭代优先，失败退化为二分；区间 (-0.9999, 10)
 */
function irrMonthly(cashflows: number[]): number {
  const f = (r: number) => cashflows.reduce((s, cf, t) => s + cf / Math.pow(1 + r, t), 0);
  const df = (r: number) => cashflows.reduce(
    (s, cf, t) => t === 0 ? s : s - t * cf / Math.pow(1 + r, t + 1), 0);

  let r = 0.01;
  for (let iter = 0; iter < 100; iter++) {
    const y = f(r), d = df(r);
    if (Math.abs(y) < 1e-9) return r;
    if (Math.abs(d) < 1e-12) break;
    const next = r - y / d;
    if (!isFinite(next) || next <= -0.9999 || next > 10) break;
    if (Math.abs(next - r) < 1e-10) return next;
    r = next;
  }
  // 二分兜底
  let lo = -0.9999, hi = 10;
  if (f(lo) * f(hi) > 0) throw new Error('IRR_NO_ROOT');
  for (let i = 0; i < 200; i++) {
    const mid = (lo + hi) / 2;
    if (f(lo) * f(mid) <= 0) hi = mid; else lo = mid;
    if (hi - lo < 1e-10) break;
  }
  return (lo + hi) / 2;
}

// 年化（复利口径，用于展示"综合年化利率"）
const annualIrr = Math.pow(1 + irrMonthly(cf), 12) - 1;   // §6.5 示例（3 期、1.5%/期）≈ 19.56%
// 若期次间隔不等（7/14 天产品），改用 XIRR：按实际天数折现
// NPV(r) = Σ CF_t / (1+r)^(days_t/365)
```

**合规校验（放款前强校验）**：`annualIrr <= 0.36`，否则后端抛 `CONFIG_ERROR` 并告警，禁止下单。前端借款页必须展示「综合年化利率 X%」与「总费用」。

### 7.4 罚息（按日计提，幂等）

```ts
// 每日 00:10 penalty.job 执行
function accruePenalty(schedule, today) {
  if (schedule.status !== 'overdue') return;                 // 仅逾期计提
  const base = schedule.remain_principal_cents
             + (schedule.interest_cents - schedule.paid_interest_cents);  // 逾期本金+未付利息
  const daily = Math.round(base * bpToRate(product.penalty_day_rate_bp)); // 每日固定额，先取整
  // 幂等：unique(schedule_id, accrue_date)
  insertIgnore('penalty_accruals', {
    schedule_id: schedule.id, accrue_date: today,
    base_cents: base, rate_bp: product.penalty_day_rate_bp, amount_cents: daily
  });
  // 汇总 + 上限
  const accrued = sumPenalty(schedule.id);
  const cap = Math.round(schedule.principal_cents * bpToRate(product.max_penalty_bp));
  const capped = Math.min(accrued, cap);
  update('loan_schedules', { penalty_accrued_cents: capped }, schedule.id);
}
```

- 起算规则：`due_date` 次日 00:00 起算（还款日当天不计罚息），前端展示「逾期 1 天」= `todayDiff(dueDate) >= 1`。
- 罚息不滚入本金、不复利（合规要求，产品可配但默认关闭）。
- 减免：后台 `POST /schedules/:id/waive` 写 `penalty_waived_cents`，核销时优先用 waived 冲抵。

### 7.5 提前结清

```ts
function prepayQuote(loan, schedules, product, today) {
  const remainPrincipal = sum(schedules.filter(s => s.status !== 'paid')
                                      .map(s => s.remain_principal_cents));
  if (remainPrincipal <= 0) throw BizError(BILL_ALREADY_PAID);

  // 1) 应计利息：从上次结清日（或放款日）到今日，按实际天数
  const lastSettle = loan.last_settle_at ?? loan.disburse_at;
  const days = dayDiff(today, lastSettle);                  // 不含今日，最小 1 天
  const accruedInterest = Math.round(remainPrincipal * bpToRate(loan.day_rate_bp) * days);

  // 2) 未到期利息全额减免（产品配置 prepay_waive_ratio，默认 100%）
  const futureInterest = sum(schedules.filter(s => s.status !== 'paid' && s.due_date > today)
                                      .map(s => s.interest_cents - s.paid_interest_cents));
  const waived = Math.round(futureInterest * product.prepay_waive_ratio / 100);

  // 3) 逾期罚息必须结清
  const penalty = sum(schedules.map(s => s.penalty_accrued_cents - s.paid_penalty_cents));

  // 4) 违约金（默认 0）
  const prepayFee = Math.round(remainPrincipal * bpToRate(product.prepay_fee_bp));

  const total = remainPrincipal + accruedInterest - waived + penalty + prepayFee;

  return { remainPrincipal, accruedInterest, waived, penalty, prepayFee, total };
}
```

执行结清（事务内）：
1. 生成 `repayments(type=prepay, schedule_id=NULL)`；
2. 支付成功后：所有未结清期次 `status='paid'`、`paid_principal=principal_cents`、`remain_principal=0`、`paid_at=now`；
3. `loans.status='settled'`、`settled_at=now`；
4. `credit_limits.used -= 本金`、`version+1`；
5. 落 `account_transactions`（type=repay）。

### 7.6 还款核销顺序

```ts
const ORDER = ['penalty', 'fee', 'interest', 'principal'];   // settings 可配

function allocate(paymentCents, schedule) {
  let left = paymentCents;
  const result = { penalty: 0, fee: 0, interest: 0, principal: 0 };
  const due = {
    penalty: schedule.penalty_accrued_cents - schedule.paid_penalty_cents,
    fee:     schedule.fee_cents - schedule.paid_fee_cents,
    interest:schedule.interest_cents - schedule.paid_interest_cents,
    principal:schedule.remain_principal_cents,
  };
  for (const k of ORDER) {
    const pay = Math.min(left, Math.max(0, due[k]));
    result[k] = pay; left -= pay;
  }
  // left > 0 的场景：溢缴款（不允许，前端已限制金额；如出现记 account_transactions 待退）
  return result;
}
```

### 7.7 授信额度与定价（评分卡 → 档位 → 额度/利率）

```ts
function decideCredit(user, features, riskAction) {
  // 1) A 卡得分（见 §8.3）
  const { score, pd } = scorecard.score(features);

  // 2) 档位映射（settings.credit_tiers）
  const tiers = getSetting('credit_tiers');           // 见 §4.6
  const tier = tiers.find(t => score >= t.minScore) ?? tiers.at(-1);

  // 3) 基础额度 = min(档位额度, 月收入 × 倍数上限, 平台单户上限)
  const incomeCap = Math.round((user.monthly_income_cents ?? 0) * 0.5);  // 收入倍数 0.5
  let limit = Math.min(tier.limitCents, incomeCap, 2000000);

  // 4) 风控动作修正
  let rate = tier.dayRateBp;
  if (riskAction.limitFactor) limit = Math.round(limit * riskAction.limitFactor);
  if (riskAction.rateDeltaBp) rate += riskAction.rateDeltaBp;

  // 5) 多头扣减（外部 bureau）
  if (features.multiLoanCount30d >= 3) { limit = Math.round(limit * 0.7); rate += 1; }

  // 6) 百元取整 + 最低额度门槛
  limit = Math.floor(limit / 10000) * 10000;          // 百元（10000 分）取整
  if (limit < 50000) return { decision: 'reject', reason: 'LIMIT_TOO_LOW' };

  // 7) 定价上限约束（年化 ≤ 36%）
  const apr = irrAnnual(limit, tier.maxTerm, rate);
  if (apr > 0.36) rate = clampRateToApr36(rate, tier.maxTerm);

  return { decision: 'approve', amountCents: limit, dayRateBp: rate, score, pd, tier: tier.tier };
}
```

---

## 8. 风控引擎

### 8.1 总体结构

```
features.ts（特征装配）
   ├─ user.*       来自 users / user_profiles（年龄、收入、学历、婚姻、地区）
   ├─ kyc.*        来自 kyc_records（实名等级、人脸分、银行卡验证）
   ├─ behavior.*   来自 loans / repayments / credit_applications 聚合（申请次数、历史还款表现）
   ├─ external.*   来自 BureauProvider（多头家数、查询次数、黑名单）
   └─ device.*     来自请求头（deviceId、IP、UA、是否模拟器/root 标记，由客户端上报+服务端校验）
        ↓
engine.decide(scene) → 按 priority 顺序求值规则 → 聚合动作 → 评分卡 → 最终决策
        ↓
risk_decisions（特征快照 + 命中明细 + rule_version）→ 可回溯复现
```

### 8.2 规则 DSL

```json
{
  "code": "R0103",
  "name": "近30天多头借贷≥3家",
  "scene": "borrow",
  "priority": 100,
  "condition": {
    "all": [
      { "field": "external.multiLoanCount30d", "op": "gte", "value": 3 },
      { "field": "user.kycLevel", "op": "gte", "value": 2 }
    ]
  },
  "action": { "type": "review", "reason": "MULTI_LOAN" },
  "weight": 0
}
```

**逻辑节点**：`all`（与）、`any`（或）、`not`。最多嵌套 3 层，节点数 ≤ 20（防性能退化）。

**算子表**（`operators.ts` 注册表，新增算子必须注册 + 单测）：

| 算子 | 说明 | 示例 |
|---|---|---|
| `eq` / `neq` | 相等/不等 | `user.gender eq "F"` |
| `gt` / `gte` / `lt` / `lte` | 数值比较 | `user.age lt 22` |
| `in` / `not_in` | 集合 | `user.province in ["新疆","西藏"]` |
| `between` | 闭区间 | `user.monthlyIncomeCents between [0,300000]` |
| `contains` | 数组包含 | `behavior.tags contains "MULTI_LOAN"` |
| `regex` | 正则（预编译+超时保护） | `device.ua regex "^.*MicroMessenger.*$"` |
| `exists` | 非空 | `external.blacklist exists true` |
| `count_gt` | 窗口聚合 | `behavior.applyCount30d count_gt 5` |

**动作表**：

| type | 语义 | 是否终止 |
|---|---|---|
| `reject` | 直接拒绝 | 是（立即返回） |
| `review` | 转人工 | 否（最终决策=review） |
| `lower_limit` | 额度打折（`factor` 0~1） | 否（累乘） |
| `raise_rate` | 利率上浮（`deltaBp`） | 否（累加） |
| `require_kyc` | 要求提升实名等级 | 是（返回 30004） |
| `tag` | 打风险标签 | 否 |

### 8.3 A 卡评分卡（逻辑回归 + PDO 刻度）

```ts
// 特征入模：z = Σ w_i * x_i + b，x 已做分箱/归一化
const z = model.intercept + model.weights.reduce((s, w, i) => s + w * features[model.names[i]], 0);
const pd = 1 / (1 + Math.exp(-z));                        // 违约概率 0~1
// PDO 刻度：基准分 600 对应 odds=1:1，PDO=20（odds 翻倍 +20 分）
const score = Math.round(600 - (20 / Math.LN2) * Math.log(pd / (1 - pd)));
// clamp 到 300~850
```

默认模型（seed，权重可后台热更新，存 `settings.scorecard_model`）：

```json
{
  "intercept": -1.2,
  "names": ["incomeLog","ageScore","eduScore","hasHouse","historyRepayRate","multiLoanCount30d","deviceRisk"],
  "weights": [0.55, 0.18, 0.12, 0.20, 0.90, -0.35, -0.60],
  "passScore": 640,
  "reviewScore": 600
}
```

映射：`score >= passScore → approve`；`reviewScore <= score < passScore → review`；`< reviewScore → reject`（与规则动作取最严）。

### 8.4 决策执行流程

```ts
function decide(input: { scene, user, biz }): Decision {
  const t0 = Date.now();
  const features = buildFeatures(input);                 // 含外部查询（带 5s 超时 + 缓存 10min）
  const rules = ruleRepo.enabledByScene(input.scene);    // 按 priority ASC
  const hits = [];
  let final: 'approve'|'reject'|'review' = 'approve';
  const adjust = { limitFactor: 1, rateDeltaBp: 0 };

  for (const r of rules) {
    const cond = JSON.parse(r.condition_json);
    if (!evalNode(cond, features)) continue;
    const act = JSON.parse(r.action_json);
    hits.push({ code: r.code, version: r.version, action: act, weight: r.weight });

    switch (act.type) {
      case 'reject': return persist('reject', hits, features);    // 短路
      case 'require_kyc': return persist('reject', hits, features, 30004);
      case 'review': final = 'review'; break;
      case 'lower_limit': adjust.limitFactor *= act.factor; break;
      case 'raise_rate': adjust.rateDeltaBp += act.deltaBp; break;
      case 'tag': features.tags.push(act.tag); break;
    }
  }

  const { score, pd } = scorecard.score(features);
  if (final !== 'review') {
    if (score < model.reviewScore) final = 'reject';
    else if (score < model.passScore) final = 'review';
  }
  return persist(final, hits, features, undefined, { score, pd, adjust });
}

function persist(decision, hits, features, code?, extra?) {
  const id = repo.insert({
    decision_no: genNo('D'),
    rule_version: `max:${ruleRepo.maxVersion()}`,
    features_json: JSON.stringify(features),    // 全量快照，事后可复现
    hit_rules_json: JSON.stringify(hits),
    decision, score: extra?.score, pd: extra?.pd,
    level: levelOf(extra?.score), latency_ms: Date.now() - t0,
  });
  return { id, decision, code, ...extra };
}
```

**三个必须**：① 决策必落库；② 特征必须全量快照（否则规则迭代后无法回溯）；③ 规则版本必须记录（`max:17` 表示当时规则最大版本 17）。

### 8.5 多头 / 黑名单 / 设备指纹

| 维度 | 数据源 | 判定 |
|---|---|---|
| 多头借贷 | `external.multiLoanCount30d`（Mock/Bureau） | ≥3 家 → review；≥7 家 → reject |
| 黑名单 | `external.blacklist` + 本地 `users.status=frozen` | 命中 → reject，永久标记 |
| 身份证重复 | `user_profiles.id_card_hash` 唯一索引 | 重复注册 → reject（30003） |
| 设备聚集 | `risk_decisions.device_id` 聚合（同设备 ≥3 个用户 7 天内申请） | → review |
| 设备异常 | 客户端上报 `isRoot/isEmulator/isHooked`（服务端做基础校验，不作为唯一依据） | → review 或 reject |
| IP 异常 | 同 IP 24h 内申请 > 10 次 / 代理 IP 库 | → review |
| 行为异常 | 注册到申请 < 60s、验证码重试 > 3 次 | → review |

### 8.6 默认规则集（seed 8 条）

| code | 场景 | 条件 | 动作 |
|---|---|---|---|
| R0101 | apply | `user.age lt 22 or user.age gt 55` | reject `AGE_LIMIT` |
| R0102 | apply | `external.blacklist eq true` | reject `BLACKLIST` |
| R0103 | borrow | `external.multiLoanCount30d gte 3` | review `MULTI_LOAN` |
| R0104 | borrow | `behavior.applyCount1d gt 3` | reject `FREQUENT_APPLY` |
| R0105 | borrow | `device.isEmulator eq true` | review `DEVICE_RISK` |
| R0106 | borrow | `user.kycLevel lt 2` | require_kyc |
| R0107 | borrow | `behavior.overdueCount12m gte 1` | lower_limit 0.5 + raise_rate 1 |
| R0108 | borrow | `external.queryCount90d gte 12` | review `OVER_QUERY` |

后台提供「规则沙箱」：选一个真实用户 + 指定场景，跑一次决策但不落库，展示每个特征的取值、每条规则命中情况、最终分数与决策，用于上线前验证。

---

## 9. 安全与合规

### 9.1 认证与会话

| 项 | 方案 |
|---|---|
| Access Token | JWT HS256，`{ sub, ut:'user'/'admin', jti, iat, exp }`，有效期 2h |
| Refresh Token | 随机 32 字节 base64url，DB 存 `sha256`，有效期 30d，**一次性轮换**（用旧换新，旧的立即 revoke） |
| 重放检测 | 若收到已 revoke 的 refresh，判定令牌泄露 → revoke 该用户全部 refresh + 强制重新登录 |
| 密码 | `bcrypt(cost=12)`；登录失败 5 次锁定 30 分钟（`admins.locked_until`） |
| 短信验证码 | 6 位数字，5 分钟有效，同手机号 60s/次、10 次/日；验证失败 5 次作废；存 `HMAC(code)` 而非明文 |
| 权限 | C 端：所有查询强制 `WHERE user_id = req.userId`；Admin：`role` 白名单中间件（`auditor` 只能审批，`finance` 只能动钱，`super` 全权） |

### 9.2 敏感数据加密与脱敏

```ts
// utils/crypto.ts
// 密文格式： v1.<iv_b64>.<tag_b64>.<ct_b64>
const KEY = Buffer.from(env.DATA_KEY_HEX, 'hex');   // 32 字节，来自环境变量/KMS
const BLIND_KEY = Buffer.from(env.BLIND_KEY_HEX, 'hex');

export function encrypt(plain: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', KEY, iv);
  const ct = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  return `v1.${iv.toString('base64')}.${cipher.getAuthTag().toString('base64')}.${ct.toString('base64')}`;
}
export const blindIndex = (v: string) => createHmac('sha256', BLIND_KEY).update(v).digest('hex');
export const maskPhone = (p: string) => p.replace(/^(\d{3})\d{4}(\d{4})$/, '$1****$2');
export const maskIdCard = (id: string) => id.replace(/^(.{6}).*(.{4})$/, '$1********$2');
export const maskCardNo = (c: string) => c.replace(/^(\d{4})\d+(\d{4})$/, '$1 **** **** $2');
```

| 字段 | 存储 | 查询 | 展示 |
|---|---|---|---|
| 手机号 | `phone_enc` AES-GCM | `phone_hash` HMAC 盲索引 | `138****8888` |
| 身份证 | `id_card_enc` | `id_card_hash` | `110101********1234` |
| 银行卡号 | `card_no_enc` | `card_no_hash` | `6222 **** **** 1234` |
| 姓名 | `real_name_enc` | 不查询 | `张*` |
| 密码 | bcrypt | — | 永不返回 |
| 日志 | pino serializer 统一脱敏 `phone/idCard/cardNo/token/password` 字段 | — | — |

**密钥管理**：开发期放 `.env`（gitignore）；生产必须走环境变量注入或 KMS，代码中零硬编码；`DATA_KEY` 轮换方案见 §12。

### 9.3 幂等

- 中间件 `idempotency.ts`：拦截所有 `POST`，读 `Idempotency-Key`；
- 首次请求：`INSERT idempotency_keys(key, scope, request_hash, status='processing')`，唯一冲突说明并发重复 → 返回 `10003`；
- 业务成功：`status='done'`，存 `response_json` + `http_status`；
- 重复请求：`request_hash` 一致 → 直接回放响应；不一致 → `10003 IDEMPOTENT_CONFLICT`；
- TTL 24h，`outbox.job` 每日清理过期键。

### 9.4 限流

| 接口 | 维度 | 阈值 |
|---|---|---|
| `/auth/sms/send` | 手机号 | 1 次/60s，10 次/日 |
| `/auth/sms/send` | IP | 20 次/小时 |
| `/auth/sms/login` | 手机号 | 10 次/小时 |
| `/auth/password/login` | 手机号+IP | 10 次/小时，5 次失败锁 30min |
| `POST /loans` | 用户 | 3 次/日 |
| `POST /repayments` | 用户 | 10 次/小时 |
| 全局 | IP | 300 次/分钟（`express-rate-limit` 内存 store，单机足够） |

实现：轻量令牌桶（`Map<key, {tokens, ts}>`），进程内即可；多实例部署时切 Redis（预留 `RateLimitStore` 接口）。

### 9.5 注入与越权防护

- **SQL 注入**：仓储层强制 `db.prepare(sql).get/run/all(params)`，禁止字符串拼接 SQL；动态排序字段用白名单映射（`sortFieldMap = { createdAt:'created_at', amount:'principal_cents' }`），未命中回退默认值。
- **水平越权**：所有 C 端资源查询带 `user_id` 条件，例 `SELECT * FROM loans WHERE id=? AND user_id=?`；不存在即 404（不区分"无权"与"不存在"，防探测）。
- **垂直越权**：`adminGuard(roles)` 中间件在路由声明式挂载，例 `router.post('/loans/:id/review', adminGuard(['auditor','admin','super']), ...)`。
- **XSS**：后台富文本（公告/合同）入库前用白名单过滤（`sanitize-html`，仅允许基础标签）；React 默认转义。
- **文件上传**：Mock 场景仅接受 base64 且限 2MB，校验 magic number（JPEG `FFD8`、PNG `89504E47`），文件名随机化，禁止路径穿越。
- **越权改价**：借款金额/利率不接受客户端传参，只接受 `quoteToken`（服务端签名，含金额/期限/利率/过期时间），下单时验签并校验未过期。

### 9.6 审计

- Admin 所有 `POST/PUT/PATCH/DELETE` 由 `audit.ts` 自动落 `audit_logs`（action 由路由元数据声明，如 `loan.review`）；
- 记录 `before_json` / `after_json`（敏感字段脱敏），`request_id` 可串联全链路日志；
- C 端关键操作（实名、借款、还款、绑卡、改密）也落审计（`actor_type='user'`）；
- 审计日志只增不改不删；保留 ≥ 6 个月（`audit.job` 归档到 `audit_logs_archive`，可延后）。

### 9.7 合规清单（研发必须落地）

| 要求 | 落地方式 |
|---|---|
| 综合年化明示 | 借款页、合同、还款计划三处展示 IRR 年化；后端放款前校验 ≤36% |
| 禁止向学生放款 | 资料含「学生」职业 → 规则 R0201 直接拒绝 |
| 授权链路 | 征信授权、隐私政策、借款合同，签署记录 `user_agreements`（可并入 audit_logs） |
| 冷静期/撤回 | 借据 `created` 状态 30 分钟内用户可取消（当期实现） |
| 数据最小化 | 不采集通讯录/相册；自拍图仅存 7 天（job 清理） |
| 逾期催收合规 | 仅站内信 + 短信，不联系第三方紧急联系人（当期不做外呼） |

---

## 10. 部署与运行

### 10.1 端口与环境

| 服务 | 端口 | 启动命令 |
|---|---|---|
| server | 4000 | `npm run dev -w @ucash/server` |
| admin | 5173 | `npm run dev -w @ucash/admin`（Vite proxy `/api` → 4000） |
| mobile (web) | 8081 | `npm run dev -w @ucash/mobile` → `expo start --web --port 8081` |
| mobile (native) | 8081 (Metro) | `expo start` 扫码 |

### 10.2 环境变量（`.env.example`）

```ini
# ---- 基础 ----
NODE_ENV=development
PORT=4000
APP_NAME=UCash
APP_BASE_URL=http://localhost:4000
ADMIN_ORIGIN=http://localhost:5173
TZ=Asia/Shanghai

# ---- 数据库 ----
DB_DRIVER=sqlite              # sqlite | sqljs（兜底）
DB_FILE=./data/ucash.db
DB_BACKUP_DIR=./data/backup

# ---- 安全（生产必须替换）----
JWT_SECRET=dev_jwt_secret_change_me_32bytes_min
JWT_ACCESS_TTL=2h
JWT_REFRESH_TTL=30d
DATA_KEY_HEX=000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
BLIND_KEY_HEX=1f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100
BCRYPT_ROUNDS=12

# ---- 适配层 ----
SMS_PROVIDER=mock
FACE_PROVIDER=mock
BUREAU_PROVIDER=mock
PAYMENT_PROVIDER=mock
CONTRACT_PROVIDER=mock
MOCK_SMS_FIXED=123456
MOCK_FACE_FAIL=0
MOCK_BUREAU_BLACKLIST=0
MOCK_PAY_FAIL_RATE=0

# ---- 任务 ----
JOBS_ENABLED=true
JOB_TZ=Asia/Shanghai

# ---- 日志 ----
LOG_LEVEL=debug
LOG_PRETTY=true
```

`config/env.ts` 用 zod 校验，缺失/格式错误直接 `process.exit(1)` 并打印缺失项。

### 10.3 一键启动

`scripts/dev.sh`：

```bash
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
[ -f .env ] || cp .env.example .env
npm install
npm run db:reset -w @ucash/server      # 建表 + 种子（幂等）
npx concurrently -n server,admin,mobile -c blue,green,magenta \
  "npm run dev -w @ucash/server" \
  "npm run dev -w @ucash/admin" \
  "npm run dev -w @ucash/mobile"
```

根 `package.json` scripts：

```json
{
  "scripts": {
    "dev": "bash scripts/dev.sh",
    "dev:server": "npm run dev -w @ucash/server",
    "dev:admin": "npm run dev -w @ucash/admin",
    "dev:mobile": "npm run dev -w @ucash/mobile",
    "build": "npm run build -w @ucash/shared && npm run build -w @ucash/server && npm run build -w @ucash/admin",
    "test": "npm run test -w @ucash/server",
    "lint": "eslint . --ext .ts,.tsx",
    "db:reset": "npm run db:reset -w @ucash/server",
    "seed:demo": "tsx scripts/seed-demo.ts"
  }
}
```

### 10.4 生产部署建议

```
                ┌──────────────── Nginx (443) ────────────────┐
   App/H5/Admin │  /            → admin 静态文件 (dist)        │
                │  /api/        → 127.0.0.1:4000 (proxy_pass)  │
                │  /contracts/  → 静态文件（鉴权后签发临时URL） │
                └──────────────────────┬──────────────────────┘
                                       ▼
                         PM2 cluster? —— 单实例！
                         （SQLite 禁止多进程写，pm2 instances=1）
                                       ▼
                              SQLite /data/ucash.db (WAL)
                                       │
                       每日 03:00 sqlite3 .backup → 保留 7 天
```

```nginx
server {
  listen 443 ssl http2;
  server_name ucash.example.com;

  location / { root /var/www/ucash-admin; try_files $uri /index.html; }

  location /api/ {
    proxy_pass http://127.0.0.1:4000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Request-Id $request_id;
    proxy_read_timeout 30s;
  }
  add_header Strict-Transport-Security "max-age=31536000" always;
  add_header X-Content-Type-Options nosniff always;
}
```

`ecosystem.config.js`：

```js
module.exports = {
  apps: [{
    name: 'ucash-server',
    script: 'apps/server/dist/index.js',
    instances: 1,                  // 必须 1：SQLite 单写
    exec_mode: 'fork',
    max_memory_restart: '512M',
    env: { NODE_ENV: 'production', PORT: 4000, TZ: 'Asia/Shanghai' },
    error_file: 'logs/err.log', out_file: 'logs/out.log', time: true
  }]
};
```

Docker（better-sqlite3 需要编译工具）：

```dockerfile
FROM node:22-bookworm-slim AS base
RUN apt-get update && apt-get install -y python3 make g++ && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package*.json ./
COPY apps/server/package.json apps/server/
COPY packages/shared/package.json packages/shared/
RUN npm ci --omit=dev --registry=https://registry.npmmirror.com
COPY . .
RUN npm run build -w @ucash/shared && npm run build -w @ucash/server
VOLUME ["/app/data"]
EXPOSE 4000
CMD ["node", "apps/server/dist/index.js"]
```

**上线切换 MySQL 的边界**：仓储层是唯一 SQL 出口，切库只需替换 `db/index.ts` 的驱动与 `sql/` 方言（`AUTOINCREMENT`→`AUTO_INCREMENT`，`TEXT`→`VARCHAR/DATETIME`），service 层零改动。建议触发条件：并发 > 100 或需多实例。

---

## 11. 里程碑与工作量拆解

> 单人全栈估算（按 1 人 = 1 人日），并行时按角色拆分。标「必须」为当期交付，标「延后」可下期。

| 天 | 任务 | 交付物 | 优先级 |
|---|---|---|---|
| D1 | monorepo 脚手架、tsconfig、eslint、npm workspaces、shared 包骨架、`MoneyText/enums` | 可 `npm run dev` 起三端空白页 | 必须 |
| D2 | DDL 全量 + migrate + seed（产品/设置/管理员/规则）+ 仓储基类 + 事务封装 + `DbAdapter` | `npm run db:reset` 可重建库 | 必须 |
| D3 | 认证：短信发送/校验、注册登录、JWT+refresh 轮换、限流、错误中间件、requestId、pino | 登录闭环 + 单测 | 必须 |
| D4 | 用户资料、实名（OCR Mock/提交）、人脸（Mock）、绑卡四要素、kyc_level 升级 | 实名闭环 | 必须 |
| D5 | 风控引擎（DSL 求值/算子/字段白名单/决策落库）+ 评分卡 + 8 条预设规则 + 沙箱 | 决策可跑、可回溯 | 必须 |
| D6 | 授信：产品列表、试算、提交申请、自动审批、额度生成、额度查询 | 授信闭环 | 必须 |
| D7 | 借据：quoteToken 签名、下单、期次生成（等额本息）、冻结额度、放款 Mock、状态机 | 借款闭环 | 必须 |
| D8 | 账单：列表/详情/汇总、还款单创建、支付 Mock、核销（顺序/部分还款）、结清 | 还款闭环 | 必须 |
| D9 | 提前结清、罚息 job、逾期 job、额度过期 job、消息生成、优惠券核销 | 逾期与结清闭环 | 必须 |
| D10 | Admin：登录、布局、看板、用户/授信/借据/账单/还款列表与详情 | 后台主流程可操作 | 必须 |
| D11 | Admin：审批（授信/借据）、罚息减免、手动还款/退款、规则管理 UI、审计日志、设置、产品、优惠券 | 后台运营闭环 | 必须 |
| D12 | Mobile：首页/借款/账单/我的 4 tab、实名 3 步、授信激活、借款确认/结果、账单详情/收银台、提前结清 | C 端全链路可跑（web 优先） | 必须 |
| D13 | 联调修复、空态/加载/错误态、金额与日期格式化、埋点日志、e2e 用例（借款→还款→逾期→结清） | 全链路回归通过 | 必须 |
| D14 | 演示数据、README、启动脚本、Nginx/PM2 配置、性能压测（P95） | 可演示版本 | 必须 |
| — | 邀请返现、消息中心、优惠券领取、合同 Mock 预览、对账页 | 运营增强 | 延后 |
| — | 对账 job、审计归档、图片 7 天清理 job | 运维增强 | 延后 |
| — | 原生 iOS/Android 打包、推送通道、指纹/面容登录 | 体验增强 | 延后 |
| — | 压测调优、MySQL 迁移、Redis 限流 | 生产化 | 延后 |

**关键路径**：D2（DDL）→ D5（风控）→ D6（授信）→ D7（借据）→ D8（还款）。这 5 个节点任一延期，整条链路延后，优先保障人力。

**每完成一天必须**：`npm run test` 绿 + 手动走一遍当天闭环 + 更新 `docs/04-api.md`。

---

## 12. 风险清单与降级方案

| # | 风险 | 触发条件 | 影响 | 应对（按优先级） |
|---|---|---|---|---|
| 1 | **better-sqlite3 原生编译失败** | Windows 无 VS Build Tools / Python；Node ABI 不匹配（`NODE_MODULE_VERSION` 报错）；`npm i` 卡在 node-gyp | 服务端起不来，全链路阻塞 | ① 装 `windows-build-tools` 或 VS Build Tools + Python3；② 用 `npx node-gyp rebuild --release` 单独编译；③ **兜底方案：`DB_DRIVER=sqljs`**，实现 `sql.js`（WASM）适配器：启动 `initSqlJs()` 读 `ucash.db` 到内存，写操作后 `debounce 500ms` 落盘（`db.export()` → fs.writeFile 原子替换）；④ 单测同时跑两个驱动（CI 只跑 sqljs） |
| 2 | **expo web 兼容问题** | `react-native-reanimated`/`gesture-handler`/`victory-native` 在 web 白屏或样式错乱；`expo-router` web 直接刷新 404 | 无法用浏览器评审 | ① 不引入 reanimated，动画统一 `Animated` API + `Platform.select({web:{transition:'all .2s'}})`；② `app.json` 设 `web.output:'single'`（SPA 路由）；③ 图表用纯 `View` 拼柱状/用 SVG 库（`react-native-svg` 支持 web）；④ 图片选择在 web 用 `<input type="file">` 兜底（`platform.ts` 分支）；⑤ 日期选择自研 Picker，不引三方原生 picker |
| 3 | **金额精度误差** | 等额本息连续四舍五入导致末期不平 | 总应还 ≠ 各期之和，对账差异、客诉 | ① 全链路整数分；② 末期平账 + `Σprincipal === P` 断言（抛错而非静默）；③ 1000 组随机本金/期数/利率对拍单测；④ 前端只展示服务端返回值，不在本地算钱 |
| 4 | **规则迭代导致决策不可回溯** | 后台改了规则/权重，历史决策无法解释 | 合规风险、客诉无法举证 | ① `risk_decisions` 存 `features_json` + `hit_rules_json` + `rule_version`；② 规则表 `UNIQUE(code, version)` 只增不改历史；③ 沙箱上线前验证；④ 决策详情页可展开完整快照 |
| 5 | **SQLite 单写并发瓶颈** | 并发还款 > 50 QPS 或长事务 | 请求超时、`SQLITE_BUSY` | ① WAL + `busy_timeout=5000`；② 事务内禁止外部调用（放款/短信在事务外）；③ 写操作串行队列（`p-queue` concurrency=1）；④ 超阈值切 MySQL（仓储层已隔离） |
| 6 | **时区/日期边界错误** | 服务器 UTC，逾期判定跨日错误 | 少算/多算逾期天数，罚息错 | ① 进程 `TZ=Asia/Shanghai`；② 业务日期统一 `date.ts`（`dayjs.tz`），禁止 `new Date().getDate()` 直接比较；③ 逾期判定用 `todayStr() > due_date` 字符串比较（`YYYY-MM-DD` 天然可比）；④ 单测覆盖 23:59/00:00 边界 |
| 7 | **JWT/密钥泄露** | `.env` 误提交、日志打印 token | 全站越权 | ① `.gitignore` 含 `.env`；② pino serializer 脱敏 `authorization/token/password`；③ 密钥轮换：`DATA_KEY` 支持 `v1/v2` 前缀，解密按前缀选 key，新数据用最新 key；④ 泄露时 revoke 全部 refresh |
| 8 | **Mock 契约与真实厂商不一致** | 接真实短信/支付时字段不匹配 | 上线返工 | ① 适配层接口先定；② Mock 返回结构与真实厂商对齐（预留 `raw` 字段）；③ 接真实厂商只写 `real.ts`，业务零改动 |
| 9 | **npm workspaces + Metro 解析失败** | `Unable to resolve @ucash/shared` | 移动端起不来 | ① `metro.config.js` 配 `watchFolders` + `nodeModulesPaths` + `disableHierarchicalLookup`；② shared 包 `main` 指向 `src/index.ts`（不走构建）；③ 必要时 `npx expo start -c` 清缓存 |

**Top3 风险（必须提前验证）**：① better-sqlite3 编译（D1 就验证，别等到 D2）；② expo web 白屏（D1 起空壳就跑 web）；③ 金额精度（D7 之前单测先写）。

---

## 13. 非功能性承诺（验收基线）

| 维度 | 目标 | 验收方式 |
|---|---|---|
| 接口响应 | 核心接口（登录/额度/账单/试算）P95 ≤ 300ms（本地）；≤ 500ms（4G 网络） | `autocannon -c 50 -d 30` |
| 并发 | 50 并发写、200 并发读无错误（SQLite 上限内） | 压测脚本 |
| 首屏 | Web 端 FCP ≤ 2s；App 冷启动 ≤ 3s | Lighthouse / 真机 |
| 可用性 | 单机 ≥ 99%（验证期）；生产 ≥ 99.5% | PM2 + 健康检查 |
| 数据一致性 | 借款/还款事务 100% 原子；对账差异 = 0 | 每日对账脚本 |
| 安全 | 无明文敏感字段落库；无 SQL 拼接；越权用例 100% 拦截 | 代码审计 + 渗透用例 |
| 测试覆盖 | `amortization/irr/settle/risk-engine` 100%；service ≥ 60% | vitest coverage |
| 备份 | 每日 03:00 全量备份，保留 7 天 | `scripts/backup.sh` |

---

## 14. 端到端验收清单（演示脚本，必须全绿）

1. 新用户手机号注册（验证码 123456）→ 首页展示「未激活额度」
2. 提交实名（身份证 + 人脸 Mock 通过）→ kyc_level=2
3. 绑定银行卡 → kyc_level=3
4. 提交授信申请 → 机审通过 → 额度 5000 元、日利率 0.05%
5. 借款 3000 元 / 3 期 → 展示费用明细与综合年化 → 确认下单 → 放款成功 → 生成 3 期账单
6. 账单页可见待还、点进详情看到本金/利息拆分
7. 部分还款 → 期次变 `partial`，剩余金额正确
8. 补足还款 → 期次 `paid`，借据进度更新
9. 手动把某期 `due_date` 改为昨天 → 跑逾期 job → 状态 `overdue`、罚息按日增长
10. 提前结清 → 展示剩余本金 + 应计利息 + 罚息 - 未到期利息减免 → 支付 → 借据 `settled`、额度释放
11. 后台：登录 → 看板数据正确 → 在授信审批里通过一条人工单 → 在审计日志看到操作记录
12. 后台：新建一条规则「年龄 < 22 拒绝」→ 沙箱验证命中 → 启用后新用户申请被拒

---

## 15. 编码前置检查（D1 当天完成）

```bash
node -v          # 必须 v22.x
npm -v           # 必须 10.x
python --version # 建议 3.11+（node-gyp 需要）
# Windows 如无 VS Build Tools：
# npm i -g windows-build-tools （管理员 PowerShell）或装 VS 2022 Build Tools + C++ 工作负载
node -e "require('better-sqlite3')"   # 装完依赖后必须无报错
npx expo --version
```

任一项不通过，立即启用 §12 的对应降级方案，不得带病开工。

---

[技术研发方案]
