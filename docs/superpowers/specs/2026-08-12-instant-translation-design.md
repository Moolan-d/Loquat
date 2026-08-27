# Instant Translation for macOS — Design Specification

**Date:** 2026-08-12

**Status:** Approved design

**Target:** macOS 15 and later

## 1. Purpose

Instant Translation is a lightweight, menu-bar-only macOS utility for translating specialized terms between Chinese and English without opening a browser.

The product removes noise rather than maximizing the number of features. Each query produces two independent results:

1. a direct result from Google Cloud Translation; and
2. a terminology-aware result from an OpenAI-compatible large language model (LLM), consisting of one primary translation and one concise rationale.

The utility must remain resident without disrupting development work. Its release-build idle memory target is no more than 50 MB, and its idle CPU usage must be effectively zero.

## 2. Competitive research

Existing projects prove the product category but do not fully match the intended scope:

- [MoePeek](https://github.com/cosZone/MoePeek) is the closest lightweight native reference. It supports manual, clipboard, selection, and OCR translation and reports an approximately 5 MB application size and 50 MB background memory use. Its broader feature set, AGPL license, and acknowledged edge cases make a clean implementation preferable to a fork.
- [BarTranslate](https://github.com/ThijmenDam/BarTranslate) closely matches the menu-bar input workflow but embeds Google Translate in a WebView, which conflicts with the no-WebView resource goal.
- [Easydict](https://github.com/tisfeng/Easydict) is a mature native macOS dictionary and translation application, but its OCR, TTS, dictionary, selection, and extensive provider features exceed the first release's scope.
- [Pot](https://github.com/pot-app/pot-desktop) is a capable cross-platform Tauri application with many providers and a plugin system, but it is not optimized for a minimal native macOS resident process.
- [Quick Translate](https://github.com/gawasa29/macos-quick-translate) demonstrates a native, on-device menu-bar workflow, but targets a selection-driven HUD rather than the required dual-source input panel.
- [Bob](https://github.com/ripperhe/Bob) validates the product interaction model but is not open source.

The product gap is therefore not a generic translator. It is a low-noise, dual-source terminology verifier with a deliberately narrow first release and explicit seams for later OCR, selection translation, more languages, pronunciation, and speech.

## 3. Scope

### 3.1 First release

The first release includes:

- a menu-bar icon with no Dock icon;
- a transient popover that closes when the user clicks outside it;
- an optional, disabled-by-default global shortcut;
- manual text input;
- an optional, disabled-by-default behavior that reads the latest plain-text clipboard value whenever the popover opens and immediately translates it;
- automatic Chinese-to-English or English-to-Chinese direction selection with a manual correction control;
- independent, parallel Google Cloud Translation and LLM requests;
- Google primary translation output;
- LLM primary translation plus one concise rationale;
- independent copy buttons for the Google and LLM primary translations;
- native light and dark appearances, vibrancy, high-contrast compatibility, and reduced-transparency fallback;
- a settings window for behavior, credentials, service configuration, and the two LLM prompt presets;
- secure credential storage in macOS Keychain;
- no query history and no persisted source or translated text.

### 3.2 Explicitly deferred

The following features are not implemented in the first release:

- selected-text capture;
- screenshot OCR;
- languages other than Chinese and English;
- phonetic transcriptions;
- TTS playback;
- translation history;
- a plugin marketplace, dynamic plugin loader, or script runtime;
- providers other than Google Cloud Translation and one OpenAI-compatible LLM endpoint.

The architecture retains stable extension seams for these features without preloading their frameworks, requesting their permissions, or exposing incomplete interface controls.

## 4. User experience

### 4.1 Application presence

The application runs as a macOS accessory application. It has no Dock icon and no conventional main window. The menu-bar item is the primary entry point. A configurable global shortcut can also toggle the popover but is disabled by default.

Clicking the menu-bar icon or invoking the shortcut opens the same popover. The input field immediately receives focus. Clicking outside the popover closes it. Closing the popover does not quit the application.

### 4.2 Popover layout

The popover uses a single-column reading order:

1. a compact direction control showing the detected source and target languages;
2. an unlabeled input field;
3. a subtle `Enter` hint;
4. a Google result card; and
5. an LLM result card.

There is no “input term” label and no prompt-preset selector in the popover. The active LLM prompt preset is configured in Settings and persists until changed.

Result-card headers use provider logos rather than source-name labels. Google uses the Google Translate mark. The LLM card derives its mark from the configured Base URL hostname for known providers such as OpenAI, DeepSeek, and OpenRouter. Unknown hosts use a bundled generic AI mark. Logos are bundled application assets; the application does not fetch or cache remote logos.

Each result card has an independent copy button. It copies only that provider's primary translation. The LLM rationale is not included. On success, the button briefly changes to a checkmark without closing the popover or changing focus. Result text remains selectable through standard macOS text selection.

### 4.3 Native appearance

The popover uses an AppKit `NSVisualEffectView` as the native vibrancy/material host. SwiftUI content renders above that host. The application follows the macOS light or dark appearance automatically and does not emulate appearance through fixed translucent colors.

The result must remain legible with Increase Contrast enabled. With Reduce Transparency enabled, the surface falls back to an opaque or substantially more solid native material. All icon-only actions expose VoiceOver labels and keyboard focus states.

## 5. Architecture

### 5.1 Technology choice

The implementation uses an AppKit shell with SwiftUI content:

- AppKit owns the accessory application lifecycle, menu-bar item, transient popover, focus behavior, outside-click dismissal, and `NSVisualEffectView` material.
- SwiftUI owns the translation content view and Settings interface.
- Foundation `URLSession` performs all network requests through an ephemeral configuration with no disk cache, cookie store, or persistent credential store.
- Security framework APIs store credentials in Keychain.
- AppKit pasteboard APIs read and write clipboard text.
- No third-party runtime dependencies, Electron runtime, WebView, polling loop, or resident local HTTP server are used.

This split gives AppKit control over the behaviors most likely to affect resident memory and native window semantics while keeping the small content and settings surfaces declarative.

### 5.2 Module boundaries

#### Application shell

- `AppLifecycle` starts the accessory application and owns the single application container.
- `StatusBarController` owns the status item and optional global shortcut.
- `TranslationPopoverController` owns the popover, native visual-effect host, focus, toggle behavior, and outside-click dismissal.

#### Presentation

- `TranslationView` renders current input, direction, provider states, results, copy controls, and localized errors.
- `SettingsView` edits non-secret preferences and sends secret values to the credential store.
- `TranslationSession` is the observable in-memory state of only the current query.

#### Input capability layer

All inputs conform to an `InputSource` contract that produces normalized `SourceText` without knowledge of the UI or providers.

- `ManualInputSource` and `ClipboardInputSource` are implemented in the first release.
- A future `SelectionInputSource` can use Accessibility, AppleScript, and clipboard fallback.
- A future `OCRInputSource` can use ScreenCaptureKit and Vision.

Selection and OCR remain separate optional capabilities. Adding them must not change the translation core or require permissions until a user enables or invokes the relevant capability.

#### Translation core

- `DirectionResolver` identifies Chinese or English and accepts a user override.
- `LanguageCatalog` contains language metadata, display names, provider identifiers, and support matrices.
- `TranslationCoordinator` starts enabled providers concurrently and isolates provider errors.
- `TranslationProvider` is the stable interface implemented by `GoogleTranslationProvider` and `LLMTranslationProvider`.

Core APIs use `LanguageID` domain values rather than a Chinese/English Boolean. The first-release catalog exposes only Chinese and English, so adding more languages extends catalog data and provider support matrices instead of changing request types.

### 5.3 Request and result models

`TranslationRequest` contains:

- normalized source text;
- input-source metadata;
- source and target `LanguageID` values;
- whether direction was detected or manually selected;
- the selected prompt-preset identifier; and
- an opaque request ID.

`TranslationResult` contains:

- provider identity;
- primary translated text;
- an optional concise rationale;
- source and target languages;
- request ID;
- duration; and
- provider error state where applicable.

The result model reserves optional, empty-by-default fields for future capabilities:

- `pronunciations: [Pronunciation]`, where each pronunciation records its scheme (for example IPA, KK, DJ, or Pinyin), text, language, and source; and
- `speakableText`, which defaults to the primary translation when absent.

`TranslationResult` never owns audio files, players, or speech engines. A future `SpeechProvider` accepts a separate `SpeechRequest` containing text, language, voice, rate, and pitch. System and cloud TTS implementations can conform to that contract and are instantiated only when playback is requested.

## 6. Providers

### 6.1 Google Cloud Translation

The first release uses the official Cloud Translation Basic v2 REST endpoint:

`POST https://translation.googleapis.com/language/translate/v2`

The request uses plain-text format and explicit source and target language codes determined by `DirectionResolver`. The API key is sent through the `X-Goog-Api-Key` HTTP header rather than a query parameter so it does not appear in URLs. The Google key should be restricted in Google Cloud to the Cloud Translation API.

The Google provider returns only its primary translation in the result card.

### 6.2 OpenAI-compatible LLM

The LLM configuration contains:

- Base URL;
- API key;
- model name; and
- the two editable system prompt presets.

The Base URL is an API root such as `https://api.openai.com/v1`; the application normalizes a trailing slash and appends `/chat/completions`. The provider makes a non-streaming OpenAI-compatible chat-completions request. It requests a compact JSON object with exactly two string fields, `translation` and `rationale`. The parser first attempts that representation. If a compatible service returns plain text or malformed structured data, it extracts a usable primary translation when possible rather than discarding the response solely because the rationale is absent.

The provider supports two built-in prompt presets:

- `general`; and
- `technology-and-r-and-d`.

Both prompts are editable and can be restored independently to their bundled defaults. `technology-and-r-and-d` is selected by default on first launch. The preset selection lives only in Settings and persists until changed.

Non-local Base URLs must use HTTPS. HTTP is accepted only for loopback hosts such as `localhost`, `127.0.0.1`, and `::1`, enabling local OpenAI-compatible servers without weakening remote transport requirements.

## 7. Runtime behavior

### 7.1 Query lifecycle

Each submitted input creates a short-lived translation session:

1. normalize and validate the input;
2. determine or apply the source/target direction;
3. assign a new request ID;
4. place Google and LLM cards into independent loading states;
5. start both provider tasks concurrently;
6. render each provider's result as soon as it arrives; and
7. retain the current input and results only in memory until another distinct input replaces them or the application exits.

The coordinator never waits for both tasks before publishing a successful result.

Google requests use a fixed 15-second timeout and LLM requests use a fixed 60-second timeout. The application performs no automatic retry. These values are implementation constants in the first release rather than user-facing settings.

### 7.2 Popover closure and cancellation

Closing the popover does not cancel in-flight requests. If a request succeeds or fails while the popover is closed, reopening the popover shows the final state.

Submitting different input cancels both tasks from the preceding session and increments the request ID. A late response with an obsolete request ID is discarded even if underlying transport cancellation did not stop it in time. Quitting the application cancels all remaining work.

Opening the popover again with unchanged input and already completed results does not resend requests. A user-explicit retry resends only the selected failed provider.

### 7.3 Clipboard-on-shortcut

The clipboard-on-shortcut option is disabled by default and is a dependent sub-setting of the global shortcut: it only appears in Settings when a shortcut is configured, and clearing the shortcut also turns it off. When enabled:

- only opening the popover via the global shortcut reads the latest pasteboard value if it is plain text; opening via a menu-bar click never reads the clipboard;
- images, file lists, URLs represented only as objects, and other non-text values are ignored;
- surrounding whitespace is trimmed while internal whitespace is preserved;
- empty text is ignored;
- normalized text equal to the current input does not create another request; and
- eligible new text is inserted and translated immediately.

To prevent accidental API spending on copied documents, text longer than 500 Unicode characters is inserted but not automatically submitted. The UI explains that the automatic limit was reached and requires the user to press Enter. Manual input is not capped at 500 characters; it remains subject to provider limits.

Reading the clipboard only on shortcut invocation (and never on a menu-bar click) keeps ordinary copy operations from silently triggering paid translation requests.

### 7.4 Direction detection

For the first release, input containing meaningful Han-script content resolves to Chinese-to-English; otherwise it resolves to English-to-Chinese. The direction control lets the user override this result before submitting or resubmit with the corrected direction.

The detection is intentionally encapsulated by `DirectionResolver`. Additional language detection strategies can replace or extend it when more languages are exposed.

## 8. Error handling

Each provider owns an independent state: `unconfigured`, `idle`, `loading`, `success`, or `failure`. One provider's failure never hides or invalidates the other provider's successful result.

- Missing configuration shows a “Needs configuration” state with an entry to the relevant Settings section and sends no request.
- HTTP 401 or 403 shows an invalid-credential message and preserves the input.
- HTTP 429 shows a rate-limit message. The application does not automatically retry paid requests.
- Offline and timeout failures show a provider-specific retry action.
- An LLM structured-response failure falls back to usable text when possible.
- Copy failures leave the content visible and show a short accessible error state.

Retries are always provider-specific. Retrying Google does not resend the LLM request and vice versa.

## 9. Settings and storage

### 9.1 General

The General section contains:

- Launch at Login — default off;
- Global Shortcut — default off; and
- Read Clipboard and Translate on Open — default off.

### 9.2 Translation services

The Services section contains:

- Google Cloud Translation API key;
- LLM Base URL;
- LLM API key; and
- LLM model name.

Each provider has a Test Connection action. The UI states that this action makes one small real API request and may incur provider charges.

### 9.3 Prompt presets

The Prompts section contains editable General and Technology & R&D system prompts, independent restore-default actions, and the default-preset selector.

### 9.4 Storage rules

Google and LLM API keys are stored only in macOS Keychain with the `WhenUnlockedThisDeviceOnly` accessibility class. Base URL, model name, prompts, preset selection, shortcut, and Boolean settings are stored in `UserDefaults`.

The implementation is a fixed Data Protection Keychain adapter. Every query sets `kSecUseDataProtectionKeychain = true`, omits `kSecAttrAccessGroup`, and uses service `com.instanttranslation.macos.credentials.v2`. The default application-identifier group therefore remains app-only; Keychain Sharing is not enabled. There is no file-based fallback, signing-mode selection, or runtime migration.

Older file-based items are intentionally not read, modified, or deleted. Existing users re-enter keys once in Settings; after verifying the new entries work, they may delete the old items manually in Keychain Access. Non-sensitive Boolean presence hints live in `UserDefaults` only to render configuration status; requests always read the real matching Keychain item.

The application never persists:

- clipboard contents;
- source text;
- translations or rationales;
- query history;
- pronunciation data; or
- generated audio.

Application exit clears the current in-memory session.

### 9.5 Signing and GitHub Release distribution

Release tooling has one direct-distribution path: it requires `DEVELOPMENT_TEAM`, a Developer ID Application `CODE_SIGN_IDENTITY`, and a `NOTARYTOOL_PROFILE` for release packaging. It signs with Hardened Runtime and a secure timestamp, verifies the actual signature authority, Team ID, and app identifiers, creates a pre-notary ZIP, waits for notarization, staples and validates the ticket, assesses the app with Gatekeeper, then emits the final ZIP and `SHA256SUMS`.

This app has no restricted capabilities, so Developer ID distribution does not need an embedded provisioning profile. The signed entitlement set contains only the application identifier and team identifier, and explicitly rejects Keychain Sharing groups. Published releases are expected to open normally through Gatekeeper; documentation does not instruct users to disable Gatekeeper or use `xattr`.

## 10. Security, privacy, and permissions

The first release requests no Accessibility, Screen Recording, Microphone, or Automation permissions. Future selection, OCR, or voice-input features request their permissions only when enabled or invoked.

Diagnostic logs contain only provider identity, HTTP status category, duration, and an anonymous request ID. Logs never contain source text, translated text, rationale, prompt content, API keys, Authorization headers, complete URLs with query parameters, clipboard data, or audio.

All remote traffic uses TLS. Provider icons are bundled and chosen from a fixed hostname mapping, avoiding remote icon downloads and tracking.

The product has no analytics, telemetry, account system, resident HTTP server, or background polling.

## 11. Extensibility constraints

Future features must extend the declared contracts rather than add provider or permission logic to the popover:

- Selection translation adds an `InputSource` implementation and its own permission/onboarding flow.
- OCR adds an `InputSource` implementation backed by ScreenCaptureKit and Vision.
- Additional languages extend `LanguageCatalog`, direction detection, settings, and provider capability matrices.
- Additional translation services implement `TranslationProvider`.
- Pronunciation-capable providers populate optional `Pronunciation` records.
- TTS implements `SpeechProvider` and remains lazily instantiated.

Extension points do not imply a runtime plugin ABI. A dynamic plugin system is deferred until there is a concrete distribution and security requirement.

## 12. Testing and acceptance

### 12.1 Automated tests

Unit tests cover:

- Chinese/English direction resolution and manual override;
- clipboard normalization, content-type filtering, duplicate suppression, and the 500-character automatic-submit threshold;
- prompt selection and restoring defaults;
- provider-logo hostname mapping and generic fallback;
- LLM structured parsing and plain-text degradation;
- request-ID protection against late responses;
- independent provider retry behavior; and
- log redaction.

Network integration tests use local stub transports and consume no real API quota. They cover parallel completion in either order, partial failure, missing configuration, 401/403, 429, offline, timeout, cancellation, late responses, invalid JSON, and LLM plain-text fallback.

UI tests cover menu-bar opening, immediate focus, outside-click dismissal, direction override, independent copy actions and success feedback, clipboard-on-shortcut behavior, and settings persistence.

Security tests verify that secrets are present only in Keychain and absent from `UserDefaults`, logs, errors, and request URLs. Storage tests assert the fixed Data Protection query shape, v2 service, absent explicit access group, and no fallback or migration. Script tests verify the Developer ID/notarization sequence with fake external tools; a real release additionally validates the signed artifact and notarization result on the release machine.

### 12.2 Manual and performance acceptance

The release is accepted when:

- macOS 15 light, dark, Increase Contrast, and Reduce Transparency appearances remain legible;
- the main flow is keyboard-operable and all icon-only controls have VoiceOver labels;
- a release build left idle for 60 seconds uses no more than 50 MB resident memory;
- idle CPU is effectively zero and no polling or persistent network connection exists;
- opening and closing the popover 500 times does not cause sustained memory growth;
- 200 stub translations do not cause sustained memory growth;
- a warm popover appears within a 100 ms target and accepts typing immediately;
- a single provider failure leaves the other result visible and copyable; and
- the first release never prompts for Accessibility, Screen Recording, or Microphone permission.

Real-provider tests are manual developer tests. They do not run in CI and their credentials are not committed or persisted outside Keychain.

## 13. First-release success criteria

The first release succeeds if a developer can click the menu-bar icon, type or automatically import a copied specialized term, and independently compare a Google translation with a concise terminology-aware LLM answer without opening a browser, while the application remains unobtrusive, private, native, and within the 50 MB idle-memory target.

## 14. Phase 2 TODO — Native capability expansion

The following Phase 2 candidates capture the parts of MoePeek that are useful to study while preserving Instant Translation's narrower security, testing, and module boundaries. MoePeek is an AGPL-3.0 project; these items describe product and architectural ideas only. Implementation must be original unless the project deliberately adopts compatible licensing obligations.

- [ ] **Introduce a dedicated non-activating result panel for selection and OCR workflows.** Keep the first-release menu-bar popover for manual input. A selection-triggered result must appear without stealing focus from the source application; a user-invoked input surface may activate the application and focus its editor. Outside-click and Escape dismissal, multi-display positioning, optional pinning, and focus restoration require AppKit-level tests.
- [ ] **Add selection translation as a permission-gated `InputSource`.** Evaluate a layered acquisition strategy of Accessibility first, application-specific adapters only where justified, and simulated copy as the final fallback. The clipboard fallback must preserve every pasteboard item and type, serialize concurrent grabs, avoid returning stale content, detect a real user copy during capture, and restore the old clipboard only when no external modification occurred.
- [ ] **Add native OCR as a permission-gated `InputSource`.** Keep screen acquisition behind an adapter so ScreenCaptureKit and the system interactive capture flow can be evaluated independently. Use Vision for local recognition, automatically clean temporary image data, release large image objects promptly, support cancellation, and request Screen Recording access only when OCR is first invoked or explicitly enabled.
- [ ] **Expand the provider registry without coupling providers to Settings UI or credential storage.** Preserve independent per-provider states, provider-specific retry and copy actions, and request-generation protection. Evaluate streaming output and multiple model slots only after measuring their UI, memory, and cancellation costs. New providers continue to implement the translation contract while configuration, credentials, and presentation remain separate modules.
- [ ] **Expand languages through catalog data and capability matrices.** Add BCP 47 metadata, localized names, direction-detection strategies, provider-specific language mappings, and unsupported-pair behavior without introducing language-specific branches into the popover or provider coordinator.
- [ ] **Render optional pronunciation data.** Providers that can supply IPA, Pinyin, or another named scheme populate `Pronunciation` records. Missing pronunciation remains a normal result rather than an error, and no pronunciation content is persisted.
- [ ] **Add lazy TTS through `SpeechProvider` and a separate speech coordinator.** Playback uses `TranslationResult.speakableText` or its primary translation, never makes `TranslationResult` own a player or audio file, and instantiates speech frameworks only after the user requests playback. Start with Apple system speech; evaluate cloud speech providers separately.
- [ ] **Add permission onboarding and recovery per capability.** Accessibility and Screen Recording must have independent rationale, request, status, and recovery flows. Enabling one capability must not require the other's permission. Release-update testing must explicitly cover whether ad-hoc identity changes require the user to grant permissions again.
- [ ] **Evaluate Sparkle only after the GitHub Release pipeline is stable.** If adopted, publish a signed appcast and verify update archives with a dedicated Ed25519 key. Sparkle signing does not replace macOS code signing, notarization, checksum publication, or the documented Gatekeeper override path.
- [ ] **Retain current quality and privacy gates while adding these capabilities.** Every new adapter receives deterministic unit and integration tests, permission APIs are statically scanned, source text and generated audio remain out of logs and persistent storage, and idle CPU/memory plus repeated open/close and capture cycles are measured before release.

Phase 2 explicitly does not adopt MoePeek's migration of API credentials into `UserDefaults`, its non-notarized development-certificate distribution as a general signing solution, or direct source copying under an incompatible license.
