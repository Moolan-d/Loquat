# Streamlined Keychain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Loquat's dual Keychain runtime with one on-demand Data Protection Keychain flow and a Developer ID notarized release pipeline.

**Architecture:** Keep `CredentialStoring` as the small application seam while making `KeychainCredentialStore` a fixed Data Protection adapter. Startup consumes non-secret presence hints, Settings reconciles real secrets only when opened, providers read secrets per request, and release packaging is always Developer ID signed and notarized.

**Tech Stack:** Swift 6.2, Swift Package Manager, AppKit/SwiftUI, Security.framework SecItem APIs, bash, codesign, notarytool, stapler, XCTest.

**Spec:** `docs/superpowers/specs/2026-08-27-streamlined-keychain-design.md`

## Global Constraints

- Minimum platform remains macOS 15.
- Secret values remain exclusively in Keychain and request headers.
- Existing file-based Keychain items are never queried, migrated, or deleted.
- Runtime code has no signing-mode or access-group configuration.
- Direct releases require Developer ID, Hardened Runtime, secure timestamp, provisioning, notarization, stapling, and Gatekeeper assessment.

---

### Task 1: Fixed Data Protection credential adapter

**Files:**
- Modify: `Tests/InstantTranslationInfrastructureTests/CredentialStorageAmendmentTests.swift`
- Modify: `Tests/InstantTranslationInfrastructureTests/StorageTests.swift`
- Modify: `Sources/InstantTranslationInfrastructure/Storage/CredentialStore.swift`

**Interfaces:**
- Consumes: Security.framework `SecItem*` functions.
- Produces: `KeychainCredentialStore(service: String = "com.instanttranslation.macos.credentials.v2")`, conforming to the unchanged `CredentialStoring` interface.

- [ ] **Step 1: Replace backend/migration tests with the fixed query contract**

Add a test that constructs `KeychainCredentialStore(service: service, client: client)`, exercises write/read/delete, and checks every recorded query:

```swift
XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true)
XCTAssertNil(query[kSecAttrAccessGroup as String])
XCTAssertEqual(query[kSecAttrService as String] as? String, service)
```

Also assert `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` on add. Remove all migration tests and their migration-only fakes.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter CredentialStorageAmendmentTests`

Expected: compilation failure because the desired initializer does not exist, or assertion failure because access groups are still emitted.

- [ ] **Step 3: Make the adapter fixed and remove migration production code**

Delete `KeychainBackend`, `CredentialMigrationError`, and `CredentialMigrator`. Change both store initializers to omit `backend`, default the service to v2, and make `baseQuery` always add:

```swift
kSecUseDataProtectionKeychain as String: true
```

Do not add `kSecAttrAccessGroup`.

- [ ] **Step 4: Update live storage tests and verify GREEN**

Update explicit initializers in `StorageTests.swift` to the new interface. Run:

```bash
swift test --filter 'CredentialStorageAmendmentTests|StorageTests'
```

Expected: all selected tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/InstantTranslationInfrastructure/Storage/CredentialStore.swift Tests/InstantTranslationInfrastructureTests/CredentialStorageAmendmentTests.swift Tests/InstantTranslationInfrastructureTests/StorageTests.swift
git commit -m "refactor(storage): use one data protection keychain"
```

### Task 2: Presence hints and deferred settings credential loading

**Files:**
- Modify: `Sources/InstantTranslationInfrastructure/Storage/PreferencesStore.swift`
- Modify: `Sources/InstantTranslationApp/Settings/SettingsViewModel.swift`
- Modify: `Sources/InstantTranslationApp/Settings/SettingsWindowController.swift`
- Modify: `Tests/InstantTranslationInfrastructureTests/StorageTests.swift`
- Modify: `Tests/InstantTranslationAppTests/SettingsViewModelTests.swift`
- Modify: `Tests/InstantTranslationAppTests/SettingsPresentationTests.swift`
- Modify: `Tests/InstantTranslationAppTests/Support/SettingsFakes.swift`

**Interfaces:**
- Produces: `AppPreferences.googleCredentialConfigured: Bool`, `AppPreferences.llmCredentialConfigured: Bool`.
- Produces: `CredentialAccessState.notLoaded`, `SettingsViewModel.loadCredentials()`.
- Consumes: unchanged `CredentialStoring` read/write/delete methods.

- [ ] **Step 1: Add failing preference round-trip and legacy-default tests**

Add literals proving both presence flags survive encode/decode and old JSON missing them decodes both as `false`.

- [ ] **Step 2: Run the storage tests and verify RED**

Run: `swift test --filter StorageTests`

Expected: compilation failure because the two properties do not exist.

- [ ] **Step 3: Add the two Codable preference fields**

Default both to `false`, decode each with the existing per-field fallback, and leave secret values absent from the preferences model.

- [ ] **Step 4: Add failing tests for deferred load and presence updates**

Extend `MemoryCredentialStore` with read counters. Add tests proving:

```swift
let model = await makeModel(credentials: credentials)
XCTAssertEqual(credentials.readCallCount, 0)
XCTAssertEqual(model.credentialAccessState, .notLoaded)
model.loadCredentials()
XCTAssertEqual(credentials.readCallCount, 2)
```

Add a save test that enters/removes keys and then asserts the stored `AppPreferences` presence flags match the successfully persisted secrets.

- [ ] **Step 5: Run focused settings tests and verify RED**

Run: `swift test --filter SettingsViewModelTests`

Expected: compilation failure for `.notLoaded`/`loadCredentials`, or behavior failure because model creation reads twice.

- [ ] **Step 6: Implement deferred loading and presence persistence**

Make `SettingsViewModel.make` initialize empty secret fields with `.notLoaded`. Rename `reloadCredentials()` to `loadCredentials()` and make it publish `.loaded` or `.unavailable`. In `validatedSettings`, derive both flags from trimmed key values before saving preferences.

Treat `.notLoaded` as non-editable/non-saveable until Settings presentation loads it. Keep current unknown-value protection and rollback behavior.

- [ ] **Step 7: Trigger real loading from Settings presentation**

At the start of `showSettings(_:)`, call `model.loadCredentials()` before constructing or presenting the window. Update the reload button action and tests to use the new method.

- [ ] **Step 8: Verify GREEN and commit**

Run:

```bash
swift test --filter 'StorageTests|SettingsViewModelTests|SettingsPresentationTests'
```

Expected: all selected tests pass.

```bash
git add Sources/InstantTranslationInfrastructure/Storage/PreferencesStore.swift Sources/InstantTranslationApp/Settings Tests/InstantTranslationInfrastructureTests/StorageTests.swift Tests/InstantTranslationAppTests/SettingsViewModelTests.swift Tests/InstantTranslationAppTests/SettingsPresentationTests.swift Tests/InstantTranslationAppTests/Support/SettingsFakes.swift
git commit -m "refactor(settings): load credentials on demand"
```

### Task 3: Remove credential work from application startup

**Files:**
- Modify: `Sources/InstantTranslationApp/Application/ApplicationContainer.swift`
- Modify: `Sources/InstantTranslationApp/Application/AppDelegate.swift`
- Modify: `Sources/InstantTranslation/main.swift`
- Delete: `Sources/InstantTranslationApp/Application/ApplicationCredentialConfiguration.swift`
- Delete: `Sources/InstantTranslationApp/Application/ApplicationStartupCoordinator.swift`
- Delete: `Sources/InstantTranslationApp/Application/AdHocKeychainRoundTripProbe.swift`
- Delete: `Tests/InstantTranslationAppTests/SigningModeConfigurationTests.swift`
- Delete: `Tests/InstantTranslationAppTests/ApplicationStartupCoordinatorTests.swift`
- Delete: `Tests/InstantTranslationAppTests/AdHocKeychainProbeTests.swift`
- Modify: `Tests/InstantTranslationAppTests/AppShellTests.swift`

**Interfaces:**
- Consumes: presence flags from Task 2.
- Produces: nonthrowing `ApplicationContainer.make() async -> ApplicationContainer` and direct AppDelegate ownership.

- [ ] **Step 1: Add a failing container test for zero startup credential reads**

Construct the container with a counting `MemoryCredentialStore` and preferences whose presence flags are true. Assert zero credential reads after construction and assert the resulting `ProviderAvailability` reflects the hints.

- [ ] **Step 2: Run the test and verify RED**

Run: `swift test --filter AppShellTests`

Expected: the counting store reports four startup reads.

- [ ] **Step 3: Simplify container composition**

Construct `KeychainCredentialStore()` directly. Build `ProviderAvailability` from `AppPreferences` presence flags. Initialize Settings without reading secrets. Register the startup shortcut from the ordinary preference snapshot rather than `settingsViewModel.googleAPIKey` or other credential-backed state.

- [ ] **Step 4: Remove runtime signing, migration, probe, and failure coordinator**

Delete the three production files and three matching test files. Remove the command-line probe branch from `main.swift`. Let `AppDelegate` create/start a nonthrowing container directly and retain it for termination.

- [ ] **Step 5: Verify GREEN and commit**

Run:

```bash
swift test --filter 'AppShellTests|SettingsViewModelTests|TranslationPresentationTests'
```

Expected: all selected tests pass and the removed test suites no longer compile into the package.

```bash
git add Sources/InstantTranslation Sources/InstantTranslationApp Tests/InstantTranslationAppTests
git commit -m "refactor(app): remove keychain work from startup"
```

### Task 4: Developer ID and notarization-only release pipeline

**Files:**
- Modify: `Config/InstantTranslation.entitlements.template.plist`
- Modify: `scripts/materialize-entitlements.sh`
- Modify: `scripts/package-app.sh`
- Modify: `scripts/package-release.sh`
- Modify: `scripts/verify-signed-app.sh`
- Modify: `scripts/test-packaging-amendment.sh`
- Modify: `scripts/test-signing-gates.sh`
- Delete: `scripts/materialize-signing-info.sh`
- Delete: `scripts/verify-profile-keychain-group.sh`

**Interfaces:**
- `package-app.sh` requires `DEVELOPMENT_TEAM`, `CODE_SIGN_IDENTITY`, and `PROVISIONING_PROFILE` and outputs the signed app path.
- `package-release.sh` consumes the signed app plus notary credentials through `xcrun notarytool` and outputs the final notarized ZIP.

- [ ] **Step 1: Rewrite script tests for one signed/notarized path**

Use fake `codesign`, `xcrun`, and package-app executables to assert observable behavior: package creation is invoked without `SIGNING_MODE`, notary submission receives the pre-notary archive, stapling/validation occur before the final ZIP, and any failed command stops publication.

Update entitlement fixtures to contain only application identifier and team identifier. Verify the profile application identifier rather than an explicit Keychain group.

- [ ] **Step 2: Run script tests and verify RED**

Run:

```bash
bash scripts/test-signing-gates.sh
bash scripts/test-packaging-amendment.sh
```

Expected: failures because current scripts require ad-hoc mode and explicit Keychain groups.

- [ ] **Step 3: Remove Keychain Sharing and runtime signing metadata**

Delete `keychain-access-groups` from the entitlement template and materializer. Delete `materialize-signing-info.sh` and `verify-profile-keychain-group.sh`. Remove all `InstantTranslationSigningMode` and `InstantTranslationKeychainAccessGroup` plist writes.

- [ ] **Step 4: Make app packaging always Developer ID signed**

Remove the `SIGNING_MODE` switch. Keep exact Team/application-identifier/profile checks. Sign with:

```bash
codesign --force --deep --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$CODE_SIGN_IDENTITY" "$APP"
```

Update `verify-signed-app.sh` to verify only Team ID and application identifier, and reject any unexpected `keychain-access-groups` entitlement.

- [ ] **Step 5: Add notarization, stapling, and assessment**

Create a pre-notary ZIP, submit it with `xcrun notarytool submit --wait`, staple and validate the app, run `spctl --assess --type execute`, then create the final ZIP and SHA-256 checksum. Accept credentials through a keychain profile or the standard notarytool environment configured by the caller; never echo them.

- [ ] **Step 6: Verify GREEN and commit**

Run both script test commands again; expected: both print their success marker and exit 0.

```bash
git add Config scripts
git commit -m "build(release): require notarized Developer ID artifacts"
```

### Task 5: Documentation and full verification

**Files:**
- Modify: `README.md`
- Modify: `README_zh.md`
- Modify: `docs/superpowers/specs/2026-08-12-instant-translation-design.md`
- Create: `docs/superpowers/specs/2026-08-27-streamlined-keychain-design.md`
- Create: `docs/superpowers/plans/2026-08-27-streamlined-keychain.md`

**Interfaces:** None; documents must match the implemented commands and credential semantics.

- [ ] **Step 1: Update user and developer documentation**

Document the v2 service, one-time credential re-entry, absence of startup Keychain reads, Developer ID/notarized distribution, and new release environment inputs. Remove ad-hoc installation and automatic migration claims.

- [ ] **Step 2: Run placeholder and stale-term scans**

Run:

```bash
rg -n 'TBD|TODO|SIGNING_MODE|fileBased|CredentialMigrator|InstantTranslationSigningMode|InstantTranslationKeychainAccessGroup|com.instanttranslation.macos.credentials`' README.md README_zh.md Sources Tests Config scripts docs/superpowers/specs/2026-08-27-streamlined-keychain-design.md
```

Expected: no stale runtime/signing terms; any historical design hits are explicitly marked superseded.

- [ ] **Step 3: Run complete verification**

Run:

```bash
swift test
bash scripts/test-signing-gates.sh
bash scripts/test-packaging-amendment.sh
swift build -c release
git diff --check
```

Expected: all commands exit 0; Swift test reports zero failures; diff check emits no output.

- [ ] **Step 4: Review requirements and commit**

Confirm each design requirement has a corresponding diff and test. Then:

```bash
git add README.md README_zh.md docs
git commit -m "docs(security): describe on-demand keychain architecture"
```
