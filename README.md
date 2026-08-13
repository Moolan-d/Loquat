<h1 align="center">Loquat</h1>

<p align="center">
  A lightweight, native macOS menu bar translator.<br/>
  Press a shortcut, translate instantly — without leaving what you're doing.
</p>

<p align="center">
  English | <a href="README_zh.md">中文</a>
</p>

<p align="center">
  <img src="screenshot1.webp" alt="Loquat translation popover" width="600" />
</p>

<p align="center">
  <a href="https://github.com/Moolan-d/Loquat/releases/latest"><img src="https://img.shields.io/github/v/release/Moolan-d/Loquat" alt="GitHub Release" /></a>
  <a href="https://github.com/Moolan-d/Loquat/releases"><img src="https://img.shields.io/github/downloads/Moolan-d/Loquat/total" alt="Downloads" /></a>
  <img src="https://img.shields.io/badge/platform-macOS%2015%2B-blue" alt="Platform" />
  <img src="https://img.shields.io/badge/swift-6.2-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="License" /></a>
</p>

## Features

### Translation

- **Instant popover** — a global shortcut opens a warm, focused popover from the menu bar; the result appears without switching apps.
- **Two engines in parallel** — Google Translate and any OpenAI-compatible LLM (OpenAI, DeepSeek, OpenRouter, or a self-hosted endpoint). Each provider translates, succeeds, fails, and retries independently, so one error never hides the other's result.
- **Smart direction detection** — Han-script input resolves to Chinese → English, everything else to English → Chinese. Override or swap the direction with one click.

### Input

- **Manual input** — type or paste anything, any time.
- **Clipboard on shortcut** — opening the popover via the global shortcut can read the clipboard automatically. Text up to 500 characters translates immediately; longer text is filled in and waits for you to press Enter, so you never spend API quota by accident.
- **Menu-bar clicks never read the clipboard** — ordinary copies stay ordinary.

### Settings

- Custom global shortcut (record any key combination).
- Providers grouped into **Google** and **LLM**, each with a visibility switch for the translation window.
- Per-provider connection tests.
- LLM prompt presets (General / Technology & R&D).
- Launch at login.

### Privacy

- API keys live in the macOS **Keychain only** — never in preferences, logs, or request URLs.
- No analytics, no telemetry, no third-party runtime dependencies.
- Remote LLM endpoints must use HTTPS (localhost is allowed for local models).

## Config Screenshots

<p align="center">
  <img src="screenshot2.webp" alt="Loquat settings" width="480" />
</p>

## Why Loquat

- **Clipboard reads only when you ask for them** — binding clipboard translation to the shortcut keeps unrelated copies from triggering paid requests.
- **Small and native** — pure Swift, no Electron, no WebView.
- **Fail independently** — one provider's error never invalidates the other's successful result.

## Performance

- **Download size** — `Loquat-macOS.zip` is ~1.4 MB.
- **Installed size** — ~3 MB unpacked.
- **Idle memory** — ≤ 50 MB per-process physical footprint, ~0% idle CPU (verified by the release gate).

## Installation

1. Download `Loquat-macOS.zip` from [GitHub Releases](https://github.com/Moolan-d/Loquat/releases).
2. Unzip it and drag `Loquat.app` into `/Applications`.
3. On first launch, if Gatekeeper blocks the ad-hoc signed app, right-click → **Open**, or go to **System Settings → Privacy & Security → Open Anyway**.

## Usage

1. Click the menu-bar icon, right-click → **Settings** (or press `⌘,`).
2. Add at least one provider:
   - **Google** — paste (right-click) a Google Cloud Translation API key.
   - **LLM** — paste (right-click) an API key, Base URL, and model name (e.g. OpenAI, DeepSeek, OpenRouter).
3. Record a global shortcut.
4. (Optional) enable **Translate Clipboard When Opened by Shortcut** — it appears once a shortcut is set.
5. Press the shortcut to open the popover, then type, or let the clipboard fill it in.

### Getting a Google Cloud Translation API key

1. Go to [Google Cloud Console](https://console.cloud.google.com) and create or select a project.
2. Enable the **Cloud Translation API** (requires a billing account).
3. Open **APIs & Services → Credentials → Create credentials → API key**.
4. (Recommended) restrict the key to the Cloud Translation API.
5. Copy the key and paste (right-click) it into **Loquat → Settings → Google → API Key**.

### Shortcuts

| Action        | Shortcut                                    |
| ------------- | ------------------------------------------- |
| Open popover  | your global shortcut (set in Settings; the Delete key clears it) |
| Open Settings | right-click the menu-bar icon → Settings    |

## FAQ

### “Loquat.app” is damaged and can’t be opened

The app is ad-hoc signed and not notarized, so Gatekeeper may block it. It doesn’t mean the file is corrupted. Either right-click → **Open**, or run:

```bash
xattr -cr /Applications/Loquat.app
```

### Where are my API keys stored?

In the macOS Keychain, under `com.instanttranslation.macos.credentials`. They are never written to `UserDefaults`, logs, or request URLs.

### First-launch authorization prompts

On first launch, macOS may show two permission dialogs:

- **Keychain** — Loquat stores your API keys there. Choose **Allow** or **Always Allow** so the app can save and read them.
- **Documents access** — macOS may ask Loquat to access your files. Allow it so the app can work normally.

## Development

```bash
git clone git@github.com:Moolan-d/Loquat.git
cd Loquat

swift test                                        # run the test suite
swift run InstantTranslation                      # run from source

SIGNING_MODE=adhoc bash scripts/package-app.sh    # build a runnable build/Loquat.app
SIGNING_MODE=adhoc bash scripts/package-release.sh # build/release/Loquat-macOS.zip
```

## License

[Apache-2.0](LICENSE)
