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

- **小巧原生** — 纯 Swift，无 Electron、无 WebView：下载约 **1.4 MB**，安装后约 **3 MB**，空闲物理内存 ≤ **50 MB**、CPU 接近 0%（由发布门槛校验）。
- **不乱花钱** — 剪贴板翻译绑定在快捷键上，无关的复制不会触发付费请求。
- **不会一错全错** — 一个引擎出错，不影响另一个引擎已经拿到的结果。

## 安装

1. 从 [GitHub Releases](https://github.com/Moolan-d/Loquat/releases) 下载 `Loquat-macOS.zip`。
2. 解压后把 `Loquat.app` 拖入 `/Applications`。
3. 首次启动若被 Gatekeeper 拦截（adhoc 签名），右键 → **打开**，或前往 **系统设置 → 隐私与安全性 → 仍要打开**。

## 使用

1. 点击菜单栏图标，右键 → **Settings**（或按 `⌘,`）。
2. 至少配置一个引擎：
   - **Google** — 粘贴（右键） Google Cloud Translation API 密钥。
   - **LLM** — 粘贴（右键） API 密钥、Base URL 与模型名（如 OpenAI、DeepSeek、OpenRouter）。
3. 录制一个全局快捷键。
4. （可选）开启 **Translate Clipboard When Opened by Shortcut**——设置快捷键后该选项才会出现。
5. 按下快捷键唤出弹窗，输入内容，或让剪贴板自动填入。

### 获取 Google Cloud Translation API 密钥

1. 打开 [Google Cloud 控制台](https://console.cloud.google.com)，新建或选择一个项目。
2. 启用 **Cloud Translation API**（需要结算账号）。
3. 进入 **API 和服务 → 凭据 → 创建凭据 → API 密钥**。
4. （推荐）把密钥限制到 Cloud Translation API。
5. 复制密钥，粘贴（右键）到 **Loquat → 设置 → Google → API Key**。

### 快捷键

| 操作     | 快捷键                                   |
| -------- | ---------------------------------------- |
| 唤出弹窗 | 你的全局快捷键（在设置中录制，backup 键可删除）        |
| 打开设置 | 右键菜单栏图标 → Settings                |

## 常见问题

### 「Loquat.app」已损坏、无法打开

应用是 adhoc 签名、未公证，所以 Gatekeeper 可能拦截。这不代表文件损坏。右键 → **打开**，或执行：

```bash
xattr -cr /Applications/Loquat.app
```

### 我的 API 密钥存在哪里？

存于 macOS 钥匙串，服务名 `com.instanttranslation.macos.credentials`。绝不写入 `UserDefaults`、日志或请求 URL。

### 首次启动的授权提示

首次启动时，macOS 可能会弹出两个授权提示：

- **钥匙串** — Loquat 把 API 密钥存在钥匙串里。选择「允许」或「始终允许」，应用才能保存和读取密钥。
- **读取文稿** — macOS 可能请求访问文件的权限。允许即可，应用才能正常工作。

## 开发

```bash
git clone git@github.com:Moolan-d/Loquat.git
cd Loquat

swift test                                          # 运行测试套件
swift run InstantTranslation                        # 从源码运行

SIGNING_MODE=adhoc bash scripts/package-app.sh      # 构建可运行的 build/Loquat.app
SIGNING_MODE=adhoc bash scripts/package-release.sh  # 构建 build/release/Loquat-macOS.zip
```

## 许可证

[Apache-2.0](LICENSE)
