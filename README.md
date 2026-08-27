<h1 align="center">
  <img src="logoA.webp" alt="" width="44" height="44" align="middle" valign="middle" />
  &nbsp;Loquat
</h1>

<p align="center">
  A lightweight, native macOS menu bar translator.<br/>
  Press a shortcut, translate instantly — without leaving what you're doing.
</p>

<p align="center">
  English | <a href="README_zh.md">中文</a>
</p>

<p align="center">
  <img src="screenshot1.png" alt="Loquat translation popover" width="600" />
</p>

<p align="center">
  <a href="https://github.com/Moolan-d/Loquat/releases/latest"><img src="https://img.shields.io/github/v/release/Moolan-d/Loquat" alt="GitHub Release" /></a>
  <a href="https://github.com/Moolan-d/Loquat/releases"><img src="https://img.shields.io/github/downloads/Moolan-d/Loquat/total" alt="Downloads" /></a>
  <img src="https://img.shields.io/badge/platform-macOS%2015%2B-blue" alt="Platform" />
  <img src="https://img.shields.io/badge/swift-6.2-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="License" /></a>
</p>

## Features

- **Instant popover** — a global shortcut opens a warm, focused popover from the menu bar; the result appears without switching apps.
- **Two engines in parallel** — Google Translate plus any OpenAI-compatible LLM (OpenAI, DeepSeek, OpenRouter, or a self-hosted endpoint), each **translating, failing, and retrying independently**.
- **Smart direction detection** — Han-script input resolves to Chinese → English, everything else to English → Chinese; override or swap with one click.
- **Clipboard read only when you ask** — only the shortcut reads it: up to 500 characters translates immediately, longer text waits for your Enter; **menu-bar clicks never read the clipboard**.
- **Settings that cover it** — custom shortcut, Google / LLM groups each with a translation-window visibility switch, per-provider connection tests, LLM prompt presets, launch at login.
- **Keys in the Keychain only** — never in preferences, logs, or request URLs; no analytics, no telemetry; remote LLM endpoints must use HTTPS (localhost allowed for local models).

## Config Screenshots

<p align="center">
  <img src="screenshot2.webp" alt="Loquat settings" width="480" />
</p>

## Why Loquat

- **Small and native** — pure Swift, no Electron, no WebView: **~1.4 MB** to download, **~3 MB** installed, **≤ 50 MB** idle physical memory and ~0% idle CPU (verified by the release gate).
- **Spends nothing behind your back** — clipboard translation is bound to the shortcut, so unrelated copies never trigger a paid request.
- **One failure isn't total failure** — one provider's error never invalidates what the other already returned.

## Installation

1. Download `Loquat-macOS.zip` from [GitHub Releases](https://github.com/Moolan-d/Loquat/releases).
2. Unzip it and drag `Loquat.app` into `/Applications`.
3. Open Loquat normally. Published releases are Developer ID signed and notarized.

## Usage

1. Click the menu-bar icon, right-click → **Settings** (or press `⌘,`).
2. Add at least one provider:
   - **Google** — paste a Google Cloud Translation API key.
   - **LLM** — paste an API key, Base URL, and model name (e.g. OpenAI, DeepSeek, OpenRouter).
3. Record a global shortcut.
4. (Optional) enable **Translate Clipboard When Opened by Shortcut** — it appears once a shortcut is set.
5. Press the shortcut to open the popover, then type, or let the clipboard fill it in.

### Getting a Google Cloud Translation API key

1. Go to [Google Cloud Console](https://console.cloud.google.com) and create or select a project.
2. Enable the **Cloud Translation API** (requires a billing account).
3. Open **APIs & Services → Credentials → Create credentials → API key**.
4. (Recommended) restrict the key to the Cloud Translation API.
5. Copy the key and paste it into **Loquat → Settings → Google → API Key**.

### Shortcuts

| Action        | Shortcut                                    |
| ------------- | ------------------------------------------- |
| Open popover  | your global shortcut (set in Settings; the Delete key clears it) |
| Open Settings | right-click the menu-bar icon → Settings    |

## FAQ

### “Loquat.app” is damaged and can’t be opened

Published releases are notarized and should not require **Open Anyway** or `xattr`. Delete the copy, download the ZIP again from the release page, and verify `SHA256SUMS`. If the warning persists, report the release version and macOS version instead of bypassing Gatekeeper.

### Where are my API keys stored?

In the macOS Data Protection Keychain, under `com.instanttranslation.macos.credentials.v2`. Loquat uses its default app-only group and does not enable Keychain Sharing. Keys are never written to `UserDefaults`, logs, or request URLs.

If you used an older release, open Settings and enter each key once. Loquat intentionally does not read or migrate the old file-based Keychain items, so it avoids their legacy authorization prompts. You can remove those old items manually in Keychain Access after confirming the new keys work.

### First-launch authorization prompts

Loquat does not read Keychain at startup. macOS may ask to authorize Keychain access when you open Settings or submit a translation; choose **Allow** or **Always Allow** to store and read your API keys. Loquat does not need Documents access for this workflow.

## Development

```bash
git clone git@github.com:Moolan-d/Loquat.git
cd Loquat

swift test                                        # run the test suite
swift run InstantTranslation                      # run from source

DEVELOPMENT_TEAM=TEAMID \
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  bash scripts/package-app.sh                       # build a signed build/Loquat.app

NOTARYTOOL_PROFILE=loquat-notary \
DEVELOPMENT_TEAM=TEAMID \
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  bash scripts/package-release.sh                   # notarize, staple, and create build/release/Loquat-macOS.zip
```

Create `loquat-notary` once with `xcrun notarytool store-credentials`; the release script passes only its Keychain profile name and never prints notarization credentials. This app uses no restricted capabilities, so Developer ID packaging does not require an embedded provisioning profile.

## License

[Apache-2.0](LICENSE)
