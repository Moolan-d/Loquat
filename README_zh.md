<h1 align="center">
  <img src="logoA.webp" alt="" width="44" height="44" align="middle" valign="middle" />
  &nbsp;Loquat
</h1>

<p align="center">
  轻量的原生 macOS 菜单栏翻译工具。<br/>
  按下快捷键，即时翻译——不打断你手头的事。
</p>

<p align="center">
  <a href="README.md">English</a> | 中文
</p>

<p align="center">
  <img src="screenshot1.png" alt="Loquat 翻译弹窗" width="600" />
</p>

<p align="center">
  <a href="https://github.com/Moolan-d/Loquat/releases/latest"><img src="https://img.shields.io/github/v/release/Moolan-d/Loquat" alt="GitHub Release" /></a>
  <a href="https://github.com/Moolan-d/Loquat/releases"><img src="https://img.shields.io/github/downloads/Moolan-d/Loquat/total" alt="Downloads" /></a>
  <img src="https://img.shields.io/badge/platform-macOS%2015%2B-blue" alt="Platform" />
  <img src="https://img.shields.io/badge/swift-6.2-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="License" /></a>
</p>

## 特性

- **即时弹窗** — 一个全局快捷键从菜单栏唤出热弹窗，结果即刻呈现，不用切换应用。
- **双引擎并行** — Google 翻译 + 任意 OpenAI 兼容模型（OpenAI、DeepSeek、OpenRouter 或自建端点），**独立翻译、独立成败、独立重试**。
- **智能方向检测** — 含汉字判为「中文 → 英文」，其余判为「英文 → 中文」，可一键覆盖或对调。
- **剪贴板只在你要时读取** — 仅快捷键唤出时读：≤ 500 字符立即翻译，更长的只填入输入框等你确认；**菜单栏点击永不读剪贴板**。
- **设置齐全** — 自定义快捷键、Google / LLM 分组及各自的窗口显示开关、连通性测试、LLM 提示词预设、登录时启动。
- **密钥只进钥匙串** — 绝不写入偏好设置、日志或请求 URL；无统计无遥测；远程 LLM 端点强制 HTTPS（本地模型允许 localhost）。

## 配置页截图

<p align="center">
  <img src="screenshot2.webp" alt="Loquat 设置界面" width="480" />
</p>

## 为什么是 Loquat

- **小巧原生** — 纯 Swift，无 Electron、无 WebView：下载约 **1.4 MB**，安装后约 **3 MB**，空闲物理内存 ≤ **30 MB**、CPU 接近 0%。
- **不乱花钱** — 剪贴板翻译绑定在快捷键上，无关的复制不会触发付费请求。
- **不会一错全错** — 一个引擎出错，不影响另一个引擎已经拿到的结果。

## 安装

1. 从 [GitHub Releases](https://github.com/Moolan-d/Loquat/releases) 下载 `Loquat-macOS.zip`。
2. 解压后把 `Loquat.app` 拖入 `/Applications`。
3. 直接正常打开 Loquat。正式发布包使用 Developer ID 签名并已完成公证。

## 使用

1. 点击菜单栏图标，右键 → **Settings**（或按 `⌘,`）。
2. 至少配置一个引擎：
   - **Google** — 粘贴 Google Cloud Translation API 密钥。
   - **LLM** — 粘贴 API 密钥、Base URL 与模型名（如 OpenAI、DeepSeek、OpenRouter）。
3. 录制一个全局快捷键。
4. （可选）开启 **Translate Clipboard When Opened by Shortcut**——设置快捷键后该选项才会出现。
5. 按下快捷键唤出弹窗，输入内容，或让剪贴板自动填入。

### 获取 Google Cloud Translation API 密钥

1. 打开 [Google Cloud 控制台](https://console.cloud.google.com)，新建或选择一个项目。
2. 启用 **Cloud Translation API**（需要结算账号）。
3. 进入 **API 和服务 → 凭据 → 创建凭据 → API 密钥**。
4. （推荐）把密钥限制到 Cloud Translation API。
5. 复制密钥，粘贴到 **Loquat → 设置 → Google → API Key**。

### 快捷键

| 操作     | 快捷键                                   |
| -------- | ---------------------------------------- |
| 唤出弹窗 | 你的全局快捷键（在设置中录制，backup 键可删除）        |
| 打开设置 | 右键菜单栏图标 → Settings                |

## 常见问题

### 「Loquat.app」已损坏、无法打开

正式发布包已经公证，不应需要「仍要打开」或 `xattr`。请删除当前副本，从 Release 页面重新下载 ZIP 并校验 `SHA256SUMS`。若仍出现提示，请反馈 Release 版本和 macOS 版本，而不要绕过 Gatekeeper。

### 我的 API 密钥存在哪里？

存于 macOS Data Protection 钥匙串，服务名 `com.instanttranslation.macos.credentials.v2`。Loquat 使用应用默认、仅自身可访问的 group，不启用 Keychain Sharing；绝不写入 `UserDefaults`、日志或请求 URL。

若你使用过旧版本，请打开设置并重新输入一次各个密钥。Loquat 不会读取或迁移旧的 file-based 钥匙串项，因此不会触发它们的旧授权弹窗。确认新密钥可用后，可在「钥匙串访问」中手动删除旧项。

### 首次启动的授权提示

Loquat 启动时不读取钥匙串。打开设置或提交翻译时，macOS 可能请求钥匙串授权；选择「允许」或「始终允许」，应用即可保存和读取 API 密钥。此流程不需要「文稿」访问权限。

## 开发

```bash
git clone git@github.com:Moolan-d/Loquat.git
cd Loquat

swift test                                          # 运行测试套件
swift run InstantTranslation                        # 从源码运行

DEVELOPMENT_TEAM=TEAMID \
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  bash scripts/package-app.sh                        # 构建已签名的 build/Loquat.app

NOTARYTOOL_PROFILE=loquat-notary \
DEVELOPMENT_TEAM=TEAMID \
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  bash scripts/package-release.sh                    # 公证、装订票据并生成 build/release/Loquat-macOS.zip
```

使用一次 `xcrun notarytool store-credentials` 创建 `loquat-notary`；脚本只传递其钥匙串 profile 名称，不会输出公证凭据。当前应用没有受限 capability，因此 Developer ID 打包不需要嵌入 provisioning profile。

## 许可证

[Apache-2.0](LICENSE)
