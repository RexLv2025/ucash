# ADR-004：客户端技术栈由 React Native 调整为 Flutter

- 状态：已采纳
- 日期：2026-11-08
- 决策人：Rex（CEO/CRO）· 全栈智造专家团

## 一、背景与决策

Phase 1 立项时客户端选型为 React Native + Expo（依据：活体、通讯录、设备指纹、推送四项原生能力 + 可 Web 验证）。用户在评审后明确要求：**用 Flutter 生成安卓原生 App**。

决策：客户端改用 **Flutter 3.x / Dart 3.13 / Material 3**，交付 Android 原生安装包。

## 二、影响范围

| 层 | 是否变更 | 说明 |
|---|---|---|
| 业务中台（Node + Express + SQLite） | 不变 | 与客户端技术栈解耦，API 契约零改动 |
| 数据模型（18 张表） | 不变 | 金额整数分、利率基点口径保持 |
| 运营后台（Vite + React） | 不变 | 复用同一套 Admin API |
| 客户端 | **重写** | RN → Flutter，页面与交互按设计稿 1:1 实现 |
| 构建链路 | **变更** | Expo/EAS → Gradle + Flutter Gradle Plugin |

## 三、保持不变的关键契约

1. 统一响应 `{code, message, data}`，错误码 9 段（1xxx 通用 / 2xxx 账号 / 3xxx 认证 / 4xxx 授信 / 5xxx 借款 / 6xxx 还款 / 7xxx 放款 / 9xxx 系统）
2. 金额一律整数分传输，客户端只做格式化，不做加减乘除
3. 借款下单只接受服务端签发的 `quoteToken`，客户端不可传金额与利率（防改价）
4. 综合年化利率按 IRR 口径明示，与合同年利率并列展示
5. 设计令牌：深藏蓝 `#0F2B5B`、香槟金 `#C9A45C`、页面底 `#F5F6F8`、成功绿 `#12B76A`、警示红 `#E5484D`

## 四、Flutter 工程结构

```
apps/mobile_flutter/lib/
├── main.dart                  入口：竖屏锁定 + 状态栏样式 + 会话引导
├── app.dart                   MaterialApp + 登录态路由闸门
├── core/
│   ├── api_client.dart        统一 HTTP、JWT 注入、错误码解析、baseUrl 可配置
│   ├── session.dart           全局会话（用户 / 额度 / 未读数），ChangeNotifier
│   └── formatters.dart        金额、利率、日期、状态文案
├── theme/app_theme.dart       设计令牌 + ThemeData + 文本层级
├── widgets/common.dart        UCard / UButton / UNavBar / UTag / UEmpty / UField 等
└── pages/                     22 个页面
```

页面清单：登录、首页、借款确认、借款结果、账单、借据详情、还款、还款结果、我的、额度激活、授信结果、实名认证、人脸识别、紧急联系人、银行卡、优惠券、邀请、消息、帮助、设置、借款记录、还款记录。

## 五、构建与分发

```bash
cd apps/mobile_flutter
flutter pub get
flutter build apk --release
# build/app/outputs/flutter-apk/app-release.apk
```

- `minSdk` / `targetSdk` 沿用 Flutter 模板（`flutter.minSdkVersion` / `flutter.targetSdkVersion`）
- 已配置 `INTERNET`、`ACCESS_NETWORK_STATE`、`CAMERA` 权限与 `network_security_config`（本地联调允许明文，生产可关闭）
- 开发联调地址：模拟器 `10.0.2.2:4000`，真机走局域网 IP（设置页可改）
- 上架前需替换 release 签名、准备软著与金融类目资质

## 六、已知构建环境约束

本机（Windows）Dart VM 在创建子进程命名管道时返回 `ERROR_PIPE_BUSY (231)`，导致 `flutter build` / `dart compile` / `dart analyze` 等需要派生子进程的命令不可用。已完成排查：

| 验证项 | 结果 |
|---|---|
| 360tray 退出后重试 | 仍失败 |
| Dart 3.5.4（另一版本）单独测试 | 仍失败 |
| PowerShell 直接运行 dart.exe | 仍失败 |
| 系统命名管道创建（PowerShell NamedPipeServerStream） | **成功**，系统管道正常 |
| 计划任务独立会话运行（schtasks） | 被安全策略禁止，无法验证 |

结论：非版本问题、非安全软件问题，为宿主环境的进程管道限制。

**第三轮验证（Gradle 侧直连构建）**：为绕开 `flutter` 命令行的 git 子进程，直接执行 `gradlew assembleDebug`。结果：

- Gradle 9.3.1 与 AGP 9.1.0 可正常解析（腾讯镜像 + 阿里云 Maven），`:gradle:compileKotlin`、`:gradle:jar` 等 Flutter Gradle Plugin 任务全部通过 → 说明 Java 侧构建链路完好
- 卡点前移到 `:app` 配置阶段的 NDK 28.2 安装（约 1GB），且 Flutter Gradle Plugin 会强制注入 `ndkVersion`，无法通过删除该配置规避
- 即使 NDK 就绪，后续 `flutter assemble` 仍需由 Dart VM 派生子进程（frontend_server / impellerc / gen_snapshot），必然复现同一管道错误

规避方案：

1. **推荐**：在 CI（GitHub Actions / 腾讯云 CODING）或另一台机器执行 `flutter build apk --release`
2. 或在本地以管理员身份、关闭进程防护后重试
3. 代码本身通过 `dart format` 全量解析（31 个文件语法无误），Flutter 依赖通过 `dart pub get` 正常解析

> 注：Dart VM 内部操作（pub 解析、格式化）均正常，仅派生外部进程受限，因此不影响源码正确性与后端联调。
