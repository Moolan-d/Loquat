# Free Ad-Hoc Release and Keychain Design

## Goal

Make Loquat permanently distributable without a paid Apple Developer membership while keeping the runtime and release architecture small, keeping API keys out of preferences, and avoiding application-triggered work during startup.

## Product decision

Loquat supports one distribution model: an ad-hoc-signed, non-notarized ZIP published with a SHA-256 checksum. Developer ID, notarization, provisioning profiles, signing-mode switches, and future paid-distribution branches are out of scope.

The unavoidable trade-off is explicit: Gatekeeper may require one per-install user authorization, and the legacy macOS Keychain ACL may ask again after an app update. The project must not describe the artifact as trusted, notarized, or automatically accepted by Gatekeeper.

## Credential storage

`KeychainCredentialStore` remains the only production credential adapter and continues conforming to `CredentialStoring`. It uses the macOS file-based Keychain exclusively, with generic-password items identified by:

- service `com.instanttranslation.macos.credentials.v3`;
- provider account `google-api-key` or `llm-api-key`; and
- no `kSecUseDataProtectionKeychain`, `kSecAttrAccessGroup`, or `kSecAttrAccessible` attribute.

The v3 service is a clean namespace. Loquat never reads, migrates, updates, or deletes v1/v2 items. Existing users enter each credential once after installing this release and may remove older items manually in Keychain Access.

The public `AppPreferences.googleCredentialConfigured` and `llmCredentialConfigured` properties remain unchanged, but their serialized JSON keys become `googleCredentialV3Configured` and `llmCredentialV3Configured`. An older snapshot containing v1/v2 presence keys therefore decodes both hints as `false` while retaining unrelated preferences. Startup immediately and correctly presents the new v3 store as unconfigured without probing either old Keychain backend.

The store keeps its update-first/add-on-missing/duplicate-add-retry behavior and sanitized `OSStatus` errors. API key values remain absent from `UserDefaults`, logs, errors, URLs, tests, and release artifacts.

## Startup and first-use behavior

The existing deferred-access architecture remains:

- application startup performs zero Keychain operations;
- startup configuration status comes from v3-specific, non-sensitive Boolean presence hints in `AppPreferences`;
- opening Settings loads the real credentials because the user explicitly requested credential UI;
- each translation provider reads its own credential immediately before its request; and
- a failed or denied Keychain read is never treated as proof that the credential is missing.

No migration probe, first-launch credential check, permission onboarding window, or automatic Keychain retry is added. This confines application-triggered Keychain interaction to Settings and translation requests. Gatekeeper authorization occurs before the process starts and cannot be removed without Developer ID notarization.

## Packaging and release

`scripts/package-app.sh` takes no signing credentials and has no signing mode. It builds the release executable, assembles `build/Loquat.app`, and applies one ad-hoc signature:

```bash
codesign --force --deep --sign - "$APP"
```

No entitlements plist, Hardened Runtime option, secure timestamp, provisioning profile, Developer ID identity, or notary credential is used. A small verifier runs `codesign --verify --deep --strict` and confirms `codesign -dvv` reports `Signature=adhoc` and `TeamIdentifier=not set`.

`scripts/package-release.sh` calls `package-app.sh`, creates `build/release/Loquat-macOS.zip` with `ditto`, writes `build/release/SHA256SUMS`, and verifies the checksum before succeeding. It never calls `notarytool`, `stapler`, or `spctl`.

The Developer ID entitlement template, entitlement materializer, and Developer ID verifier are deleted. Historical architecture documents remain for context but receive a prominent superseded notice pointing here.

## Installation documentation

Installation instructions lead with the least invasive flow:

1. download the ZIP only from GitHub Releases and verify `SHA256SUMS`;
2. drag `Loquat.app` to `/Applications`;
3. try Control-click or right-click → Open;
4. if macOS still blocks the app, use System Settings → Privacy & Security → Open Anyway; and
5. use `xattr -dr com.apple.quarantine /Applications/Loquat.app` only as the final documented fallback, without `sudo` by default.

Documentation states that these steps bypass Gatekeeper trust for this specific downloaded app and do not prove that the software was notarized. It never recommends disabling Gatekeeper globally.

## Verification

- Storage tests assert the v3 service, v3-specific presence serialization, and absence of Data Protection, access-group, and accessibility attributes on every SecItem operation.
- Existing app tests continue proving zero credential reads during startup and on-demand reads from Settings/providers.
- Shell tests prove packaging requires no certificate environment, uses only ad-hoc signing, produces a clean ZIP/checksum, and never invokes notarization tools.
- The full Swift suite, shell regression scripts, release build, real local ad-hoc package, code-signature verification, checksum verification, stale-term scan, and `git diff --check` must pass.
- Manual release acceptance records Gatekeeper behavior on a freshly downloaded ZIP separately from application-triggered Keychain behavior; local builds cannot simulate download quarantine faithfully.

## Primary references

- Apple TN3137, “On Mac keychains”: <https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains>
- Apple `kSecUseDataProtectionKeychain`: <https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain>
- Apple Developer ID overview (documents the paid trusted alternative that this design excludes): <https://developer.apple.com/developer-id/>
