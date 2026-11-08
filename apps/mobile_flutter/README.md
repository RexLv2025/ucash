# UCash Flutter 客户端（Android）

线上小额现金贷 App，Flutter 3.x / Dart 3.13 / Material 3，对接 `apps/server` 业务中台。

## 本地运行

```bash
flutter pub get
flutter run                     # 连接真机或模拟器
flutter build apk --release     # 产物 build/app/outputs/flutter-apk/
```

服务端地址默认按运行环境自动选择：

| 环境 | 默认地址 |
|---|---|
| Android 模拟器 | `http://10.0.2.2:4000` |
| Flutter Web | `http://localhost:4000` |
| 真机 | 需在 App 内「设置 → 开发者选项」改为电脑局域网 IP |

也可在构建时注入：`flutter build apk --dart-define=API_BASE=https://api.example.com`

## 目录结构

```
lib/
├── main.dart              入口：竖屏锁定、状态栏、会话引导
├── app.dart               MaterialApp + 登录态路由闸门
├── core/                  api_client（JWT/错误码/baseUrl）、session、formatters
├── theme/app_theme.dart   设计令牌（深藏蓝 #0F2B5B + 香槟金 #C9A45C）
├── widgets/common.dart    UCard / UButton / UNavBar / UField 等通用组件
└── pages/                 22 个业务页面
```

## 页面清单

登录 · 首页 · 借款确认 · 借款结果 · 账单 · 借据详情 · 还款 · 还款结果 · 我的 ·
额度激活 · 授信结果 · 实名认证 · 人脸识别 · 紧急联系人 · 银行卡 · 优惠券 ·
邀请有礼 · 消息中心 · 帮助与客服 · 设置 · 借款记录 · 还款记录

## 与后端的契约

- 统一响应 `{code, message, data}`，`code !== 0` 抛 `ApiException`，`1002` 视为登录失效
- 金额一律整数分，客户端只做格式化，不做加减乘除
- 借款下单只提交服务端签发的 `quoteToken`，客户端不传金额与利率
- 还款/借款请求携带 `Idempotency-Key`，防止重复提交

## CI 构建

仓库根目录 `.github/workflows/build-apk.yml` 在 push 或手动触发时构建 release APK，
产物上传为 Artifact `ucash-apk`。当前 release 使用 debug 签名，正式上架前需替换签名配置。
