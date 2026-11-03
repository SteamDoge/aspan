# ASpan

离线的时间与资源管理应用。通过独立规则管理订阅缴费、待办、生日、维护检查、次数卡和有效期，支持分类、合并、余额流水与本地备份。

本快照版本为 **0.0.5-rc.1+9**。支持 Android 与 Windows x64；其他平台尚未接入。系统通知、具体时刻、时区/DST 和自动记账尚未实现，提醒窗口目前仅在应用内显示。Android ARM64 尚未完成真机验收。软件处于候选阶段，请保留自己的导出备份。

## 架构与功能

- `crates/core`：纯 Rust 日期周期、规则、资源精度、幂等记账、纠错与完整性校验。
- `crates/runtime`：SQLite 事务、JSON C ABI、备份与 CLI；金额和资源使用整数最小单位。
- `apps/aspan`：Flutter 界面与平台文件选择，使用 `dart:ffi` 调用独立的 `aspan_bridge` 原生库。
- 四套明暗配色、三个固定入口、窄屏悬浮导航与宽屏侧栏；23 个内置场景模板。

预测不写账本，删除规则保留已发生的流水，纠错追加反向和替代流水；备份恢复先完整校验并保留恢复前检查点。本项目不读取其他应用的数据、账户或签名。

## 构建环境

本快照验证环境：Flutter **3.47.7**（Dart **3.13.5**）、Rust **1.98.1**、PowerShell **7**。使用已有的工具链即可，不需要将 SDK 放进本仓库。所有命令从仓库根目录运行，同一 Flutter 工程的检查和构建请串行执行。

- Windows：Windows 10/11 x64、Visual Studio 的“使用 C++ 的桌面开发”及 Windows SDK；Rust MSVC 工具链。
- Android：最低 Android 7.0/API 24；JDK 21、Android SDK、NDK **28.2.13676358**、已安装的 Rust `aarch64-linux-android` 和 `x86_64-linux-android` 目标。本快照使用 AGP **9.1.0**、Kotlin **2.4.0**、Gradle **9.3.1**，Gradle 分发 SHA-256 已固定。构建脚本的 Android 交叉编译当前面向 Windows 主机。

将 `flutter` 和 `cargo` 放进当前进程的 PATH，或传入 `-Flutter`。可在忽略入库的 `.tools/toolchains.json` 中设置 `flutter`、`java`、`androidSdk` 三个本机路径；仓库不附带本机配置。首次恢复依赖需要网络或完整的已有缓存。

## 检查与运行

```powershell
pwsh -File scripts/check.ps1
pwsh -File scripts/run.ps1
pwsh -File scripts/native-check.ps1
```

`check.ps1` 执行 Rust 格式、测试、Clippy、原生库构建和 Dart 格式、分析、Flutter 测试。`run.ps1` 先构建原生库再运行 Windows 应用；不要仅运行 Flutter 而遗漏 Rust 库。`native-check.ps1` 使用独立临时数据运行 Windows 集成测试。

依赖由 Cargo.lock 和 pubspec.lock 锁定；检查/构建使用 `--locked`、`--enforce-lockfile`。Flutter 在 Android 构建时从自身 SDK 缓存补齐 Gradle wrapper 启动文件，因此不将其 JAR 或生成的启动脚本重复入库。Windows 插件链接由脚本创建，必要时需要系统允许符号链接或 junction。

仅检查 Rust 也可执行：

```powershell
cargo test --workspace --locked
```

## 构建本地安装包

```powershell
pwsh -File scripts/build.ps1 -Platform windows
pwsh -File scripts/build.ps1 -Platform android -Configuration Debug `
  -AndroidSdk '<已安装的 Android SDK 目录>' -Java '<已安装的 JDK 目录>'
```

Windows 输出在 `apps/aspan/build/windows/x64/runner/Release/`，运行时必须保留整个目录的 DLL 与 data。Android 按 ARM64 和 x86_64 分包，输出在 `apps/aspan/build/app/outputs/flutter-apk/`。Debug 签名由 Android 开发工具生成；发布构建必须使用你自己的签名。

Android Release 先在 `apps/aspan/android/key.properties` 配置 `storeFile`、`storePassword`、`keyAlias`、`keyPassword`；使用自己的 keystore 绝对路径，不提交这个文件或私钥。随后把上面的 `-Configuration Debug` 改为 `Release`。自签名构建无法覆盖其他证书签名的安装，请先导出数据备份，不要直接卸载旧应用。

构建脚本只生成本地产物，不提交源码、创建 Tag、推送代码或发布 GitHub Release。构建产物不进入源码 Git 历史。若要发布二进制，应先提交公开源码并创建明确 Tag，从该 Tag 的干净源码重新构建；保留工具版本、构建参数与 SHA-256，通过 GitHub Releases 附件分发。仓库中的许可证声明不能替代对具体二进制所含组件的发行检查。

## 使用与数据

运行后在主页处理当前期，在项目页创建规则或使用模板，在“我的”管理外观、模板与备份。余额和日期周期由 Rust 核心计算；涉及扣费、充值或跳过均须显式确认。

Windows 数据位于平台应用支持目录下的 `ASpan/v1/aspan.sqlite3`；Android 使用应用私有目录。卸载 Android 应用通常会清除私有数据。导出/导入为版本化 JSON，导入上限 50 MiB；检查点目前没有应用内回退或自动淘汰入口。

## 许可证

ASpan 应用代码采用 **AGPL-3.0-only**，完整 GNU AGPLv3 原文见 [LICENSE](LICENSE)，不附加禁止商用或限制修改的条款。适当的应用源文件带 SPDX 标识。第三方代码、Flutter 生成的平台模板、引擎与字体保留各自原有许可及版权，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和 `licenses/`。

本快照没有 HTML/JavaScript 插件机制；独立插件保留各自的许可证与接口边界，不能仅凭本项目的许可证就推定所有第三方插件的授权方式。
