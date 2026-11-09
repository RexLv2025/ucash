> **【变更说明 2026-11-09】** 服务端数据库驱动已由 better-sqlite3 改为 Node 内置 `node:sqlite`，运行环境要求 Node ≥ 22.5（推荐 24 LTS）。文中涉及 better-sqlite3 的安装/编译/降级方案不再需要。

# UCash 交付作业手册（Phase 2–5）

- 版本：v2.4.0 ｜ 编制日期：2026-11-08 ｜ 适用里程碑：验收 → 上线 → 稳定运行 → 首月增长
- 覆盖四角色：质量测试官（第 1 章）· 上线发布师（第 2 章）· 运维守护师（第 3 章）· 增长运营师（第 4 章）
- 编写原则：**命令可直接粘贴执行、阈值可被判定、指标口径可被 SQL 复算**。凡系统尚不具备的能力，标注 `[待补]` 并给出最小落地改动，不写成已完成。

## 0. 事实基线（本文数字的唯一来源）

| 项 | 实测值 | 取证方式 |
| --- | --- | --- |
| 客户端 | Flutter 3.x / Dart `^3.13.7` / Material 3，`version: 2.4.0+24` | `apps/mobile_flutter/pubspec.yaml` |
| 客户端页面 | `lib/pages` 24 个文件 = 22 个业务页面 + `main_shell` 导航壳 + 1 | `ls apps/mobile_flutter/lib/pages \| wc -l` |
| 客户端依赖 | `http`、`shared_preferences`、`intl`（无状态管理/路由库） | `pubspec.yaml` |
| 业务中台 | Node 22 + Express 4 + TypeScript + better-sqlite3，端口 `4000` | `apps/server/package.json`、`src/index.ts` |
| 数据表 | **18 张**（`schema.sql` 18 条 `CREATE TABLE`，`sqlite_master` 实测一致） | 查询 `sqlite_master` |
| 路由/服务 | `auth.ts` 161 行、`app.ts` 497 行、`admin.ts` 545 行；`risk/credit/loan/repay` 共 1171 行 | `wc -l` |
| 数据库 | `apps/server/data/ucash.db`，`journal_mode=WAL`、`foreign_keys=ON` | `src/db.ts:15-16` |
| 认证 | JWT 用户 `30d` / 管理员 `12h`；bcrypt cost 10；PII 用 AES-256-GCM | `middleware/auth.ts`、`lib/security.ts` |
| RBAC | `ops(1) < risk(2) < approver(3) < super(9)`，`adminRouter.use(requireAdmin('ops'))` | `middleware/auth.ts:74-84` |
| 借款要素 | 500–50,000 元、100 元整数倍、3/6/12 期 | `services/loan.ts:12-14,52-56` |
| 风控 | 评分 300–850，`score<600` 拒绝；“转人工”仅授信场景 | `services/risk.ts:214-230` |
| 额度/定价 | 额度 1,000–50,000 元、500 元取整；利率 900–2400bp | `services/risk.ts:73-110` |
| 罚息 | 日万分之五，`cron '5 0 * * *'` 每日 00:05 计提 | `services/repay.ts:7,281-301` |
| 提前结清 | 剩余本金 + 当期未付利息 + 已计提罚息，未来期利息免除，违约金 0 | `services/repay.ts:118-144` |
| 接口验收 | `e2e.ts` 25 条断言，覆盖注册→放款→结清 | `npm run e2e` |
| 运营后台 | Vite 5 + React 18，9 个业务页面，开发端口 5173 | `apps/admin/src/pages` |
| 环境约束 | 本机 Dart VM 派生进程 `ERROR_PIPE_BUSY(231)`，`flutter build/analyze/test` 本机不可用 | `docs/04-flutter-adr.md` 第六节 |
| 文档差异 | README/ADR 写“20 张表”，实测 18 张 | 以库为准，差异列入文末自检清单 |

> 口径纪律：“当前值/实测值”指 2026-11-08 本仓库真实状态；“目标值/阈值”是上线门禁，未达标即阻塞。

---

## 第 1 章 测试保障方案（质量测试官）

### 1.1 测试缺口盘点

| 层 | 现状 | 缺口 | 处置 |
| --- | --- | --- | --- |
| 接口自动化 | `e2e.ts` 25 断言全绿（正向全链路） | 无负向/越权/幂等/并发 | 1.4 补 40 条 |
| 领域单测 | **0 个** `*.test.ts` | 计息、IRR、罚息、额度定价无回归保护 | 1.3 落地 |
| 客户端测试 | `apps/mobile_flutter/test/` **空目录** | 无 Widget 用例 | 1.5 补核心 6 页 |
| CI 卡点 | 仅有 `.github/workflows/build-apk.yml`（main 分支构建未签名 APK，无服务端测试/AAB） | 缺质量门禁与制品规范 | 第 2 章 2.2 合并版 |
| 幂等能力 | `idempotency_keys` 表已建但**全代码未使用** | 还款接口无幂等键 | TC-REP-008 必测 |

四个必须先处理的风险：① `POST /api/repayments` 无幂等保护，快速双击会把下一期一并还掉且不可撤销；② `POST /api/admin/login` 无失败计数与锁定；③ `release` 构建仍用 debug 签名（`android/app/build.gradle.kts`），不可上架；④ 定价上限 2400bp 名义利率对应 IRR 2681bp，超 24% 红线（见 1.3）。

### 1.2 四层测试分层与准入

| 层 | 范围 | 执行命令 | 准入门禁 |
| --- | --- | --- | --- |
| L1 领域单测 | `money.ts` 全部函数 + 额度/定价模型 | `npm --prefix apps/server run test` | `money.ts` 行覆盖 100%、分支 ≥90% |
| L2 接口测试 | 60+ 端点，正向 + 负向 | `npm run e2e` 与 `e2e-negative.ts` | 正向 25/25；负向 40 条全过 |
| L3 组件测试 | 登录/首页/借款/账单/还款/结果页 | `flutter test --reporter expanded` | 6 页全过，无 overflow |
| L4 人工端到端 | 借款状态机 12 跳、后台四角色 | 用例表 + 录屏 | P0 100%，全量 ≥95% |

提测准入冒烟（不过即打回，30 秒）：

```bash
curl -s localhost:4000/health | grep -q '"ok":true' && echo smoke-ok
TOKEN=$(curl -s -X POST localhost:4000/api/auth/login -H 'Content-Type: application/json' -d '{"phone":"13800138000","code":"123456"}' | node -pe 'JSON.parse(require("fs").readFileSync(0)).data.token')
curl -s localhost:4000/api/bills -H "Authorization: Bearer $TOKEN" | head -c 100; echo   # 期望 code:0
```

### 1.3 领域逻辑单测（金标准已实测，不要改）

新建 `apps/server/src/lib/money.test.ts`：

```ts
import assert from 'node:assert/strict';
import test from 'node:test';
import { buildSchedule, calcPenalty, calcSettlement, irrAnnualBp } from './money.js';

test('5000元/18%/6期：金标准与合计守恒', () => {
  const r = buildSchedule(500_000, 1800, 6);
  assert.equal(r.monthlyPaymentCents, 87_763);                                    // 877.63 元
  assert.equal(r.totalInterestCents, 26_576);                                     // 265.76 元
  assert.equal(r.totalRepayCents, 526_576);                                       // 5265.76 元
  assert.equal(r.items.reduce((s, x) => s + x.principalCents, 0), 500_000);        // Σ本金 = 本金
  assert.equal(r.items.reduce((s, x) => s + x.totalCents, 0), r.totalRepayCents);  // Σ应还 = 总应还
  assert.equal(r.items[5].totalCents, 87_761);                                    // 末期平账，尾差 2 分
});

test('全组合边界：Σ本金守恒且 IRR 恒 ≤ 24%', () => {
  for (const amt of [50_000, 300_000, 1_000_000, 5_000_000])
    for (const bp of [900, 1080, 1800, 2160])   // 2160bp 名义 ≈ IRR 2387bp，是 24% 红线下可用最高档
      for (const n of [3, 6, 12]) {
        const s = buildSchedule(amt, bp, n);
        assert.equal(s.items.reduce((q, x) => q + x.principalCents, 0), amt);
        assert.ok(irrAnnualBp(amt, s.items.map((x) => x.totalCents)) <= 2400, `${amt}/${bp}/${n}`);
      }
  assert.equal(irrAnnualBp(500_000, buildSchedule(500_000, 1800, 6).items.map((x) => x.totalCents)), 1956);
});

test('罚息与提前结清口径', () => {
  assert.equal(calcPenalty(100_000, 5, 10), 500);  // 1000 元逾期 10 天 = 5.00 元
  assert.equal(calcPenalty(100_000, 5, 0), 0);
  const s = calcSettlement({ remainingPrincipalCents: 300_000, annualRateBp: 1800, daysSinceLastSettle: 15, penaltyRateBpOfPrincipal: 0 });
  assert.equal(s.accruedInterestCents, 2_250);     // 3000 × 18% × 15/360
  assert.equal(s.totalCents, 302_250);
});
```

> 定价红线（实测）：`rateModel` 上限 2400bp（名义）对应 IRR **2681bp**，超过“综合年化 ≤24%”的监管口径与 README 宣称，属 P0 合规缺陷。修法：上限改为 2160bp（IRR 2387bp），并把 24% 校验建在 IRR 而非名义利率上；后台人工定价同样收紧。

`package.json` 增加 `"test": "node --import tsx --test \"src/**/*.test.ts\""`；执行 `npm --prefix apps/server run test`（期望 3 tests / 0 fail），模型测试用 `DB_PATH=:memory:` 隔离数据库。

额度与定价断言矩阵（与 `scoreCard` 常量对齐）：

| 场景 | 输入 | 期望 |
| --- | --- | --- |
| 白户最低配 | 收入 0、无认证、score 620 | 额度 1,000 元下限；利率 2399bp |
| 标准工薪 | 收入 1 万、三认证、score 745 | 1.25 系数后 500 元取整；利率 1440−240=1200bp |
| 高优客户 | 收入 2 万、三认证、score 800 | ≤5 万封顶；利率 1080−240=900bp 下限 |

### 1.4 接口层：在 25 条正向断言之外补负向集

`e2e.ts` 覆盖注册→授信→借款→放款→账单→还款→结清及账务自洽，但**负向路径零覆盖**——资金系统最容易出 P0 的地方。新增 `apps/server/src/scripts/e2e-negative.ts`（复用 `api()`/`assert()`），错误码对照 `lib/http.ts`：

断言模板：`const r = await api('POST','/api/loans/quote',{amountCents:49_900,termMonths:6},token); assert('金额低于500元被拒', r.code===5001);`。执行：

```bash
npx --prefix apps/server tsx apps/server/src/scripts/e2e-negative.ts   # 需先 npm run dev，期望 40/0
```

并发/幂等专项（`better-sqlite3` 同步执行会串行化，业务层仍可能连扣两期）：

```bash
seq 2 | xargs -P2 -I{} curl -s -X POST localhost:4000/api/repayments -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"loanId":1,"type":"normal","bankCardId":1}' -o /tmp/r{}.json
grep -o '"code":[0-9]*' /tmp/r*.json | sort | uniq -c    # 期望 1 个 0，另一个 6002/6004
```

### 1.5 客户端 Widget 测试（本机不可跑，只在 CI 跑）

`test/` 为空，先补纯逻辑用例，避免把网络依赖带进测试：

```dart
// test/formatters_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ucash/core/formatters.dart';

void main() => test('格式化', () {
  expect(formatMoney(52657600), '526,576.00');
  expect(formatRate(1956), '19.56%');
});
```

执行：`cd apps/mobile_flutter && flutter pub get && flutter test --reporter expanded`（期望 All tests passed）。

Widget 用例（L3）：登录页（空号/格式/倒计时）、首页（额度三栏空态与有值态）、借款确认（滑块越界/期数切换/优惠券后金额刷新）、账单（三 tab 与逾期标签）、还款（卡异常 6003、结清二次确认）、结果页（成功与 E1024 两态）。断言重点：无 RenderFlex overflow、金额与接口一致、错误码文案映射正确。

### 1.6 兼容性矩阵（Android 8–15）

先确认真实 minSdk，不凭记忆：

```bash
cd apps/mobile_flutter/android && ./gradlew :app:properties | grep -iE "minSdk|targetSdk|compileSdk"
```

| 维度 | 覆盖项 | 判定标准 |
| --- | --- | --- |
| 系统 | 8.0(26)/10(29)/12(31)/13(33)/14(34)/15(35) | minSdk<26 则 8.0 必测；≥26 在报告注明“不支持 8.0” |
| ROM | 华为 HarmonyOS 4、小米 HyperOS、OPPO ColorOS、vivo OriginOS、荣耀 MagicOS 各 1 台 | 权限弹窗、后台保活、输入法遮挡、字体 1.3 倍不破版 |
| 分辨率 | 720×1280 / 1080×2340 / 1080×2400 / 1260×2800 / 平板 1200×2000 | 无截断、无横向滚动、金额不被省略 |
| 网络 | 200kbps 限速 +10% 丢包、断网、飞行模式恢复、来电中断 | 20/25s 超时后友好报错，不白屏、可重试、不重复提交 |
| 升级 | 覆盖安装、卸载重装、2.3.x→2.4.0 | token/baseUrl 不丢或可优雅重登；签名一致可覆盖 |

### 1.7 性能基线

| 指标 | 目标（门禁） | 测量方法 |
| --- | --- | --- |
| 冷启动 | ≤ 3.0s（中端机 Android 12） | `adb shell am start -W -n com.ucash.ucash/.MainActivity` 看 `TotalTime` |
| 首屏可交互 | ≤ 2.0s（4G 模拟） | DevTools Performance + 秒表双记 |
| 首页/账单查询 | P95 ≤ 500ms | 下方 autocannon 命令 |
| 试算 `/api/loans/quote` | P95 ≤ 300ms（纯计算） | 同上 |
| 下单/还款（写） | P95 ≤ 800ms | 同上 |
| 放款到账 | ≤ 3s（模拟 2s 延迟 + 500ms×15 轮询） | e2e 步骤 9，取 `disbursed_at - created_at` |
| APK 体积 | arm64 ≤ 25MB；`--split-per-abi` 单包 ≤ 20MB | `ls -lh build/app/outputs/flutter-apk/` |

```bash
npm --prefix apps/server run seed -- --reset     # 造数后再压，空库压测无意义
TOKEN=$(curl -s -X POST localhost:4000/api/auth/login -H 'Content-Type: application/json' -d '{"phone":"13800138000","code":"123456"}' | node -pe 'JSON.parse(require("fs").readFileSync(0)).data.token')
npx --yes autocannon -c 20 -d 30 -H "Authorization=Bearer $TOKEN" http://localhost:4000/api/bills
# 判读：p97.5 ≤ 500ms（写接口 ≤800ms）、Errors=0、Non2xx=0
```

### 1.8 用例清单（40 条，正向 + 负向）

| 编号 | 模块 | 用例标题 | 优先级 | 期望结果 |
| --- | --- | --- | --- | --- |
| TC-AUTH-001 | 登录 | 已注册手机号 + 正确验证码 | P0 | `code=0`，30d JWT，手机号脱敏 |
| TC-AUTH-002 | 登录 | 新号首登自动注册并赠券 | P0 | 建 user/profile/默认卡，发 `NEW20`+`RATE01` |
| TC-AUTH-003 | 登录 | 验证码错误 | P0 | `2001`，不泄露号码是否注册 |
| TC-AUTH-004 | 登录 | 60s 内重复获取验证码 | P1 | `2005` |
| TC-AUTH-005 | 登录 | 未带 token 访问 `/api/bills` | P0 | `1002` |
| TC-AUTH-006 | 登录 | 用户 token 访问 `/api/admin/dashboard` | P0 | `1002`（claims.type≠admin） |
| TC-KYC-001 | 认证 | 合法身份证实名通过 | P0 | 写 `kyc_records`，`realname_verified=1` |
| TC-KYC-002 | 认证 | 身份证校验位错误 | P0 | `1001` |
| TC-KYC-003 | 认证 | 年龄 21 岁 / 56 岁 | P0 | `3005`（22–55 周岁） |
| TC-KYC-004 | 认证 | 职业含“学生” | P0 | `3005`，不得放行 |
| TC-KYC-006 | 认证 | 人脸活体失败 / score=50 | P0 | `3002`，落 rejected 记录 |
| TC-CR-001 | 授信 | 未实名申授信 | P0 | `3001` |
| TC-CR-002 | 授信 | 未人脸申授信 | P0 | `3002` |
| TC-CR-003 | 授信 | 优质客户自动通过 | P0 | 额度 ∈[1000,50000] 元且 500 取整，利率 ∈[900,2400]bp |
| TC-CR-004 | 授信 | 命中黑名单规则 | P0 | `rejected`，落 `risk_decisions` 快照 |
| TC-LOAN-001 | 借款 | 500 元/3 期与 5 万元/12 期试算 | P0 | Σ本金=本金、Σ应还=总应还、IRR ≤2400bp |
| TC-LOAN-002 | 借款 | 金额 499 元（低于下限） | P0 | `5001` |
| TC-LOAN-003 | 借款 | 金额 50,001 元（超上限） | P0 | `5001` |
| TC-LOAN-004 | 借款 | 期数 9 期 | P0 | `5002` |
| TC-LOAN-005 | 借款 | 可用额度不足 | P0 | `4002`，文案带可用额度 |
| TC-LOAN-006 | 借款 | 未勾选合同直接下单 | P0 | `5003` |
| TC-LOAN-007 | 借款 | 篡改 quoteToken（改金额/换用户） | P0 | `1007`/`1003`，金额以服务端 token 为准 |
| TC-LOAN-008 | 借款 | 重复下单（存在 reviewing/disbursing） | P0 | `5004`，不新增借据、不重复冻结额度 |
| TC-LOAN-009 | 借款 | 优惠券不可用（未达门槛/已用/过期） | P1 | `5006`，`NEW20` 门槛 1000 元 |
| TC-PAY-001 | 放款 | 正常放款 reviewing→disbursing→active | P0 | 生成 N 期账单、`used+=本金`、`frozen` 归零、站内信 1 条 |
| TC-PAY-002 | 放款 | 卡异常触发 E1024 | P0 | `status=failed`、`fail_code=E1024`、额度解冻、提示换卡 |
| TC-PAY-003 | 放款 | 失败后换卡重试成功 | P1 | 重新冻结→放款成功，仅一条有效借据 |
| TC-REP-001 | 还款 | 按期还款（首期） | P0 | 期状态 paid、`used` 减本金、流水 1 条、额度立即释放 |
| TC-REP-002 | 还款 | 还清最后一期自动结清 | P0 | `loans.status=settled`，`settled_at` 非空 |
| TC-REP-003 | 还款 | 已结清再还款 | P0 | `6002`，不产生流水 |
| TC-REP-004 | 还款 | 提前结清：免未来利息 | P0 | `savedInterestCents`=剩余期利息和，`total` 不含未来利息 |
| TC-REP-005 | 还款 | 还款卡失效（尾号 0000） | P0 | `6003` |
| TC-REP-006 | 还款 | 逾期 10 天后罚息 | P0 | 罚息 = 逾期本息×0.05%×10，四舍五入到分 |
| TC-REP-007 | 还款 | 逾期户再借款 | P0 | `1007` “存在逾期借款，请先结清” |
| TC-REP-008 | 还款 | 双击“还款”并发 2 次 | P0 | 仅扣 1 期，第二次 `6002`/`6004`（**当前缺口，须修**） |
| TC-SEC-001 | 安全 | A 用户 token 读 B 用户借据 | P0 | `1004`，不区分“不存在/无权限” |
| TC-SEC-002 | 安全 | ops 角色调用审批接口 | P0 | `1003` |
| TC-SEC-003 | 安全 | 响应/日志检索身份证、完整手机号、卡号 | P0 | 仅脱敏值，无明文 |
| TC-OPS-001 | 后台 | 人工定额/定价越界 | P0 | 额度夹在 [1000,50000]、利率夹在 [900,2400] |
| TC-DATA-001 | 账务 | 1.9 的 10 条勾稽 SQL | P0 | 全部零差异，任一非空即阻塞 |

> 执行说明：40 条中 P0 = 33 条必须 100% 通过；P1 = 5 条允许书面豁免（附规避方案）；P2 = 2 条可延后。每条记录“环境/账号/时间/请求 ID”，失败按 Bug 规范提单（标题、级别、环境、步骤、实际 vs 预期、证据、复现概率）。

### 1.9 账务校验 SQL（上线前零差异）

落 `apps/server/src/scripts/audit-check.ts`，一条命令跑完；任一查询有行即 `exit 1`：

```bash
npx --prefix apps/server tsx apps/server/src/scripts/audit-check.ts
# 期望：10/10 PASS，末行 "ACCOUNTING CHECK OK"
```

| # | 校验项 | SQL（SQLite 方言） |
| --- | --- | --- |
| 1 | Σ计划本金 = 借据本金 | `SELECT l.id,SUM(s.principal_cents) sp FROM loans l JOIN loan_schedules s ON s.loan_id=l.id WHERE l.status IN ('active','overdue','settled') GROUP BY l.id HAVING sp<>l.principal_cents;` |
| 2 | Σ计划应还 = 总应还 | `SELECT l.id,SUM(s.total_cents) st FROM loans l JOIN loan_schedules s ON s.loan_id=l.id WHERE l.status IN ('active','overdue','settled') GROUP BY l.id HAVING st<>l.total_repay_cents;` |
| 3 | 已用额度守恒 | `WITH c AS (SELECT u.id,u.used_limit_cents,COALESCE((SELECT SUM(l.principal_cents) FROM loans l WHERE l.user_id=u.id AND l.status IN ('active','overdue')),0)-COALESCE((SELECT SUM(s.paid_principal_cents) FROM loan_schedules s JOIN loans l2 ON l2.id=s.loan_id WHERE l2.user_id=u.id AND l2.status IN ('active','overdue')),0) exp FROM users u) SELECT * FROM c WHERE used_limit_cents<>exp;` |
| 4 | 冻结额度守恒 | `WITH c AS (SELECT u.id,u.frozen_limit_cents,COALESCE((SELECT SUM(l.principal_cents) FROM loans l WHERE l.user_id=u.id AND l.status IN ('reviewing','disbursing')),0) exp FROM users u) SELECT * FROM c WHERE frozen_limit_cents<>exp;` |
| 5 | 流水本金 = 计划已还 | `SELECT id,rp,sch FROM (SELECT l.id,COALESCE((SELECT SUM(r.principal_cents) FROM repayments r WHERE r.loan_id=l.id AND r.status='success'),0) rp,COALESCE((SELECT SUM(s.paid_principal_cents) FROM loan_schedules s WHERE s.loan_id=l.id),0) sch FROM loans l WHERE l.status IN ('active','overdue','settled')) WHERE rp<>sch;` |
| 6 | 单笔流水内平 | `SELECT id,amount_cents,principal_cents+interest_cents+penalty_cents calc FROM repayments WHERE amount_cents<>principal_cents+interest_cents+penalty_cents;` |
| 7 | 已还期金额与状态一致 | `SELECT id,status FROM loan_schedules WHERE (status='paid' AND (paid_principal_cents<>principal_cents OR paid_interest_cents<>interest_cents)) OR (status<>'paid' AND (paid_principal_cents>principal_cents OR paid_interest_cents>interest_cents));` |
| 8 | 结清借据无未付期 | `SELECT l.id,COUNT(*) unpaid FROM loans l JOIN loan_schedules s ON s.loan_id=l.id WHERE l.status='settled' AND s.status<>'paid' GROUP BY l.id;` |
| 9 | 罚息复算（容差 1 分） | `SELECT id,penalty_cents FROM loan_schedules WHERE status='overdue' AND ABS(penalty_cents-ROUND(((principal_cents-paid_principal_cents)+(interest_cents-paid_interest_cents))*5*CAST(julianday(date('now','localtime'))-julianday(due_date) AS INTEGER)/10000.0))>1;` |
| 10 | 逾期天数 = 最早逾期期 | `SELECT l.id FROM loans l JOIN loan_schedules s ON s.loan_id=l.id WHERE l.status='overdue' AND s.status<>'paid' GROUP BY l.id HAVING ABS(l.overdue_days-CAST(julianday(date('now','localtime'))-julianday(MIN(s.due_date)) AS INTEGER))>1;` |

> 已知差异（实测 `apps/server/data/ucash.db`）：`type='settle'` 流水的 `interest_cents` 记的是全部剩余期利息，而 `amount_cents` 只收当期利息（未来利息已免除），实测 id=7、9 两条差 41.98 元，SQL #6 必然命中。这是 P0 账务缺陷：结清流水应只记实收利息，免收部分另落 `waived_interest_cents`，修完再放行。

### 1.10 质量门禁与放行结论

| 门禁项 | 阈值 | 判定方式 |
| --- | --- | --- |
| P0 缺陷 | **= 0** | 缺陷库按级别统计 |
| P1 缺陷 | 全部关闭或书面豁免（附规避方案与责任人） | 豁免记录入发布单 |
| 核心链路 | 100% 通过（注册→授信→借款→放款→还款→结清） | `npm run e2e` 25/25 |
| 负向用例 | 40 条 100% 通过 | `e2e-negative.ts` |
| 账务校验 | 10 项零差异（当前 #6 命中结清流水，须先修） | `audit-check.ts` exit 0 |
| 接口性能 | 读 P95 < 500ms、写 P95 < 800ms、错误率 0 | autocannon 报告 |
| 客户端 | 崩溃率 ≤0.1%、首屏 ≤2s、冷启动 ≤3s | 真机 + DevTools |
| 安全 | 水平/垂直越权、注入、敏感明文、改价 全过 | TC-SEC 组 + 手工复核 |
| 合规 | 隐私政策可访问、权限文案一致、IRR ≤24%（当前 2400bp 定价会算到 2681bp） | 人工核对 + 试算抽查 |

测试报告模板（每次提测一份，存 `docs/reports/`）：

```
测试报告 | v2.4.0 | 2026-11-08
一、结论：是否达门禁（逐项 是/否 + 阻塞项）
二、范围：40 条 / 执行 40 / 通过 xx / 通过率 xx%
三、缺陷：P0 0；P1 x（关闭 x / 豁免 x）；P2/P3 存量
四、兼容与性能：机型 x 台、P95 实测 xx ms
五、遗留风险：描述 + 影响 + 规避 + 责任人
```

## 第 2 章 上线发布方案（上线发布师）

### 2.1 发布前置与版本规范

| 项 | 规则 | 当前值 |
| --- | --- | --- |
| 版本号 | `主.次.修订+build`，破坏性变更升主版 | `2.4.0+24`（`pubspec.yaml`） |
| 制品唯一 | 生产包必须来自 CI 产物，禁止本地打包直传 | CI 仅有 APK 构建，缺签名与门禁，见 2.2 |
| 环境 | dev / test / staging / prod 四套，配置密钥隔离 | 当前仅本地 dev |
| 密钥 | 不进代码库，环境变量或密钥管理注入 | `JWT_SECRET`、`PII_SECRET` 有 dev 默认值，生产必须覆盖 |
| 回滚制品 | 至少保留上一稳定版本 | `/opt/ucash/releases/<version>` 按版本留目录 |

发布单必填：版本与 commit、变更内容、影响面、时间窗、责任人、回滚预案、检查清单结论、已知问题与客服口径。

### 2.2 CI/CD：GitHub Actions 全文（本机无法构建）

本机 Dart VM 派生进程报 `ERROR_PIPE_BUSY(231)`，`flutter build/analyze/test` 全部不可用（已排除版本与安全软件因素）。因此**构建与测试一律在 CI 完成**，本地只做 `dart format` 与 `dart pub get`。仓库现有 `build-apk.yml` 只构建未签名 APK，用下面的合并版替换（或删旧文件），避免两条流水线重复构建。

`.github/workflows/ucash-ci.yml`：

```yaml
name: ucash-ci
on:
  push: { branches: [main], tags: ['v*'] }
  pull_request:
jobs:
  server:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22, cache: npm, cache-dependency-path: apps/server/package-lock.json }
      - run: npm ci --prefix apps/server
      - run: npm --prefix apps/server run typecheck && npm --prefix apps/server run test
      - run: npm --prefix apps/server run seed -- --reset
      - name: e2e
        run: |
          npm --prefix apps/server start &
          for i in $(seq 1 30); do curl -sf http://localhost:4000/health && break; sleep 1; done
          npm --prefix apps/server run e2e
  android:
    runs-on: ubuntu-latest
    needs: server
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '17' }
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.47.9', channel: stable, cache: true }   # 与现有 build-apk.yml 一致
      - name: Analyze & test
        run: |
          cd apps/mobile_flutter
          flutter pub get && flutter analyze && flutter test
      - name: Inject signing
        if: startsWith(github.ref, 'refs/tags/v')
        run: |
          cd apps/mobile_flutter/android
          echo "${{ secrets.ANDROID_KEYSTORE_BASE64 }}" | base64 -d > app/ucash-release.jks
          printf 'storeFile=ucash-release.jks\nstorePassword=%s\nkeyAlias=%s\nkeyPassword=%s\n' \
            "${{ secrets.ANDROID_STORE_PASSWORD }}" "${{ secrets.ANDROID_KEY_ALIAS }}" "${{ secrets.ANDROID_KEY_PASSWORD }}" > key.properties
      - name: Build
        run: |
          cd apps/mobile_flutter
          flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols
          flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
      - uses: actions/upload-artifact@v4
        with:
          name: ucash-${{ github.ref_name }}
          path: |
            apps/mobile_flutter/build/app/outputs/flutter-apk/*.apk
            apps/mobile_flutter/build/app/outputs/bundle/release/*.aab
            apps/mobile_flutter/build/symbols
```

腾讯云 CODING 备选：构建计划选「自定义」，环境 Linux + JDK17，步骤为 `flutter pub get` → `flutter analyze` → `flutter test` → `flutter build appbundle --release`；keystore 的 base64 存「凭据管理」，产物推「制品库」，触发条件 `v*` tag。若 CI 也不可用，最后手段是本地以管理员身份临时关闭进程防护重试，成功后立即归档 keystore 与产物。

### 2.3 Android 签名、混淆与渠道包

当前 release 仍指向 debug 签名，**必须替换**（首版签名不可更换，否则后续无法覆盖升级）：

```kotlin
// android/app/build.gradle.kts
import java.util.Properties
import java.io.FileInputStream
val keystoreProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}
android {
    signingConfigs {
        create("release") {
            storeFile = file(keystoreProps["storeFile"] as String)
            storePassword = keystoreProps["storePassword"] as String
            keyAlias = keystoreProps["keyAlias"] as String
            keyPassword = keystoreProps["keyPassword"] as String
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // Dart 用 --obfuscate 混淆；R8 未验证 Flutter keep 规则前不要开 isMinifyEnabled
        }
    }
}
```

`android/key.properties`（加 `.gitignore`）：`storeFile=ucash-release.jks`、`storePassword=<store 口令>`、`keyAlias=ucash`、`keyPassword=<key 口令>`。

```bash
keytool -genkeypair -v -keystore apps/mobile_flutter/android/app/ucash-release.jks -alias ucash -keyalg RSA -keysize 2048 -validity 10000 -storetype PKCS12
cd apps/mobile_flutter
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols   # 直发/渠道
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols             # 商店
for ch in huawei xiaomi oppo vivo yingyongbao; do
  flutter build apk --release --split-per-abi --dart-define=CHANNEL=$ch --obfuscate --split-debug-info=build/symbols-$ch
done
```

三点必须注意：① `build/symbols` 必须归档，否则线上崩溃堆栈永久不可读；② 客户端硬编码联调地址（`api_client.dart` 的 `10.0.2.2:4000`/`localhost:4000`），上线前 `[待补]` 加 `String.fromEnvironment('API_BASE')` 并以 `--dart-define=API_BASE=https://api.<domain>` 注入，同时关闭 `usesCleartextTraffic`；③ 渠道号客户端未读取，`[待补]` 在注册时上报 `CHANNEL`，否则渠道包只是同包不同名。

### 2.4 服务端发布：PM2、Docker Compose、Nginx 与备份

**单实例红线**：`instances` 必须为 `1`。SQLite 单写、`node-cron` 每日 00:05 计提会重复执行、短信验证码存在进程内 `Map`、放款 `setTimeout` 队列也在进程内——多实例会直接产生重复计提与验证码失效。

PM2 `ecosystem.config.cjs`：

```js
module.exports = {
  apps: [{
    name: 'ucash-api',
    cwd: '/opt/ucash/current/apps/server',
    script: 'node_modules/.bin/tsx',
    args: 'src/index.ts',
    instances: 1,
    exec_mode: 'fork',
    max_memory_restart: '600M',
    env: { NODE_ENV: 'production', PORT: '4000', DB_PATH: '/data/ucash/ucash.db',
           JWT_SECRET: process.env.JWT_SECRET, PII_SECRET: process.env.PII_SECRET }
  }]
};
```

```bash
pm2 start ecosystem.config.cjs && pm2 save && pm2 startup
# 注意：`start` 走 tsx，而 tsx 在 devDependencies，`npm ci --omit=dev` 后不可用；生产应 `tsc` 编译到 dist 后以 node 启动，或把 tsx 提升为依赖（[待补]）
```

Docker Compose（环境一致、回滚即换镜像 tag）：

```yaml
# deploy/docker-compose.yml
services:
  api:
    image: registry.example.com/ucash-api:2.4.0
    restart: always
    environment: { NODE_ENV: production, PORT: "4000", DB_PATH: /data/ucash.db,
                   JWT_SECRET: "${JWT_SECRET}", PII_SECRET: "${PII_SECRET}" }
    volumes: ["ucash-data:/data"]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 3s
      retries: 2
  nginx:
    image: nginx:1.27-alpine
    restart: always
    ports: ["80:80", "443:443"]
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - ./certs:/etc/nginx/certs:ro
      - /opt/ucash/admin-dist:/usr/share/nginx/admin:ro
volumes:
  ucash-data:
```

```bash
docker compose -f deploy/docker-compose.yml up -d && docker compose -f deploy/docker-compose.yml ps   # api=healthy
```

镜像注意：`index.ts` 用 `path.join(__dirname,'..','..','admin','dist')` 托管后台，容器内需把 `apps/admin/dist` 放到 `/admin/dist`，或 `[待补]` 改读 `ADMIN_DIST`；且 `vite.config.ts` 必须加 `base: '/admin/'`，否则 `/admin` 页面能开、`/assets/*.js` 全 404（当前即此状态）。

Nginx 关键段：

```nginx
server { listen 80; server_name api.example.com; return 301 https://$host$request_uri; }
server {
  listen 443 ssl http2; server_name api.example.com;
  ssl_certificate /etc/nginx/certs/fullchain.pem; ssl_certificate_key /etc/nginx/certs/privkey.pem;
  ssl_protocols TLSv1.2 TLSv1.3; client_max_body_size 2m;
  gzip on; gzip_types application/json application/javascript text/css;
  location /api/auth/ { limit_req zone=auth burst=10 nodelay; proxy_pass http://api:4000; }
  location /api/      { proxy_pass http://api:4000; proxy_read_timeout 30s; }
  location = /health  { proxy_pass http://api:4000/health; access_log off; }
  location /admin/    { alias /usr/share/nginx/admin/; try_files $uri $uri/ /admin/index.html; }
}
# http 块：limit_req_zone $binary_remote_addr zone=auth:10m rate=20r/m;
```

证书用 acme.sh 自动续期并挂到期监控：`acme.sh --issue -d api.example.com --webroot /var/www/acme && acme.sh --install-cert ... --reloadcmd "nginx -s reload"`。

SQLite 备份（**WAL 下禁止直接 `cp ucash.db`**，会丢 `-wal` 未落盘数据）：

```bash
# /opt/ucash/deploy/backup.sh，每日 03:00 与 15:00
set -e; D=/data/ucash/ucash.db; B=/backup; mkdir -p "$B"
sqlite3 "$D" ".backup '$B/ucash-$(date +%F-%H).db'"     # 在线安全备份
sqlite3 "$D" "PRAGMA wal_checkpoint(TRUNCATE);"
find "$B" -name 'ucash-*.db' -mtime +7 -delete
[ "$(date +%d)" = "01" ] && cp "$B"/ucash-$(date +%F-%H).db "$B"/monthly-$(date +%Y%m).db
```

`crontab -e` 加 `0 3,15 * * * /opt/ucash/deploy/backup.sh >> /var/log/ucash/backup.log 2>&1`；每季度恢复演练一次（`sqlite3 /tmp/r.db ".restore '<备份>'"` 后拉起临时实例验证），目标 RTO ≤2h、RPO ≤12h（需 ≤5min 则改 5 分钟 `VACUUM INTO` 或迁 PostgreSQL）。

### 2.5 灰度发布与一键回滚

| 阶段 | 放量 | 观察窗 | 通过条件 |
| --- | --- | --- | --- |
| S1 | 5%（内部 + 演示账号白名单） | 30 分钟 | 错误率 <0.5%，放款、还款成功各 ≥1 笔 |
| S2 | 20% | 2 小时 | 错误率 <0.8%，P95 <800ms，无 P0 客诉 |
| S3 | 50% | 24 小时 | 放款失败率 <3%，还款失败率 <2%，逾期率日环比 <+20% |
| S4 | 100% | 72 小时 | 全部达标并出 72 小时观察报告 |

服务端按 Nginx 权重（5/95）或 uid 取模分流；App 用商店分阶段发布；后台与 H5 用目录切换秒级回退。

回滚触发（任一命中立即回滚，不讨论）：错误率 >1% 持续 5 分钟；放款失败率 >3%（剔除单卡 E1024 后仍超）；还款失败率 >2%；P95 >1s 持续 10 分钟；逾期率日环比 +30%；崩溃率 >0.5%；资金类 P0。

```bash
ls -1 /opt/ucash/releases                 # 确认上一稳定版，如 2.3.1
ln -sfn /opt/ucash/releases/2.3.1 /opt/ucash/current
pm2 restart ucash-api --update-env
curl -sf https://api.example.com/health && echo rollback-ok
```

Docker 回滚：镜像 tag 改回上一版本后 `docker compose up -d --no-deps api`。客户端无法物理回滚，故服务端接口须向后兼容 ≥2 个版本，破坏性字段走「先加后删」；新功能用 `settings` 表开关控制，回滚先关开关再换版本。

### 2.6 应用商店审核与合规

| 材料 | 说明 | 状态 |
| --- | --- | --- |
| 营业执照 | 经营范围含小贷/金融信息服务 | 需提供 |
| 放贷资质 | 小贷牌照，或持牌机构助贷协议 + 资金方证明 | 需提供 |
| ICP + APP 备案 | 域名备案与工信部 App 备案 | 需提供 |
| 软件著作权 | 与 App 名称一致的软著 | 需提供 |
| 等保测评 | 二级及以上备案与测评报告 | 需提供 |
| 隐私/授权文书 | 隐私政策、个人信息授权书、征信授权书、借款合同 | 有文案，需公网可访问链接 |

高频拒审与规避：① 类目选错 → 按实际业务选「金融-借贷」并交资质；② 资质主体不一致 → 补齐授权链；③ 利率费用不透明 → 借款页与合同双处明示 IRR 与全部费用，禁用“日息低至”；④ 权限过度 → 仅保留 `INTERNET`/`NETWORK_STATE`/`CAMERA`（当前已最小集，紧急联系人手填，勿回退读通讯录）；⑤ 无注销入口 → 已有 `/api/auth/close` 与设置页入口，在贷时禁止需在页面说明；⑥ 诱导借贷 → 禁用“秒批/必过/无视征信”；⑦ 隐私政策与实际收集不一致 → 逐项核对 SDK 与字段。

隐私自查（提审逐条打勾）：首启隐私弹窗、拒绝后不采集；权限申请前有说明；身份证/银行卡加密且界面脱敏；日志无明文手机号/身份证/卡号；第三方 SDK 清单与政策一致；未成年人拦截（22 周岁起）；催收频次每日 ≤3 次且 22:00–8:00 禁止。

## 第 3 章 运维保障方案（运维守护师）

### 3.1 部署架构

**单机拓扑（MVP 标准形态，当前代码直接可用）**：

```
  Flutter App ──HTTPS──┐
  运营后台(浏览器) ─────┤
                       ▼
                 ┌───────────────┐
                 │ Nginx :443    │  静态 /admin/、反代 /api、限流 /api/auth
                 └───────┬───────┘
                         │ 127.0.0.1:4000
                 ┌───────▼───────┐
                 │ Node 22        │  Express + JWT + RBAC + 审计
                 │ PM2 单实例     │  node-cron 00:05 逾期计提
                 └───┬───────┬───┘
                     │       │
        ┌────────────▼──┐  ┌─▼──────────────────┐
        │ SQLite (WAL)  │  │ 放款 setTimeout 队列 │
        │ /data/ucash.db│  │ 进程内（重启靠 sweep）│
        └───────┬───────┘  └────────────────────┘
                │ 03:00 / 15:00
        ┌───────▼────────┐        ┌──────────────────┐
        │ /backup 全量备份│───────>│ 对象存储（异地） │
        └────────────────┘        └──────────────────┘
  监控：/health 拨测 1min + 云监控(CPU/磁盘) + 日志采集 + 每日业务日报
```

**多实例拓扑（改造后可用，当前不可直接横向扩展）**：

```
           ┌──────────────┐
   LB/CDN ─┤ Nginx ×2     │ 会话无状态（JWT），可横向
           └───┬──────┬───┘
        ┌──────▼─┐  ┌─▼──────┐
        │ API ×2 │  │ API ×2 │  仅无状态读写
        └──┬─────┘  └───┬────┘
           │            │
     ┌─────▼────────────▼─────┐      ┌─────────────┐
     │ PostgreSQL（主从）      │      │ Redis        │
     │ 替代 SQLite            │      │ 验证码/幂等/限流│
     └─────────┬──────────────┘      └─────────────┘
               │
     ┌─────────▼──────────┐
     │ 独立 Worker ×1      │  cron、放款队列、对账（单实例）
     └────────────────────┘
```

改造门槛（任一触发即启动迁移）：写并发 >50 TPS 持续 10 分钟；DB >5GB 或单日增长 >200MB；需要 7×24 双活；单机月故障 >1 次。迁移清单：SQLite→PostgreSQL（`better-sqlite3` 换 `pg`，SQL 方言差异集中在 `julianday`/`substr`）、验证码 `Map`→Redis、`idempotency_keys` 真正接入、cron 与放款队列拆为独立 worker。

### 3.2 监控指标与告警阈值

三层齐备才算合格：可用性、性能、业务。**只有 CPU/磁盘的监控视为不合格**。

| 指标 | 阈值 | 持续 | 级别 | 动作 |
| --- | --- | --- | --- | --- |
| `/health` 拨测 | 连续 2 次失败 | 2 分钟 | P0 | 电话+短信，立即查进程与磁盘 |
| HTTP 5xx 占比 | >1% | 5 分钟 | P0 | 查 `pm2 logs`、DB 完整性、最近发布 |
| 接口 P95 | >1000ms | 10 分钟 | P1 | 查慢查询、DB 体积、WAL 大小 |
| 放款失败率 | >3%（剔除单卡 E1024） | 30 分钟 | P0 | 暂停下单开关，查渠道与银行卡状态 |
| 还款失败率 | >2% | 30 分钟 | P1 | 查 `repayments.status`、卡状态、余额扣款通道 |
| 逾期率日环比 | +30% | 日 | P1 | 查 cron 是否重复计提、系统日期 |
| cron 执行 | 00:10 无 `[cron] overdue scan` 日志 | 日 | P1 | 手动 `POST /api/internal/overdue-scan` 补跑 |
| DB 文件大小 | >2GB 或日增 >200MB | 日 | P2 | 归档历史、评估迁 PG |
| WAL 文件 | >500MB | 1 小时 | P2 | `PRAGMA wal_checkpoint(TRUNCATE)` |
| 磁盘使用率 | >85% | 10 分钟 | P1 | 清日志/备份、扩盘（先删 7 天前备份） |
| JWT 1002 占比 | >5% 或 5 分钟内突增 3 倍 | 5 分钟 | P1 | 查密钥是否被轮换、客户端版本 |
| 管理员登录失败 | >10 次/5 分钟 | 5 分钟 | P1 | 临时封 IP，核查是否爆破 |
| HTTPS 证书 | 到期前 30/7/1 天 | 日 | P2/P1 | 续期并 reload |
| 备份任务 | 未生成当日文件 | 日 | P1 | 手动执行 `backup.sh`，查磁盘与锁 |

告警纪律：每条告警必须写清“服务/指标/当前值/建议动作”；同类聚合收敛，DB 故障时抑制其下游接口告警；每月复盘，误报率 >30% 的规则必须调优。P0 = 电话+群呼 15 分钟响应；P1 = 工作时间 30 分钟、夜间次晨；P2 = 日报汇总。

### 3.3 日志、审计与检索

现状：`index.ts` 仅 `console.log` 打印 `method + path`，无结构化、无 trace_id、无耗时。`[待补]` 最小改造（约 40 行）：中间件生成 `x-request-id` 并回写响应头，日志输出单行 JSON：

```json
{"ts":"2026-11-08T10:00:00.000Z","level":"info","svc":"ucash-api","trace":"a1b2c3","uid":12,"method":"POST","path":"/api/repayments","status":200,"code":0,"ms":38}
```

Nginx 侧 `log_format` 增加 `$request_id $request_time $upstream_response_time $status`，与应用日志用同一 `trace` 关联。三类日志分工：访问日志（网关）、应用日志（业务事件，INFO/WARN/ERROR）、审计日志（`audit_logs` 表：登录、审批、调额、罚息减免、放款、导出）。

```bash
# 检索示例（结构化后可 jq 精确过滤）
pm2 logs ucash-api --lines 500 | grep '"level":"error"'
grep '"trace":"a1b2c3"' /var/log/ucash/out.log
sqlite3 /data/ucash/ucash.db "SELECT created_at,actor_type,actor_id,action,target_type,target_id FROM audit_logs WHERE created_at>date('now','-1 day') ORDER BY id DESC LIMIT 50;"
sqlite3 /data/ucash/ucash.db "SELECT action,COUNT(*) FROM audit_logs GROUP BY action ORDER BY 2 DESC;"
```

保留策略：审计日志**≥5 年**（借贷合同与交易记录按监管要求，且不可篡改，建议按月导出只读归档）；应用日志热存 14 天、归档 90 天；访问日志 30 天。日志脱敏红线：禁止输出完整手机号、身份证、银行卡号、密码、JWT 原文。用 logrotate 防写满磁盘：

```
/var/log/ucash/*.log { daily rotate 14 compress delaycompress missingok notifempty copytruncate }
```

### 3.4 应急预案（发现 → 定位 → 处置 → 复盘）

**A. 放款通道故障（E1024 批量）**
- 发现：放款失败率 >3%；`/api/messages` 中“放款失败”激增；后台待处理增长。
- 定位：`sqlite3 /data/ucash/ucash.db "SELECT fail_code,COUNT(*) FROM loans WHERE created_at>=date('now','-1 day') GROUP BY 1;"`；核对 `bank_cards.status` 与卡号尾号 0000 规则。
- 处置：立即关下单开关（`settings` 键 `loan_enabled=false`，`[待补]` 在 `createLoan` 读取）；已失败借据走换卡重试 `POST /api/loans/:id/retry`；批量站内信告知换卡；必要时后台人工放款。
- 复盘：48 小时内出报告，补通道健康探测与自动熔断，单卡失败与通道失败分开告警。

**B. 数据库损坏**
- 发现：接口大面积 9001；`PRAGMA integrity_check` 非 `ok`；进程反复重启。
- 定位：`sqlite3 /data/ucash/ucash.db "PRAGMA integrity_check;"`；`dmesg | grep -i "i/o error"` 判断是否磁盘故障。
- 处置：停服并保留现场（复制 `.db/.db-wal/.db-shm`）；用最近 `.backup` 恢复到临时库；跑第 1 章 10 条勾稽 SQL；确认后切换 `DB_PATH` 并重启；补录备份点之后的流水需人工对账。
- 复盘：检查 WAL 与磁盘健康、备份频率是否匹配 RPO，季度恢复演练是否真做过。

**C. 服务雪崩 / 内存打满**
- 发现：P95 陡增、5xx >1%、PM2 频繁 `restart`、`max_memory_restart` 触发。
- 定位：`pm2 describe ucash-api` 看重启次数与内存；慢查询 `SELECT` 全表扫描（`loan_schedules` 无索引条件）；WAL 膨胀。
- 处置：Nginx 限流 `/api`（`limit_req`）；重启单实例；降级非核心（优惠券、邀请、站内信写库）；清理 WAL；仍不恢复则扩内存或迁 PG。
- 复盘：补索引、加查询超时与分页上限，压测复现拐点并发。

**D. 数据泄露 / 越权**
- 发现：审计日志异常批量查询、异常 IP 导出、外部报告；`audit_logs` 出现非工作时段高频操作。
- 定位：按 `actor_id`、`ip` 拉全量行为；比对响应是否含未脱敏字段；确认泄露范围（用户量、字段）。
- 处置：立即轮换 `JWT_SECRET`（所有 token 失效）与 `PII_SECRET`（注意：换 PII 密钥会导致历史密文不可解，必须先导出明文再迁移）；封禁 IP/账号；断开外网；按《个人信息保护法》评估是否需 72 小时内报告监管与告知用户。
- 复盘：补字段级访问审计、最小权限复核（super 账号数量）、导出加二次确认与水印。

**E. 逾期批量异常（cron 重复计提/日期错乱）**
- 发现：逾期户数或罚息金额短时暴涨；日报 `overdueRate` 跳变。
- 定位：`SELECT COUNT(*) FROM loan_schedules WHERE status='overdue' AND penalty_cents>0;` 与昨日对比；检查服务器时区与 `date`；确认 cron 是否被多实例重复执行。
- 处置：停 cron（`pm2 stop` 或注释调度后重启）；按 `PENALTY_DAILY_BP=5` 公式全量重算 `penalty_cents`（重算前先备份）；对多收部分做罚息减免并留审计；通知客服口径。
- 复盘：给计提加“当日幂等”（`settings` 记 `last_overdue_run`），并加“单日计提金额环比 >50% 即告警”。

### 3.5 容量与成本估算

假设：注册→放款转化 3%、客单 3,000 元、平均在贷 6 期、日活 = 借款人 20%。

| 项 | 1 万借款人 | 10 万借款人 |
| --- | --- | --- |
| 日活 / 日借据 | 2,000 / 约 300 笔 | 20,000 / 约 3,000 笔 |
| 峰值 QPS（读+写） | 20–40 | 200–400 |
| DB 体积（首年） | 1–3GB | 15–35GB |
| 实例 | 2C4G 单机 + 100GB SSD | 4C8G×2 + PG 4C8G 主从 + Redis 2G |
| 带宽 | 5Mbps | 50Mbps + CDN |
| 月成本量级（含备份/监控） | ¥400–1,000 | ¥4,000–10,000 |

成本护栏：云账单达预算 80% 提醒、100% 复盘；短信/对象存储/CDN 单独设用量告警；测试与预发环境非工作时段关机（可省 60%）；每月盘点闲置 IP、快照、过期证书与废弃套餐。SLA 目标：MVP 期承诺 99.5%（月停机 ≤3.6h），资金链路按 99.9% 建设但对外只承诺 99.5%；统计口径为用户侧错误率（非进程存活），用第三方拨测数据度量。

### 3.6 值班、演练与备份目标

| 周期 | 动作 | 产出 |
| --- | --- | --- |
| 每日 | 核验备份文件已生成；检查告警静默与 cron 日志 | 值班日志 |
| 每周 | 补丁与漏洞通告核对；异常登录/爆破日志抽查；审计日志抽检 | 周检记录 |
| 每月 | 资源与账单盘点；告警规则调优（误报率 >30% 必改）；证书/域名到期核对 | 月度运维报告 |
| 每季度 | 备份恢复演练（真跑一次 restore）；P0 预案桌面推演 | 演练报告（含实际 RTO/RPO） |
| 每半年 | 权限盘点（离职/转岗账号回收）；`JWT_SECRET` 轮换；`PII_SECRET` 轮换方案演练 | 权限清单与轮换记录 |

值班机制：明确第一响应人与备份人姓名/电话，P0 15 分钟内认领；P0 预案打印贴在值班位；无认领则 10 分钟后升级至负责人。

| 对象 | 策略 | 保留 | 目标 |
| --- | --- | --- | --- |
| 业务库 | 每日 03:00/15:00 `sqlite3 .backup` + 每月归档 | 7 天热备、12 个月月备 | RPO ≤12h |
| 备份副本 | 同步至对象存储另一地域 | 与主备一致 | 防单点删除 |
| 配置与密钥 | 密钥管理 + 变更留版本 | 每次变更 | 可回滚 |
| 代码与制品 | Git tag + CI 产物 + symbols | 永久 | 可重建任意版本 |

演练硬要求：**没验证过可恢复的备份等于没有备份**。每季度必须从备份实际拉起一次实例并跑通 e2e 冒烟，记录真实 RTO（目标 ≤2h）与丢失数据窗口；演练失败视为 P1 事件，两周内整改复演。

## 第 4 章 运营增长方案（增长运营师）

### 4.1 冷启动路径

**种子用户画像**：22–45 岁、有稳定收入来源（月收入 5,000–20,000 元）、非在校学生、有 3–12 个月短期周转需求的城市蓝领与小微经营者。合规红线：不得向未成年人、在校学生、无还款能力人群营销。

| 路径 | 具体动作 | 频次/预算 | 预期 |
| --- | --- | --- | --- |
| ASO（商店搜索） | 标题“UCash-小额借款·额度灵活”，副标题含“短期周转/随借随还”；关键词覆盖“小额借款、现金周转、短期借款、额度灵活”，避开“秒批/必过/无视征信”等违规词 | 每月复盘一次关键词（曝光/点击/下载转化） | 自然量占新增 30% |
| 内容种草 | 财经/生活类账号做“理性借贷与信用管理”科普，落地页导向额度测算，不做收益承诺 | 每周 3 篇 + 2 个素人置换，≤3,000 元/月 | 月新增 300–500 |
| 老客裂变 | 邀请有礼：被邀请人完成**首借放款**后双方得奖励（非注册即奖，防刷） | 常驻，单客奖励 ≤50 元 | K 因子 ≥0.15 |
| 商店首发 | 华为/小米/OPPO/vivo/应用宝申请新品首发专题 | 上线首月一次 | 首月下载 +30% |
| 私域承接 | 客服企微承接咨询，输出还款提醒与信用小贴士 | 每日 | 首借转化 +5pp |

**禁用的违规获客手段**（触碰即下线整改，不做灰度）：虚假/夸大宣传（“秒批”“必过”“零门槛”）、AB 贷与包装资料、砍头息与会员费变相收费、爬取通讯录/通话记录、向学生或未成年人营销、诱导多头借贷、伪造资质或冒用持牌机构名义、马甲包与刷量刷评、短信/电话轰炸式营销、暴力与骚扰催收。

### 4.2 漏斗基线、口径与目标

当前无真实流量（仅 3 个演示账号），下表“当前”为口径验证值，不作为业务基线；上线后首周以真实数据替换。

| 环节 | 口径（可 SQL 复算） | 当前 | 首月目标 |
| --- | --- | --- | --- |
| 注册 | `users` 去重手机号 | 3（演示） | 3,000 |
| 实名 | `kyc_records.status='passed'` 去重用户 | 3 | 注册→实名 ≥65% |
| 授信提交 | `credit_applications` 去重用户 | 3 | 实名→提交 ≥85% |
| 授信通过 | `credit_applications.status='approved'` 去重用户 | 3 | 提交→通过 50%–60% |
| 首借放款 | `loans.disbursed_at IS NOT NULL` 去重用户 | 2 | 通过→首借 ≥40% |
| 放款成功 | `loans.status IN ('active','overdue','settled')` / 下单数 | — | ≥95% |
| 复借（30 日） | 同一用户 `disbursed_at` 第二次在首借后 30 天内 | 0 | ≥20% |

```sql
-- 漏斗一键复算（放进日报脚本，每日 08:00 跑）
WITH rn AS (SELECT DISTINCT user_id FROM kyc_records WHERE status='passed'),
ap AS (SELECT user_id, MAX(status='approved') ok FROM credit_applications GROUP BY user_id),
ln AS (SELECT user_id, MIN(disbursed_at) first_at, COUNT(*) n FROM loans WHERE disbursed_at IS NOT NULL GROUP BY user_id)
SELECT (SELECT COUNT(*) FROM users) 注册,
       (SELECT COUNT(*) FROM rn) 实名,
       (SELECT COUNT(*) FROM ap) 授信提交,
       (SELECT COUNT(*) FROM ap WHERE ok=1) 授信通过,
       (SELECT COUNT(*) FROM ln) 首借放款,
       (SELECT COUNT(*) FROM ln WHERE n>=2) 复借;
```

诊断口诀：注册→实名低 = 认证引导与隐私顾虑问题；实名→提交低 = 额度预期与流程长度问题；提交→通过低 = 风控过严或流量质量差；通过→首借低 = 定价/额度/信任问题；首借→复借低 = 额度不成长与还款体验问题。**先修漏斗再投钱**，留存曲线未走平前放大投放等于漏桶注水。

### 4.3 留存与复借策略

**额度成长（已有能力）**：公积金认证 +5,000 元、运营商 +3,000 元、信用卡账单 +3,000 元，评分系数最高 1.4，封顶 5 万（`services/risk.ts:73-95`）。运营话术落在“认证即提额”，当前 `refreshLimit()` 已实现“只升不降”。

**额度成长（待补）**：`[待补]` 还款行为提额——连续 2 期按时还款 +10% 额度、结清后 +15%，需在 `repay()` 结清分支调用提额并写 `audit_logs`；否则用户没有“越借越额度高”的正反馈，复借只能靠降价。

**优惠券节奏**（现有券：`NEW20` 满 1000 减 20、`RATE01` 降息 100bp，注册自动发放）：

| 时点 | 券 | 目的 |
| --- | --- | --- |
| 注册 | `NEW20` + `RATE01` | 首借转化 |
| 首借结清 | 复借券（满 2000 减 30，`[待补]` 新增券种） | 复借 |
| 逾期前 3 天 | 不发票，只发还款提醒 | 防逾期 |
| 沉睡 30 天 | 召回券（降息 50bp，7 天有效） | 召回 |

单用户每月发券 ≤2 张，券成本控制在放款金额的 0.5% 以内；所有券必须设门槛与有效期，禁止无门槛现金券（易被薅）。

**触达频次上限（硬约束）**：事务性（放款到账、还款成功、逾期提醒）可即时发；营销类 Push/短信每日 ≤1 条、每周 ≤3 条；22:00–8:00 不发营销；催收每日 ≤3 次且不得在 22:00–8:00 联系；每条触达提供退订入口（≤2 步）。还款提醒节奏：T-3 站内信、T-1 Push、当日短信、逾期 D+1/D+3/D+7 各一次人工外呼。

### 4.4 数据看板指标定义

**后台已有（`/api/admin/dashboard`）**：`today.newUsers`、`today.creditApplications`、`today.loanCount`、`today.loanAmountCents`、`today.repayCount`、`today.repayAmountCents`；`portfolio.totalUsers`、`balanceCents`、`inLoanPrincipalCents`、`overdueCount`、`overdueAmountCents`、`overdueRate`、`creditApprovalRate`、`settleRate`；`todo.pendingCredit`、`todo.pendingLoan`；`trend[7]`。

**需补字段与表**（SQLite `ADD COLUMN` 安全，符合“先加后删”）：

```sql
ALTER TABLE user_profiles ADD COLUMN realname_at TEXT;
ALTER TABLE user_profiles ADD COLUMN face_at TEXT;
ALTER TABLE user_profiles ADD COLUMN contacts_at TEXT;
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER, name TEXT NOT NULL, channel TEXT, props TEXT, created_at TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS idx_events_name ON events(name, created_at);
```

| 指标 | 定义 | 数据来源 | 状态 |
| --- | --- | --- | --- |
| 实名转化率 | 实名通过用户 / 注册用户 | `user_profiles.realname_at` | 需补时间戳 |
| 授信通过率 | 通过用户 / 提交用户 | `credit_applications` | 已有 |
| 首借率 | 首借放款用户 / 授信通过用户 | `loans.disbursed_at` | 可算 |
| 复借率 | 30 日内二次放款用户 / 首借用户 | `loans` | 可算 |
| 逾期率 | 逾期应还 / 在贷余额 | 工作台口径 | 已有（分母需统一为在贷余额） |
| 放款成功率 | 成功放款 / 下单 | `loans.status` | 可算 |
| 券核销率 | 已用券 / 已发券 | `user_coupons` | 可算 |
| 邀请转化 | 被邀请人首借 / 邀请注册 | `invitations` | 需补发放逻辑 |
| CAC | 渠道花费 / 该渠道首借用户 | 需接渠道归因 | 需补 |
| 留存 D1/D7/D30 | 回访用户（`last_login_at`） / 新增 | `users.last_login_at` | 近似可用 |

`[待补]` 邀请奖励闭环：`invitations.reward_cents` 目前从未发放，状态停在 `registered`（`auth.ts:90-92` 只建记录）。需在放款成功回调中把 `status` 推进到 `borrowed` 并发放奖励（`reward_status='granted'` + 站内信 + 券），否则裂变只有邀请量没有兑现，口碑会反噬。

### 4.5 首月运营节奏（Week 1–4）

| 周 | 关键动作 | 验收指标 |
| --- | --- | --- |
| W1 基建 | 埋点补齐（实名/授信/首借时间戳、`events` 表）；后台看板加漏斗卡片；客服话术与催收合规培训；内部与演示账号全链路走查 | 漏斗 6 个环节数据可查；e2e 25/25；客服 100% 通过合规测验 |
| W2 首发 | 商店首发申请与素材上线；种子 100 人一对一邀请；ASO 关键词首版；隐私政策与资质页面上线 | 商店过审；新增 ≥300；注册→实名 ≥55% |
| W3 转化 | 优化实名引导（隐私说明前置）；首借券弹窗；人工审批 SLA 收紧至 2 小时；还款提醒上线 | 实名→提交 ≥80%；授信通过率 50%–60%；首借 ≥35% |
| W4 复借与复盘 | 结清发复借券；额度成长话术；渠道效果复盘，决定是否加投 | 30 日复借 ≥15%；放款成功率 ≥95%；逾期率 <3%；出首月增长复盘报告 |

复盘纪律：每周固定输出“北极星指标 + AARRR 五段数据 + 本周实验结论 + 下周 Top3 动作”，只罗列数字不给结论的周报视为无效；每个实验先写假设（“若改 X，则 Y 提升 Z%，因为 …”），单变量、有样本量、有判定标准，失败实验也入台账。

---

### 4.6 流失定义与分层召回

**流失定义**：连续 30 天未登录且无在贷借据（有在贷用户不进流失池，走还款服务流程）。口径写入数据字典，避免运营与数据两套说法。

| 分层 | 定义 | 召回重点 | 落地动作 |
| --- | --- | --- | --- |
| 新用户流失 | 注册 7 天内未完成实名 | 降低门槛与隐私顾虑 | 站内信 + Push：说明仅用于风控、3 步完成、认证即见额度 |
| 认证未授信 | 三认证完成 7 天未提交授信 | 额度预期 | 展示“预估额度区间”，一键提交 |
| 授信未首借 | 通过后 7 天未下单 | 定价与信任 | 首借降息券 + 合同与费率说明直达 |
| 结清未复借 | 结清后 30 天未再借 | 额度成长与习惯 | 提额结果通知 + 复借券 |
| 沉睡用户 | 60 天未登录 | 大额激励 + 新功能 | 召回券（7 天有效）+ 客服外呼（每人每季 ≤1 次） |

渠道优先级：Push（已装机）→ 短信（有手机号）→ 站内信 → 客服企微。话术公式＝身份 + 具体钩子 + 低门槛行动，禁止“好久不见快回来”式空话：

- 授信未首借：“您的额度 8,000 元已生效，本周借款可享年化降 1%，点此查看还款计划。”
- 结清未复借：“您已按时结清 1 笔，额度已提升至 12,000 元，复借免审核。”
- 沉睡召回：“额度保留至 12 月 31 日，回归可领 7 天降息券，点此查看。”

召回成本核算：单客召回成本（券 + 短信 + 外呼分摊）必须 ≤ 单客毛利 × 20%。单客毛利 ≈ 放款额 × 综合年化 × 平均期限/12 − 资金成本 − 风险成本；按客单 3,000 元、年化 18%、期限 6 个月、资金成本 8%、风险成本 3% 估算，单客毛利约 170 元，则召回成本上限约 34 元。召回后 7 日二次流失率纳入监控，目标 ≤40%；超过说明钩子与承接页不匹配。

### 4.7 首个增长实验与周报模板

实验 1（W2 上线）：假设“实名页前置隐私用途说明与预估额度，实名转化提升 8pp”。单变量、A/B 各 500 名新注册用户或运行 14 天；判定标准：转化率提升 ≥5pp 且 p<0.05 则全量，无差异则记录关闭，显著下降立即回滚。实验期间不得同时改授信流程，否则归因失效。

实验 2（W3）：假设“首借页展示‘按期还款可提额’提示，首借转化提升 5pp”，判定同上。

周报模板（每周一 10:00 出，口径与 4.2 一致）：

```
增长周报 | 第 N 周 | {起止日期}
一、北极星：首借放款用户数 {n}（环比 {x}%）｜目标 {y}
二、AARRR：新增 {a}（渠道占比…）｜实名 {b}%｜授信通过 {c}%｜首借 {d}%｜复借 {e}%
三、漏斗瓶颈：本周最弱环节 {环节}，原因假设 {…}
四、实验结论：{实验名}（假设/结果/决策）
五、下周 Top3：{动作 + 负责人 + 预期指标影响}
```

纪律：只罗列数据不给结论的周报视为无效；每个实验先写假设与判定标准，失败实验同样入台账，避免重复踩坑。

### 4.8 用户生命周期分层运营

| 阶段 | 定义 | 运营目标 | 关键动作 |
| --- | --- | --- | --- |
| 新用户 | 注册 ≤7 天 | 完成实名与授信 | 新手任务、隐私说明前置、预估额度展示 |
| 成长期 | 已授信未首借或首借未结清 | 完成首借并按时还款 | 首借券、还款日历、T-3 提醒 |
| 成熟期 | 已结清 ≥1 笔 | 复借与提额 | 结清即提额、复借券、认证提额提示 |
| 衰退期 | 频次连续 2 个月下降 | 止跌 | 额度到期提醒、降息券、客服回访 |
| 流失期 | 超 30 天未登录且无在贷 | 召回或自然淘汰 | 分层召回（见 4.6）、沉默用户清理 |

纪律：每层有独立指标与动作；用户从上层滑向下层时必须触发对应动作，而不是等流失定义期过后直接进召回池。

## 交付自检清单

**文档与代码一致性**

- [ ] `docs/05-delivery-playbook.md` 四章齐全，每章 150–250 行，命令与阈值可执行可判定
- [ ] 修正 README/ADR 与实测的表数差异（文档写 20 张，实测 18 张），统一为 18 张并说明口径
- [ ] 补齐 `apps/server/src/lib/money.test.ts`，`npm run test` 通过且 `money.ts` 覆盖 100%
- [ ] 补齐 `apps/server/src/scripts/audit-check.ts`，10 条勾稽 SQL 零差异
- [ ] 补齐 `apps/server/src/scripts/e2e-negative.ts`，40 条负向断言全过
- [ ] 补齐 `apps/mobile_flutter/test/` 用例（至少格式化与 6 个核心页面）

**必须修复的已知缺陷**

- [ ] 还款幂等：`idempotency_keys` 接入 `POST /api/repayments`，双击不再连扣两期
- [ ] 结清流水利息口径：只记实收利息，未来期利息落 `waived_interest_cents`（当前实测差 41.98 元）
- [ ] 定价上限从 2400bp 降至 2160bp（IRR≤24%），后台人工定价同步收紧
- [ ] 后台登录失败锁定：连续 5 次失败锁定 15 分钟并告警
- [ ] 后台 `vite.config.ts` 增加 `base: '/admin/'`，修复 `/admin` 下静态资源 404
- [ ] Android release 签名换成正式 keystore，debug 签名不得上架
- [ ] 客户端 API 地址改为 `--dart-define=API_BASE` 注入，生产关闭明文流量
- [ ] 渠道号 `CHANNEL` 上报，打通渠道归因
- [ ] 邀请奖励闭环（`reward_cents` 真正发放，状态推进到 `rewarded`）

**上线门禁**

- [ ] 质量门禁全过：P0=0、核心链路 100%、账务零差异、P95 <500ms（读）
- [ ] CI 流水线跑通：typecheck、单测、seed、e2e、`flutter analyze/test/build` 全绿
- [ ] 生产密钥已注入（`JWT_SECRET`、`PII_SECRET` 非默认值），`.env` 未入库
- [ ] Nginx HTTPS 生效、证书自动续期与到期告警已配
- [ ] 备份脚本 + cron 生效，且完成一次真实恢复演练（记录 RTO/RPO）
- [ ] 监控告警接入（拨测、5xx、P95、放款失败率、cron、磁盘、证书）
- [ ] 灰度与回滚步骤已走查，上一版本制品可用，回滚命令有执行人
- [ ] 应用商店资质齐备（执照、牌照/助贷协议、ICP+APP 备案、软著、等保二级）
- [ ] 隐私合规自查逐项打勾，权限清单与隐私政策一致
- [ ] `systemd`/PM2 单实例约束已知会全员（禁止开 cluster，否则 cron 重复计提）

**运营准备**

- [ ] 漏斗 6 环节数据可查，日报脚本每日 08:00 推送
- [ ] 首月券与触达节奏已配置，频次上限写入客服与运营 SOP
- [ ] 禁用获客手段清单已宣达至市场与渠道合作方
- [ ] 首月复盘模板与实验台账建立

[测试保障方案][上线发布方案][运维保障方案][运营增长方案]
