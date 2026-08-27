# Streamlined Keychain Design

## Goal

Replace Loquat's signing-aware, dual-Keychain runtime with one Data Protection Keychain implementation, defer secret reads until user intent requires them, and make the direct-distribution pipeline Developer ID signed and notarized.

## Constraints

- API keys remain only in macOS Keychain; no secret value may enter `UserDefaults`, logs, errors, URLs, or release artifacts.
- The minimum platform remains macOS 15.
- Google and LLM keys remain separate generic-password items.
- Translation requests continue reading the relevant key at request time.
- The application has no credential-sharing app or extension, so it does not claim a Keychain Sharing group.
- Existing file-based items are never read or migrated automatically. Users re-enter credentials once in the new release.
- Old file-based items are left intact so the new release never triggers their ACL prompts. Users may remove them manually.

## Credential storage

`KeychainCredentialStore` is the only production credential adapter. Every SecItem query contains:

- `kSecClassGenericPassword`;
- service `com.instanttranslation.macos.credentials.v2`;
- the provider-specific account; and
- `kSecUseDataProtectionKeychain = true`.

Queries omit `kSecAttrAccessGroup`, allowing Keychain Services to select the app's default application-identifier group. Writes retain `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Existing update/add race handling and sanitized `OSStatus` errors remain.

`CredentialStoring` remains the external seam used by providers, settings, and tests. `KeychainBackend`, the migration types, signing-mode configuration, and the ad-hoc probe are removed.

## Credential presence metadata

`AppPreferences` gains `googleCredentialConfigured` and `llmCredentialConfigured`. These values are non-sensitive UI hints, not authorization or request inputs.

- Startup builds `ProviderAvailability` from the hints plus non-secret LLM configuration.
- Successful settings saves derive and persist the hints from the proposed credential values.
- A failed save restores both Keychain values and the previous preference snapshot.
- Opening Settings reads both real Keychain items and reconciles the in-memory fields and presence display.
- Translation providers always read Keychain and treat missing values as unconfigured regardless of the hints.

Legacy preference snapshots decode both hints as `false`, intentionally asking existing users to configure the new v2 store.

## Startup and settings lifecycle

Application composition performs no Keychain operations. `SettingsViewModel` starts with empty secret fields and a not-loaded credential state. `SettingsWindowController` asks the model to load credentials before the first presentation and reloads when a previously constructed window is reopened.

The global shortcut is registered from the ordinary preferences snapshot, not from secret-aware settings state. With signing resolution and migration removed, application construction is nonthrowing and `ApplicationStartupCoordinator` is deleted. `AppDelegate` owns and starts the container directly.

## Signing and release

Runtime code never inspects signing mode or access-group strings. Direct release packaging has one supported mode:

1. build the app;
2. sign with a Developer ID Application identity, Hardened Runtime, and secure timestamp;
3. verify the signature authority, Team ID, application identifier, and absence of Keychain Sharing;
4. archive for notarization;
5. submit with `xcrun notarytool submit --wait` using a stored Keychain profile;
6. staple and validate the ticket;
7. assess the app with Gatekeeper; and
8. create the final ZIP and checksum.

The entitlement template retains `com.apple.application-identifier` and `com.apple.developer.team-identifier` but removes `keychain-access-groups`. This app has no restricted capability, so its Developer ID distribution does not embed a provisioning profile. If a future restricted capability requires one, it must be designed as a separate distribution change. Ad-hoc packaging is not a supported credential-capable distribution path.

## Verification

- Unit tests assert every SecItem operation targets Data Protection Keychain, uses the v2 service, and omits explicit access groups.
- Settings tests prove construction does not read Keychain, presentation does, and successful saves update presence hints.
- Container tests prove startup makes no credential reads while provider requests still do.
- Script tests use fake signing/notary tools to verify ordering and fail-closed behavior without external credentials.
- The complete Swift test suite and packaging/signing regression scripts must pass.
