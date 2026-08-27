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

- **Small and native** — pure Swift, no Electron, no WebView: **~2.2 MB** to download, **~4 MB** installed, **≤ 50 MB** idle physical memory and ~0% idle CPU (verified by the release gate).
- **Spends nothing behind your back** — clipboard translation is bound to the shortcut, so unrelated copies never trigger a paid request.
- **One failure isn't total failure** — one provider's error never invalidates what the other already returned.

## Installation

1. Download `Loquat-macOS.zip` from [GitHub Releases](https://github.com/Moolan-d/Loquat/releases) and verify `SHA256SUMS` (`shasum -a 256 -c SHA256SUMS`).
2. Unzip it and drag `Loquat.app` into `/Applications`.
3. Try Control-click (or right-click) `Loquat.app` → **Open**.
4. If macOS still blocks it, open **System Settings → Privacy & Security → Open Anyway**.
5. Only if both UI paths fail, run `xattr -dr com.apple.quarantine /Applications/Loquat.app` as a last resort.

The published release is ad-hoc signed and **not notarized**. These steps let Gatekeeper open this specific downloaded app; they bypass Gatekeeper for it and do not verify notarization. Download the artifact only from GitHub Releases and verify `SHA256SUMS` before bypassing Gatekeeper. Never disable Gatekeeper globally.

## Usage

1. Click the menu-bar icon, right-click → **Settings** (or press `⌘,`).
2. Add at least one provider:
   - **Google** — paste a Google Cloud Translation API key.
   - **LLM** — paste an API key and Base URL. Other OpenAI-compatible endpoints require a model name; OpenRouter may leave it blank to use `openrouter/free`.
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

The release is ad-hoc signed and not notarized, so macOS may flag it. First try **Control-click → Open**, then **System Settings → Privacy & Security → Open Anyway**. If both fail, `xattr -dr com.apple.quarantine /Applications/Loquat.app` is the last fallback — it bypasses Gatekeeper for this app and does not verify notarization. Download the ZIP only from GitHub Releases, delete the quarantined copy, and verify `SHA256SUMS` before proceeding.

### Where are my API keys stored?

In the macOS file-based Keychain, under `com.instanttranslation.macos.credentials.v3`. Keys are never written to `UserDefaults`, logs, or request URLs.

Older releases used the v1/v2 Keychain services. Loquat never reads, migrates, updates, or deletes those old items, so they keep their previous authorization behavior. Enter each credential once in Settings after installing; you may remove the old items manually in Keychain Access after confirming the new ones work.

### Keychain authorization prompts

Loquat does not read Keychain at startup; prompts, if any, happen only after you open Settings or submit a translation — choose **Allow** or **Always Allow** to store and read your API keys. The legacy macOS Keychain ACL may also ask for access again after you replace the app with a newer ad-hoc build; that is expected and separate from Gatekeeper. Loquat does not need Documents access for this workflow.

## Development

```bash
git clone git@github.com:Moolan-d/Loquat.git
cd Loquat

swift test                                       # run the test suite
swift run InstantTranslation                     # run from source

bash scripts/package-app.sh     # build ad-hoc-signed build/Loquat.app
bash scripts/package-release.sh # build/release/Loquat-macOS.zip + SHA256SUMS
```

No certificate, Team ID, provisioning profile, or notarization credentials are required. `package-release.sh` prints the final ZIP path after verifying its checksum.

## License

[Apache-2.0](LICENSE)
