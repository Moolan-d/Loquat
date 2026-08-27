# Free Ad-Hoc Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Loquat's paid Developer ID/Data Protection distribution architecture with one certificate-free ad-hoc release path and one file-based Keychain adapter while keeping startup free of Keychain access.

**Architecture:** Keep the existing `CredentialStoring` seam, non-sensitive presence hints, deferred Settings load, and per-request credential reads. Change the production adapter to one v3 file-based Keychain namespace, and replace Developer ID/notarization packaging with unconditional ad-hoc signing plus ZIP/checksum publication.

**Tech Stack:** Swift 6.2, Swift Package Manager, Security.framework SecItem APIs, AppKit/SwiftUI, Bash 3.2, `codesign`, `ditto`, `shasum`, XCTest.

**Spec:** `docs/superpowers/specs/2026-08-27-free-adhoc-release-design.md`

## Global Constraints

- Minimum platform remains macOS 15.
- API key values remain exclusively in macOS Keychain and request headers; never store them in `UserDefaults`.
- Production has exactly one Keychain implementation and exactly one release mode.
- Credential service is exactly `com.instanttranslation.macos.credentials.v3`.
- Serialized presence keys are exactly `googleCredentialV3Configured` and `llmCredentialV3Configured`; old presence keys decode as absent.
- Never read, migrate, update, or delete v1/v2 credential items.
- Application startup performs zero Keychain operations.
- Do not add `kSecUseDataProtectionKeychain`, `kSecAttrAccessGroup`, `kSecAttrAccessible`, a signing-mode flag, a migration coordinator, or a startup probe.
- Release packaging takes no certificate, Team ID, provisioning-profile, or notarization input.
- Release artifacts are ad-hoc signed and explicitly documented as non-notarized.
- Do not recommend disabling Gatekeeper globally or using `sudo` in the default recovery command.
- Preserve the current update/add race handling and sanitized `KeychainError` behavior.

---

### Task 1: One v3 file-based Keychain adapter

**Files:**
- Modify: `Sources/InstantTranslationInfrastructure/Storage/CredentialStore.swift:59`
- Modify: `Sources/InstantTranslationInfrastructure/Storage/PreferencesStore.swift:13`
- Modify: `Tests/InstantTranslationInfrastructureTests/CredentialStorageAmendmentTests.swift:1`
- Modify: `Tests/InstantTranslationInfrastructureTests/StorageTests.swift:151`

**Interfaces:**
- Consumes: unchanged `CredentialStoring.read(_:)`, `write(_:for:)`, and `delete(_:)`.
- Produces: `KeychainCredentialStore(service: String = "com.instanttranslation.macos.credentials.v3")` backed only by the macOS file-based Keychain.
- Produces: unchanged public presence properties serialized as `googleCredentialV3Configured` and `llmCredentialV3Configured`.

- [ ] **Step 1: Replace the Data Protection contract tests with the fixed file-based contract**

In `CredentialStorageAmendmentTests.swift`, replace the three current tests with tests equivalent to:

```swift
func testEveryOperationUsesTheSingleFileBasedV3Namespace() throws {
    let client = RecordingSecItemClient()
    let store = KeychainCredentialStore(client: client)

    try store.write("value", for: .googleAPIKey)
    _ = try store.read(.googleAPIKey)
    try store.delete(.googleAPIKey)

    XCTAssertFalse(client.queries.isEmpty)
    for query in client.queries {
        XCTAssertEqual(
            query[kSecAttrService as String] as? String,
            "com.instanttranslation.macos.credentials.v3"
        )
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "google-api-key")
        XCTAssertNil(query[kSecUseDataProtectionKeychain as String])
        XCTAssertNil(query[kSecAttrAccessGroup as String])
        XCTAssertNil(query[kSecAttrAccessible as String])
    }
}

func testCustomServiceDoesNotAddDataProtectionOnlyAttributes() throws {
    let client = RecordingSecItemClient()
    let store = KeychainCredentialStore(service: "test.service", client: client)

    try store.write("value", for: .llmAPIKey)

    let query = try XCTUnwrap(client.queries.first)
    XCTAssertEqual(query[kSecAttrService as String] as? String, "test.service")
    XCTAssertEqual(query[kSecAttrAccount as String] as? String, "llm-api-key")
    XCTAssertNil(query[kSecUseDataProtectionKeychain as String])
    XCTAssertNil(query[kSecAttrAccessGroup as String])
    XCTAssertNil(query[kSecAttrAccessible as String])
}

func testReadFailureIsReturnedWithoutRetryingAnotherKeychain() {
    let client = RecordingSecItemClient(copyStatus: errSecAuthFailed)
    let store = KeychainCredentialStore(client: client)

    XCTAssertThrowsError(try store.read(.googleAPIKey)) { error in
        XCTAssertEqual(error as? KeychainError, .status(errSecAuthFailed))
    }
    XCTAssertEqual(client.queries.count, 1)
    XCTAssertNil(client.queries[0][kSecUseDataProtectionKeychain as String])
}
```

Keep `RecordingSecItemClient`; it must continue recording update, add, read, and delete dictionaries so the test observes the real query contract.

Add a `StorageTests` regression that decodes a pre-v3 snapshot whose old presence hints are `true` and proves only those hints reset:

```swift
func testPreV3PresenceHintsResetWithoutDiscardingOtherPreferences() throws {
    let legacy = """
    {
      "launchAtLogin": true,
      "googleCredentialConfigured": true,
      "llmCredentialConfigured": true,
      "llmBaseURL": "https://api.openai.com/v1"
    }
    """

    let preferences = try JSONDecoder().decode(
        AppPreferences.self,
        from: Data(legacy.utf8)
    )

    XCTAssertTrue(preferences.launchAtLogin)
    XCTAssertEqual(preferences.llmBaseURL, "https://api.openai.com/v1")
    XCTAssertFalse(preferences.googleCredentialConfigured)
    XCTAssertFalse(preferences.llmCredentialConfigured)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter CredentialStorageAmendmentTests
```

Expected: failures show service v2, `kSecUseDataProtectionKeychain = true`, and `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` are still present; the pre-v3 snapshot still decodes the old presence hints as `true`.

- [ ] **Step 3: Implement the fixed v3 adapter**

In both `KeychainCredentialStore` initializers, change the default service to:

```swift
service: String = "com.instanttranslation.macos.credentials.v3"
```

Make `write(_:for:)` update only the secret bytes:

```swift
let attributes: [String: Any] = [
    kSecValueData as String: Data(value.utf8),
]
```

Make `baseQuery(_:)` exactly:

```swift
private func baseQuery(_ key: CredentialKey) -> [String: Any] {
    [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: key.account,
    ]
}
```

Do not add a backend enum or fallback. Leave the update-first, add-on-`errSecItemNotFound`, duplicate-add retry, delete idempotency, invalid UTF-8 handling, and sanitized status error unchanged.

In `AppPreferences`, add explicit coding keys while preserving the public property names:

```swift
private enum CodingKeys: String, CodingKey {
    case launchAtLogin
    case globalShortcut
    case translateClipboardOnShortcut
    case googleProviderEnabled
    case llmProviderEnabled
    case googleCredentialConfigured = "googleCredentialV3Configured"
    case llmCredentialConfigured = "llmCredentialV3Configured"
    case llmBaseURL
    case llmModel
    case generalPrompt
    case technologyAndRnDPrompt
    case defaultPromptPresetID
}
```

Because the existing decoder already falls back field by field, old serialized presence keys become `false` without resetting unrelated settings. The synthesized encoder writes only the new v3 key names.

- [ ] **Step 4: Simplify the broader storage tests and fakes**

In `StorageTests.swift`:

- delete `testKeychainWritesUseDataProtectionAccessibility`;
- change `insertRawData` to accept only `data`, `service`, and `account`;
- remove `usesDataProtectionKeychain` from `TestSecItemClient.ItemKey`;
- remove `kSecUseDataProtectionKeychain` from inserted fixture dictionaries;
- change `keychainQuery(account:useDataProtectionKeychain:)` to `keychainQuery(account:)` with only class/service/account;
- change cleanup to query and delete only the file-based test service; and
- leave concurrent-write, invalid-data, preference-secrecy, and presence-hint tests intact.

Extend `testCredentialPresenceHintsSurviveSaveAndReloadWithoutSecretValues` to assert the persisted JSON contains both new key names and does not contain the quoted old names:

```swift
XCTAssertTrue(text.contains("\"googleCredentialV3Configured\":true"))
XCTAssertTrue(text.contains("\"llmCredentialV3Configured\":true"))
XCTAssertFalse(text.contains("\"googleCredentialConfigured\""))
XCTAssertFalse(text.contains("\"llmCredentialConfigured\""))
```

The simplified fake key must be:

```swift
private struct ItemKey: Hashable {
    let service: String
    let account: String
}

private func itemKey(from attributes: [String: Any]) -> ItemKey? {
    guard let service = attributes[kSecAttrService as String] as? String,
          let account = attributes[kSecAttrAccount as String] as? String
    else {
        return nil
    }
    return ItemKey(service: service, account: account)
}
```

- [ ] **Step 5: Verify storage, settings, providers, and zero-read startup**

Run:

```bash
swift test --filter 'CredentialStorageAmendmentTests|StorageTests|SettingsViewModelTests|AppShellTests|GoogleTranslationProviderTests|LLMTranslationProviderTests'
```

Expected: all selected tests pass. In particular, `testContainerConstructionUsesPresenceHintsWithoutReadingCredentials` must still report zero reads.

- [ ] **Step 6: Scan for forbidden production query attributes**

Run:

```bash
rg -n 'kSecUseDataProtectionKeychain|kSecAttrAccessGroup|kSecAttrAccessible' Sources
```

Expected: no matches.

- [ ] **Step 7: Commit the storage change**

```bash
git add Sources/InstantTranslationInfrastructure/Storage/CredentialStore.swift Sources/InstantTranslationInfrastructure/Storage/PreferencesStore.swift Tests/InstantTranslationInfrastructureTests/CredentialStorageAmendmentTests.swift Tests/InstantTranslationInfrastructureTests/StorageTests.swift
git commit -m "refactor(storage): use one file based keychain"
```

---

### Task 2: Certificate-free ad-hoc packaging

**Files:**
- Delete: `Config/InstantTranslation.entitlements.template.plist`
- Delete: `scripts/materialize-entitlements.sh`
- Delete: `scripts/verify-signed-app.sh`
- Create: `scripts/verify-adhoc-app.sh`
- Modify: `scripts/package-app.sh`
- Modify: `scripts/package-release.sh`
- Modify: `scripts/test-signing-gates.sh`
- Modify: `scripts/test-packaging-amendment.sh`

**Interfaces:**
- Produces: `scripts/package-app.sh` with no required environment variables; final stdout line is the absolute/derived `Loquat.app` path.
- Produces: `scripts/verify-adhoc-app.sh APP_PATH`, which accepts only a valid ad-hoc signature.
- Produces: `scripts/package-release.sh` with no required environment variables; final stdout line is `build/release/Loquat-macOS.zip` or the matching custom build-root path.

- [ ] **Step 1: Rewrite the signing regression around observable ad-hoc behavior**

Replace the Developer ID assertions in `scripts/test-signing-gates.sh` with a temporary fake toolchain. The fake `swift` must return a fixture binary directory for `--show-bin-path`; the fake `codesign` must log the signing invocation, succeed for `--verify`, and emit controlled `Signature`/`TeamIdentifier` fields for `-dvv`:

```bash
cat >"$FAKE_BIN/swift" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"--show-bin-path"* ]]; then
    echo "$FAKE_RELEASE_BIN"
fi
SCRIPT

cat >"$FAKE_BIN/codesign" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"--verify"* ]]; then
    exit 0
fi
if [[ "$*" == *"-dvv"* ]]; then
    echo "Signature=${FAKE_SIGNATURE:-adhoc}" >&2
    echo "TeamIdentifier=${FAKE_TEAM:-not set}" >&2
    exit 0
fi
echo "$*" >>"$CODESIGN_LOG"
SCRIPT

chmod +x "$FAKE_BIN/swift" "$FAKE_BIN/codesign"
mkdir -p "$FAKE_RELEASE_BIN"
printf 'fixture executable\n' >"$FAKE_RELEASE_BIN/InstantTranslation"
chmod +x "$FAKE_RELEASE_BIN/InstantTranslation"
```

Create a fixture executable at `$FAKE_RELEASE_BIN/InstantTranslation`, run `package-app.sh` with only `PATH`, `FAKE_RELEASE_BIN`, `CODESIGN_LOG`, and `INSTANT_TRANSLATION_BUILD_ROOT`, then assert:

```bash
[[ -d "$BUILD_ROOT/Loquat.app" ]]
[[ "$(cat "$CODESIGN_LOG")" == "--force --deep --sign - $BUILD_ROOT/Loquat.app" ]]
```

Also call `verify-adhoc-app.sh` directly and assert it:

- succeeds for `Signature=adhoc` and `TeamIdentifier=not set`;
- fails with `expected an ad-hoc signature` for `Signature=Developer ID Application`;
- fails with `expected TeamIdentifier=not set` for any team value; and
- fails before calling `codesign` when the app directory is missing.

- [ ] **Step 2: Rewrite the release regression to reject notarization calls**

In `scripts/test-packaging-amendment.sh`, make the fake package-app require no signing/notary variables and return the fixture app. Put fake `xcrun` and `spctl` executables first in `PATH`; each must create a marker and exit 99 if called:

```bash
cat >"$FAKE_PACKAGE_APP" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
echo "$FAKE_APP"
SCRIPT

cat >"$FAKE_BIN/xcrun" <<'SCRIPT'
#!/usr/bin/env bash
touch "$FORBIDDEN_TOOL_MARKER"
exit 99
SCRIPT

cat >"$FAKE_BIN/spctl" <<'SCRIPT'
#!/usr/bin/env bash
touch "$FORBIDDEN_TOOL_MARKER"
exit 99
SCRIPT

chmod +x "$FAKE_PACKAGE_APP" "$FAKE_BIN/xcrun" "$FAKE_BIN/spctl"
```

Run `package-release.sh` with only:

```bash
env -u DEVELOPMENT_TEAM \
    -u CODE_SIGN_IDENTITY \
    -u PROVISIONING_PROFILE \
    -u NOTARYTOOL_PROFILE \
    PATH="$FAKE_BIN:$PATH" \
    FORBIDDEN_TOOL_MARKER="$FORBIDDEN_TOOL_MARKER" \
    INSTANT_TRANSLATION_BUILD_ROOT="$BUILD_ROOT" \
    INSTANT_TRANSLATION_PACKAGE_APP_SCRIPT="$FAKE_PACKAGE_APP" \
    "$ROOT/scripts/package-release.sh"
```

Assert the final ZIP and `SHA256SUMS` exist, checksum verification succeeds, the ZIP starts with `Loquat.app/`, no `._`/`__MACOSX` entry exists, and neither forbidden-tool marker exists.

- [ ] **Step 3: Run both script tests and verify RED**

```bash
bash scripts/test-signing-gates.sh
bash scripts/test-packaging-amendment.sh
```

Expected: signing tests fail because current packaging requires Developer ID inputs; release tests fail because current packaging requires a notary profile and calls `notarytool`/`stapler`/`spctl`.

- [ ] **Step 4: Add the fail-closed ad-hoc verifier**

Create executable `scripts/verify-adhoc-app.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

APP="${1:-build/Loquat.app}"
if [[ ! -d "$APP" ]]; then
    echo "error: app bundle not found: $APP" >&2
    exit 66
fi

codesign --verify --deep --strict "$APP"
SIGNATURE_DETAILS="$(codesign -dvv "$APP" 2>&1)"
SIGNATURE="$(awk -F= '/^Signature=/{print substr($0, index($0, "=") + 1); exit}' <<<"$SIGNATURE_DETAILS")"
TEAM="$(awk -F= '/^TeamIdentifier=/{print substr($0, index($0, "=") + 1); exit}' <<<"$SIGNATURE_DETAILS")"

if [[ "$SIGNATURE" != "adhoc" ]]; then
    echo "error: expected an ad-hoc signature; found '$SIGNATURE'" >&2
    exit 65
fi
if [[ "$TEAM" != "not set" ]]; then
    echo "error: expected TeamIdentifier=not set; found '$TEAM'" >&2
    exit 65
fi

echo "verified ad-hoc signature"
```

Run `chmod +x scripts/verify-adhoc-app.sh`.

- [ ] **Step 5: Replace app packaging with one unconditional ad-hoc path**

In `scripts/package-app.sh`, delete every reference to `DEVELOPMENT_TEAM`, `CODE_SIGN_IDENTITY`, entitlements, Hardened Runtime, timestamping, and Developer ID verification. Preserve the existing release build, app-bundle assembly, icon copy, and resource-bundle copy. End with:

```bash
codesign --force --deep --sign - "$APP"
"$ROOT/scripts/verify-adhoc-app.sh" "$APP"

echo "$APP"
```

Do not add `SIGNING_MODE`; ad-hoc is the only path.

- [ ] **Step 6: Remove notarization from release packaging**

In `scripts/package-release.sh`, remove the three required environment variables, the notary directory/archive, and every `xcrun`/`spctl` call. Keep package-app injection for deterministic tests. The packaging body after validating `$APP` must be:

```bash
RELEASE_DIR="$BUILD_ROOT/release"
ZIP_NAME="Loquat-macOS.zip"
mkdir -p "$RELEASE_DIR"
rm -f "$RELEASE_DIR/$ZIP_NAME" "$RELEASE_DIR/SHA256SUMS"

ditto \
    --norsrc \
    --noextattr \
    --noqtn \
    --noacl \
    -c -k --keepParent \
    "$APP" "$RELEASE_DIR/$ZIP_NAME"
(
    cd "$RELEASE_DIR"
    shasum -a 256 "$ZIP_NAME" >SHA256SUMS
    shasum -a 256 -c SHA256SUMS
)

echo "$RELEASE_DIR/$ZIP_NAME"
```

- [ ] **Step 7: Delete paid-distribution-only files and verify GREEN**

Delete:

```text
Config/InstantTranslation.entitlements.template.plist
scripts/materialize-entitlements.sh
scripts/verify-signed-app.sh
```

Then run:

```bash
bash -n scripts/package-app.sh scripts/package-release.sh scripts/verify-adhoc-app.sh scripts/test-signing-gates.sh scripts/test-packaging-amendment.sh
bash scripts/test-signing-gates.sh
bash scripts/test-packaging-amendment.sh
```

Expected: both regression scripts print their success marker and exit 0.

- [ ] **Step 8: Scan the active release implementation for removed concepts**

```bash
rg -n 'DEVELOPMENT_TEAM|CODE_SIGN_IDENTITY|PROVISIONING_PROFILE|NOTARYTOOL_PROFILE|notarytool|stapler|spctl|keychain-access-groups|options runtime|timestamp' Config scripts
```

Expected: no matches except negative assertions inside regression tests. Review every test match to confirm it is explicitly proving the forbidden tool or input is unused.

- [ ] **Step 9: Commit the release change**

```bash
git add Config scripts
git commit -m "build(release): publish one ad hoc artifact"
```

---

### Task 3: Honest installation, credential, and first-launch documentation

**Files:**
- Modify: `README.md:48`
- Modify: `README_zh.md:48`
- Modify: `docs/superpowers/specs/2026-08-12-instant-translation-design.md:292`
- Modify: `docs/superpowers/specs/2026-08-27-streamlined-keychain-design.md:1`
- Modify: `docs/superpowers/plans/2026-08-27-streamlined-keychain.md:1`
- Create: `docs/manual-free-release-checklist.md`

**Interfaces:**
- Consumes: v3 file-based Keychain and certificate-free commands from Tasks 1–2.
- Produces: one consistent public explanation of non-notarized installation, Keychain timing, upgrade behavior, and release commands.

- [ ] **Step 1: Replace the English installation and FAQ claims**

In `README.md`:

- state that the GitHub artifact is ad-hoc signed and not notarized;
- make Control-click/right-click → Open the first recovery step;
- make System Settings → Privacy & Security → Open Anyway the second recovery step;
- show `xattr -dr com.apple.quarantine /Applications/Loquat.app` only as the last fallback;
- state that the command bypasses Gatekeeper for this app and does not verify notarization;
- require downloading from GitHub Releases and verifying `SHA256SUMS` before bypassing Gatekeeper;
- document service `com.instanttranslation.macos.credentials.v3` as the file-based macOS Keychain;
- explain that old v1/v2 items are untouched and users enter credentials once;
- state that startup does not read Keychain and prompts, if any, happen only after Settings or a translation request; and
- replace the environment-heavy build examples with:

```bash
bash scripts/package-app.sh       # build ad-hoc-signed build/Loquat.app
bash scripts/package-release.sh   # build/release/Loquat-macOS.zip + SHA256SUMS
```

- [ ] **Step 2: Apply the same contract to the Chinese README**

Use equivalent Chinese wording in `README_zh.md`. Do not describe the app as “安全通过 Gatekeeper”, “已验证开发者”, “正式签名”, or “已公证”. Explicitly say `xattr` is a final fallback and avoid `sudo` in the documented command.

- [ ] **Step 3: Supersede the paid architecture without erasing history**

Update sections 9.4, 9.5, and 12.1 of `docs/superpowers/specs/2026-08-12-instant-translation-design.md` to match the new spec.

Add this notice immediately below the title of both 2026-08-27 Data Protection documents:

```markdown
> **Superseded on 2026-08-27.** The project permanently chose certificate-free ad-hoc distribution. Follow `docs/superpowers/specs/2026-08-27-free-adhoc-release-design.md` and `docs/superpowers/plans/2026-08-27-free-adhoc-release.md`; the Data Protection/Developer ID material below is retained only as a historical decision record.
```

Do not mechanically rewrite the historical body after adding the notice.

- [ ] **Step 4: Add a manual acceptance checklist for unavoidable prompts**

Create `docs/manual-free-release-checklist.md` with unchecked items for:

```markdown
# Free Release Manual Acceptance

- [ ] Verify `shasum -a 256 -c SHA256SUMS` before installation.
- [ ] Download/extract the ZIP through a normal browser so quarantine is present.
- [ ] Record whether Control-click/right-click → Open succeeds on current macOS.
- [ ] If needed, record whether Privacy & Security → Open Anyway succeeds.
- [ ] Use `xattr -dr com.apple.quarantine /Applications/Loquat.app` only if both UI paths fail.
- [ ] Confirm startup shows no application-triggered Keychain or protected-resource prompt.
- [ ] Open Settings and save one test credential; record any Keychain ACL prompt.
- [ ] Quit/relaunch and confirm the credential remains readable.
- [ ] Replace the app with the next ad-hoc build and record whether macOS asks for Keychain access again.
- [ ] Confirm no API key appears in UserDefaults, logs, the ZIP, or `SHA256SUMS`.
```

The checklist records observations; do not mark an item complete without performing it on a quarantined download.

- [ ] **Step 5: Run documentation and stale-term scans**

Run:

```bash
rg -n 'com\.instanttranslation\.macos\.credentials\.v2|Data Protection Keychain|Developer ID|NOTARYTOOL_PROFILE|CODE_SIGN_IDENTITY|DEVELOPMENT_TEAM|notarized|已公证|正式签名' README.md README_zh.md Sources Config scripts docs/superpowers/specs/2026-08-12-instant-translation-design.md
```

Expected: no active product or release claim remains. Negative shell-test assertions and explicitly superseded historical documents outside this scan are acceptable.

Run:

```bash
rg -n 'API.?Key|secret|credential' README.md README_zh.md Sources Config scripts
```

Review every match and confirm no literal production credential exists.

- [ ] **Step 6: Commit the documentation change**

```bash
git add README.md README_zh.md docs
git commit -m "docs(release): explain free ad hoc distribution"
```

---

### Task 4: Complete verification and build the free release artifact

**Files:** None expected. Build outputs remain ignored under `build/` and `.build/`.

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: locally verified `build/Loquat.app`, `build/release/Loquat-macOS.zip`, and `build/release/SHA256SUMS`.

- [ ] **Step 1: Run the full Swift test suite**

```bash
swift test
```

Expected: all tests pass with zero failures.

- [ ] **Step 2: Run both release regression suites**

```bash
bash scripts/test-signing-gates.sh
bash scripts/test-packaging-amendment.sh
```

Expected: both scripts exit 0 and print their success markers.

- [ ] **Step 3: Build the real local release package without credentials**

Run with all obsolete release variables explicitly absent:

```bash
env -u DEVELOPMENT_TEAM \
    -u CODE_SIGN_IDENTITY \
    -u PROVISIONING_PROFILE \
    -u NOTARYTOOL_PROFILE \
    bash scripts/package-release.sh
```

Expected: command exits 0 and prints the final ZIP path. It must not contact Apple or request Keychain access for signing credentials.

- [ ] **Step 4: Verify the real signature and release checksum**

```bash
codesign --verify --deep --strict build/Loquat.app
SIGNATURE_DETAILS="$(codesign -dvv build/Loquat.app 2>&1)"
rg '^Signature=adhoc$' <<<"$SIGNATURE_DETAILS"
rg '^TeamIdentifier=not set$' <<<"$SIGNATURE_DETAILS"
(cd build/release && shasum -a 256 -c SHA256SUMS)
unzip -Z1 build/release/Loquat-macOS.zip | head
```

Expected:

- signature verification exits 0;
- both `Signature=adhoc` and `TeamIdentifier=not set` are printed;
- checksum verification prints `Loquat-macOS.zip: OK`; and
- the archive begins with `Loquat.app/` and contains no `._` or `__MACOSX` entries.

- [ ] **Step 5: Run final architecture and whitespace scans**

```bash
rg -n 'kSecUseDataProtectionKeychain|kSecAttrAccessGroup|kSecAttrAccessible|com\.instanttranslation\.macos\.credentials\.v2' Sources
rg -n 'DEVELOPMENT_TEAM|CODE_SIGN_IDENTITY|PROVISIONING_PROFILE|NOTARYTOOL_PROFILE|notarytool|stapler|spctl|keychain-access-groups' Config scripts/package-app.sh scripts/package-release.sh scripts/verify-adhoc-app.sh
git diff --check
git status --short
```

Expected: both architecture scans and `git diff --check` emit no output. `git status --short` is empty after the three task commits; ignored build artifacts do not appear.

- [ ] **Step 6: Report the manual gate accurately**

Report the local package as “ad-hoc signed, checksum-verified, not notarized.” Do not claim that Gatekeeper or update-time Keychain ACL behavior passed until a human completes `docs/manual-free-release-checklist.md` using a freshly downloaded/quarantined artifact.
