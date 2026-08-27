# Instant Translation 发布内存与诊断门禁修订设计

> **状态：已于 2026-08-27 归档。** Settings 懒构造已经交付；内存/Bundle 扫描、独立诊断程序及其文档方案不再实施。下文只保留为历史设计背景，不构成当前发布要求。
>
> 当前发布依据为 `docs/superpowers/specs/2026-08-27-free-adhoc-release-design.md`、`docs/superpowers/plans/2026-08-27-free-adhoc-release.md` 与 `docs/manual-free-release-checklist.md`。

日期：2026-08-13
归档日期：2026-08-27
适用范围：历史记录

## 1. 背景与结论

现有 `measure-memory.sh` 使用 `ps rss` 作为 50 MB 硬门禁。macOS 26.5.1 上，同一个 release 进程稳定显示约 107–113 MB RSS，但 Apple `footprint`、`vmmap` 和 `top MEM` 显示其 `phys_footprint` 约为 32–34 MB。`ps rss` 包含大量可回收的 clean/shared framework resident pages，不能准确表达应用实际承担的物理内存。

诊断还确认组合根在启动时创建了尚不可见的 Settings `NSWindow` 与完整 SwiftUI 树，额外消耗约 13 MB physical footprint。主翻译 popover 的预构造增量约 0–1 MB，且直接服务于低于 100 ms 的 warm-open 目标，因此保留预热。

本修订保持“50 MB”产品目标不变，将其精确定义为 Apple per-process physical footprint，并同时消除隐藏 Settings 的无效常驻成本。

## 2. 方案边界

本次实现包含四项：

1. 将发布内存硬门改为 `phys_footprint_kb <= 51,200`；
2. Settings 窗口与 SwiftUI 内容首次打开时懒构造；
3. 强化 bundle、密钥夹具与进程生命周期检查，使失败不能被当作无匹配而放行；
4. 增加只供开发者使用、不会进入 Release `.app` 的诊断可执行程序。

本次不改变翻译交互、Provider 协议、Keychain 生产后端、主 popover 预热策略、50 MB 数值阈值或 GitHub Release 的 ad-hoc 分发方案。

## 3. 内存指标

### 3.1 权威指标

`scripts/measure-memory.sh` 以 Apple `footprint` 提供的 per-process physical footprint 为硬门指标。脚本同时输出：

- `physical_footprint_kb`：发布硬门；
- `rss_kb`：诊断参考，不决定成功或失败；
- `cpu_percent`：继续使用既有 `ps` 口径，硬门保持 `<= 0.5`。

脚本必须验证工具存在、输出非空且为数值。工具执行失败、解析失败或进程提前退出都直接失败，禁止回退到 RSS 后静默通过。

### 3.2 进程归属与清理

脚本只管理自己启动的子进程，并保存启动时的 PID、命令路径与启动标识。采样前和清理前均验证身份；若应用提前退出或身份不匹配，脚本报告失败且不向该 PID 发送信号。

信号处理器使用明确的非零退出码。临时目录通过 `mktemp -d` 创建并由精确路径清理；禁止 broad kill、`pkill`、未解析 glob 或基于进程名杀进程。

## 4. Settings 懒构造

### 4.1 生命周期

`ApplicationContainer` 仍只保留一个 `SettingsViewModel` 与一个 `SettingsWindowController`。控制器在应用启动时创建，但不创建 `NSWindow`、`NSHostingView` 或 `SettingsView`。

首次收到右键菜单、应用菜单 `⌘,` 或 `.openInstantTranslationSettings` 通知时，控制器创建唯一窗口及其 SwiftUI 内容。关闭窗口后继续复用同一窗口与模型，保持当前窗口位置、编辑状态和“关闭后重开”行为。

因此，“单实例复用”约束保持不变，只有昂贵视图树的创建时机从应用启动推迟到首次实际使用。

### 4.2 错误与并发

窗口创建和显示均在 `MainActor`。多个连续打开事件不得创建多个窗口。若首次打开事件重入，后续调用复用已经建立的窗口。

应用启动阶段的 credential migration、shortcut 和 Settings 模型构造顺序不变。懒构造不得吞掉启动错误，也不得建立第二份 credential store、session、appearance 或 shortcut registrar。

## 5. 发布安全门禁

### 5.1 Bundle 能力扫描

`verify-bundle.sh` 同时执行源代码与成品 bundle 两层检查：

- 源代码层检查禁止的全局/本地 event monitor、`CGEventTap`、WebView 和首版受保护权限 API；
- bundle 层递归枚举所有 Mach-O executable、framework 和 dylib，再检查禁止符号与运行时远程图标主机；
- 验证四个 Provider SVG 位于生产 loader 使用的精确资源路径；
- 验证 `Info.plist` 不包含受保护资源 usage keys；
- 验证代码签名与已有 signing gates。

`rg`、`find`、`file`、`strings`、`nm` 或解析工具缺失/执行失败时，门禁直接失败。空扫描集合也失败，避免 pipeline/process-substitution 将工具错误解释为“没有匹配”。

### 5.2 测试密钥夹具

仓库维护一个明确的测试密钥夹具清单。自动检查必须证明：

1. Tests 中符合 credential/team/account 可疑模式的字面量均被清单覆盖；
2. 清单中的每个非空条目均不出现在 `.app`、ZIP、checksum 或解压产物中；
3. `find`、读取或搜索失败直接使发布失败。

该门禁只声称覆盖仓库已知夹具，不声称能够识别任意未知秘密。

## 6. 开发者诊断程序

### 6.1 交付形态

新增独立 Swift Package executable target，例如 `InstantTranslationDiagnostics`。它复用 `InstantTranslationApp` 的公开/内部组合接口，但不被 `package-app.sh` 或 `package-release.sh` 复制进 Release `.app`。

诊断程序不使用真实 Keychain、剪贴板或网络。它通过内存 Preferences/Credential store、确定性 TranslationProvider 和可控 connection tester 构造与正式应用相同的 Settings/translation presentation。

### 6.2 场景

命令行参数选择单一场景：

- slow in-flight request；
- Google-only failure；
- LLM-only failure；
- 401/403 invalid credentials；
- 429 rate limit；
- offline/network unavailable；
- timeout；
- malformed LLM response；
- credential read unavailable then reload succeeds；
- save rollback incomplete / needs-attention。

每个场景都有稳定名称、固定非秘密数据和可访问性描述。未知场景以非零状态退出并列出有效名称。诊断程序不得从环境变量读取真实 API key，也不得写入生产 `UserDefaults` suite。

### 6.3 人工验收入口

提供 `scripts/run-diagnostics.sh <scenario>`，构建并启动诊断程序。人工清单为每个需要 UI 操作的故障场景给出精确命令、预期卡片/Settings 状态与关闭方式。

纯协议边界继续由 XCTest 自动验证；人工清单不再用不可执行的自然语言替代 harness，也不重复要求真实服务产生 429 或畸形响应。

## 7. 测试策略

所有生产变更遵循 RED→GREEN：

- Settings 测试先证明控制器初始化时没有窗口/hosting tree，首次打开只创建一次，关闭后重开复用相同 identity；临时恢复 eager construction 应使测试 RED；
- 内存脚本夹具覆盖 physical-footprint 边界、解析失败、工具失败、提前退出、身份不匹配、CPU 边界与精确清理；
- bundle 脚本夹具覆盖嵌套 Mach-O 禁止符号、缺失工具、空扫描集合、错误资源路径和命令失败；
- 密钥清单测试覆盖新增但未登记夹具、读取失败和 artifact 命中；
- 诊断程序对每个场景验证 provider/card/settings 状态和零真实 I/O；至少一个路由 mutation 必须产生 RED；
- 最终运行 clean 全量 XCTest、签名/打包回归、ad-hoc ZIP/checksum、bundle gate、诊断场景矩阵和真实内存门禁。

Thread Sanitizer 若仍被 dyld platform policy 阻止，保留准确的外部门禁记录，不伪造成功。

## 8. 验收标准

- 应用冷启动不构造 Settings window 或 Settings SwiftUI tree；首次打开与后续复用行为正确；
- release 进程 `physical_footprint_kb <= 51,200` 且 idle CPU `<= 0.5%`；RSS 仅记录；
- 安全扫描的任何工具/遍历/解析错误均导致非零退出；
- Release artifact 不包含诊断 executable、测试夹具、测试 targets 或已知测试密钥；
- 所有人工故障场景具有可运行的无真实凭据诊断命令；
- GitHub Release 仍为 ad-hoc、未公证、ZIP + `SHA256SUMS`，不需要付费 Apple Developer 账号。
