# AGENTS.md

Loquat, a macOS menu-bar translation app. Swift 6.2, macOS 15+, no third-party dependencies. Commits follow Conventional Commits; version bumps use `chore(release): bump version to x.y.z`.

## Commands

```bash
swift test                              # run the full test suite
swift run InstantTranslation            # run from source
bash scripts/package-app.sh              # package build/Loquat.app
bash scripts/package-release.sh          # package release/Loquat-macOS.zip + SHA256SUMS
```

## Architecture

Five targets with compile-time-enforced boundaries: `Core ← Infrastructure`, `Core ← Feature`, and `{Core, Infrastructure, Feature} ← App ← executable`.

- **Core** imports Foundation only — no AppKit, SwiftUI, network, or disk.
- **App layer** holds no business decisions; **Feature layer** never constructs providers directly; **Infrastructure** holds no UI state.
- Sole composition root is `ApplicationContainer.make`. LLM config is a closure (read per request); `ProviderAvailability` is published from non-sensitive startup hints and refreshed after settings saves.
- Deep dives: `docs/architecture.md`, `docs/runtime-keychain-architecture.md`, `docs/superpowers/specs/`.

## Invariants to preserve

Easiest to break when editing; highest priority:

1. **Cancellation + requestID double gate.** Cancellation stops work; `requestID` re-checks reject late events. Both are required.
2. **"More contexts" is an independent request.** It shares no task group with the initial translation and must not affect already-delivered results on failure.
3. **Fallback model is never persisted.** `LLMDefaultModel` resolves only on the request path; persisting it creates zombie model names.
4. **Credentials pass through `EndpointPolicy` first.** Non-HTTPS and non-loopback base URLs never send credentials.
5. **Keys live only in the Keychain.** Never in UserDefaults, logs, or request URLs; no `SecItem*` calls during startup (this is what keeps startup prompt-free).
6. **Clipboard is read only on shortcut invocation.** A menu-bar click never reads the clipboard.
7. **Preference decoding falls back per field.** `AppPreferences.init(from:)` must not degrade to a full reset.

## Tests

One test target per module. Infra tests use `StubHTTPTransport`; App tests use Settings fakes to replace real system interaction — never issue real network requests. Core contract changes ripple upward; run `swift test` first to see the blast radius.

## Terminology

Follow `CONTEXT.md`: `clipboard-on-shortcut` (not clipboard-on-open), `shortcut invocation`, `menu-bar click`. Keep one name per concept across the repo; update `CONTEXT.md` when domain terms change.
