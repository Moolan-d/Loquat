# Release Memory and Diagnostics Gates Implementation Plan

> **Historical plan — its ad-hoc release instructions are superseded.** Retain only its memory/diagnostics context; follow `docs/superpowers/specs/2026-08-27-streamlined-keychain-design.md` for the current notarized Developer ID release flow.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the 50 MB release gate measure Apple physical footprint, remove eager hidden Settings memory, make release scans fail closed, and provide a deterministic developer-only UI diagnostics executable.

**Architecture:** Keep the production translation popover warm, but make the retained Settings controller construct its single window only on first presentation. Keep release enforcement in small shell helpers with explicit tool/error handling. Add a separate Swift Package executable that composes real app views with in-memory deterministic dependencies and is never copied into the release bundle.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, XCTest, Swift Package Manager, Bash 3.2-compatible shell, macOS `footprint`, `vmmap`, `file`, `strings`, `nm`, `codesign`, `ditto`, and `shasum`.

## Global Constraints

- Support macOS 15 and later; keep `LSUIElement=true` and no Dock icon.
- Preserve the single retained `SettingsViewModel` and `SettingsWindowController`; only delay creation of `NSWindow`, `NSHostingView`, and `SettingsView`.
- Preserve the warm translation popover and its under-100 ms manual acceptance target.
- Keep the memory threshold exactly `51,200 KB`, defined as Apple per-process physical footprint; output RSS only as diagnostic data.
- Keep idle CPU at or below `0.5%`.
- Current GitHub Release mode remains exactly `SIGNING_MODE=adhoc`; no paid Apple Developer identity is required.
- Future `signed` mode continues to fail closed and remains an external verification gate.
- The diagnostics executable must not enter `InstantTranslation.app` or its ZIP and must never use real network, Keychain, pasteboard, or production `UserDefaults`.
- Security scans fail on missing tools, traversal errors, parse errors, empty executable sets, and search operational errors.
- Add concise Chinese comments only for non-obvious AppKit lifetime, deterministic fault injection, process ownership, or security fail-closed behavior.
- Every production change follows RED→GREEN with mutation evidence, clean full-suite verification, a fresh task reviewer, and no unresolved Critical or Important finding.

## File Structure

```text
Sources/InstantTranslationApp/Settings/
  SettingsWindowController.swift         # lazy retained Settings window lifecycle
Sources/InstantTranslationDiagnostics/
  DiagnosticsScenario.swift              # closed scenario catalog and expected UI states
  DiagnosticsDependencies.swift          # in-memory stores/providers; no live I/O
  DiagnosticsApplication.swift           # real popover/settings composition and app lifetime
  main.swift                             # argument parsing and executable entry
Tests/InstantTranslationAppTests/
  SettingsPresentationTests.swift        # lazy construction and single-window tests
Tests/InstantTranslationDiagnosticsTests/
  DiagnosticsScenarioTests.swift         # scenario routing and zero-live-I/O assertions
scripts/
  measure-memory.sh                      # phys_footprint/CPU hard gate; RSS diagnostics
  verify-bundle.sh                       # source + all nested Mach-O fail-closed scan
  package-release.sh                     # known-fixture manifest scan and release archive
  known-test-credential-fixtures.txt     # exact known test-only markers
  run-diagnostics.sh                     # build/run developer diagnostic scenario
  test-release-gates.sh                  # deterministic shell regression fixtures
README.md                                # diagnostics and physical-footprint commands
PRIVACY.md                               # developer diagnostics privacy boundary
docs/manual-test-checklist.md            # executable commands for every manual fault gate
```

---

### Task 1: Lazily Construct the Retained Settings Window

**Files:**
- Modify: `Sources/InstantTranslationApp/Settings/SettingsWindowController.swift`
- Modify: `Tests/InstantTranslationAppTests/SettingsPresentationTests.swift`

**Interfaces:**
- Consumes: `SettingsViewModel`, `SettingsView`, `.openInstantTranslationSettings`, and the existing public `SettingsWindowController.init(model:)`.
- Produces: unchanged public initializer and `showSettings(_:)`; internal `isSettingsWindowConstructed: Bool`; internal injected `makeWindow: @MainActor (SettingsViewModel) -> NSWindow` test seam.

- [ ] **Step 1: Write failing lazy-lifecycle tests**

Add tests that construct a controller with an injected factory counter and assert construction is deferred:

```swift
func testSettingsWindowIsConstructedOnlyOnFirstPresentation() async {
    var constructionCount = 0
    let controller = SettingsWindowController(
        model: await makeModel(),
        notificationCenter: NotificationCenter(),
        activateApplication: {},
        orderWindowFront: { window, sender in window.makeKeyAndOrderFront(sender) },
        installApplicationMenu: false,
        makeWindow: { model in
            constructionCount += 1
            return SettingsWindowController.makeProductionWindow(model: model)
        }
    )

    XCTAssertFalse(controller.isSettingsWindowConstructed)
    XCTAssertEqual(constructionCount, 0)
    controller.showSettings(nil)
    let firstWindow = controller.window
    XCTAssertTrue(controller.isSettingsWindowConstructed)
    XCTAssertEqual(constructionCount, 1)
    firstWindow?.close()
    controller.showSettings(nil)
    XCTAssertTrue(controller.window === firstWindow)
    XCTAssertEqual(constructionCount, 1)
}
```

Add a notification test that posts two open events in the same main-actor turn and asserts exactly one window identity and one factory call. Keep the existing `⌘,`, Quit, close/reopen, activation, and order-front assertions.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --filter 'SettingsPresentationTests/testSettingsWindowIsConstructedOnlyOnFirstPresentation|SettingsPresentationTests/testConcurrentOpenNotificationsConstructOneSettingsWindow'
```

Expected: compile-time RED because the internal factory seam and construction state do not exist, or assertion RED because the current initializer eagerly calls `NSWindow` and `NSHostingView`.

- [ ] **Step 3: Implement the minimal lazy controller**

Retain the model and factory, initialize the superclass with no window, and install notification/menu routing without constructing UI:

```swift
private let makeWindow: @MainActor (SettingsViewModel) -> NSWindow

var isSettingsWindowConstructed: Bool { isWindowLoaded }

private func ensureWindow() -> NSWindow {
    if isWindowLoaded, let window { return window }
    // Settings 视图树在首次实际打开时创建；关闭后仍复用同一窗口和模型。
    let created = makeWindow(model)
    window = created
    return created
}

@objc public func showSettings(_ sender: Any?) {
    let window = ensureWindow()
    activateApplication()
    orderWindowFront(window, sender)
}
```

Move current window construction into an internal static factory:

```swift
static func makeProductionWindow(model: SettingsViewModel) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.title = "Instant Translation Settings"
    window.isReleasedWhenClosed = false
    window.center()
    window.contentView = NSHostingView(rootView: SettingsView(model: model))
    window.setFrameAutosaveName("InstantTranslationSettingsWindow")
    return window
}
```

The public production initializer passes this factory. Do not expose injected seams publicly.

- [ ] **Step 4: Verify GREEN and mutation sensitivity**

Run `swift test --filter SettingsPresentationTests` and expect all focused tests to pass. Temporarily call `makeWindow(model)` from the initializer; rerun the lazy test and observe RED, then restore the lazy implementation and rerun GREEN.

- [ ] **Step 5: Run regression and memory comparison**

Run:

```bash
swift package clean
swift test
SIGNING_MODE=adhoc bash scripts/package-app.sh
```

Use the existing exact-PID diagnostic procedure to record pre-first-open physical footprint. Do not change the memory script in this task.

- [ ] **Step 6: Commit**

```bash
git add Sources/InstantTranslationApp/Settings/SettingsWindowController.swift Tests/InstantTranslationAppTests/SettingsPresentationTests.swift
git commit -m "perf(settings): lazily construct settings window"
```

---

### Task 2: Correct and Harden Release Gates

**Files:**
- Modify: `scripts/measure-memory.sh`
- Modify: `scripts/verify-bundle.sh`
- Modify: `scripts/package-release.sh`
- Modify: `scripts/test-release-gates.sh`
- Create: `scripts/known-test-credential-fixtures.txt`
- Modify: `docs/superpowers/specs/2026-08-12-instant-translation-design.md`
- Modify: `docs/superpowers/plans/2026-08-12-instant-translation-implementation.md`

**Interfaces:**
- Consumes: `scripts/package-app.sh`, explicit signing modes, packaged app layout, and known test sources.
- Produces: output line `physical_footprint_kb=<integer> rss_kb=<integer> cpu_percent=<decimal>`; fail-closed `verify-bundle.sh`; manifest-backed `package-release.sh`.

- [ ] **Step 1: Add failing shell regression fixtures**

Extend `test-release-gates.sh` with isolated fake tools and bundles that assert:

```bash
run_expect_failure env INSTANT_TRANSLATION_FOOTPRINT_COMMAND="$FIXTURES/footprint-missing-value" \
    INSTANT_TRANSLATION_IDLE_SECONDS=0 bash scripts/measure-memory.sh
run_expect_failure env INSTANT_TRANSLATION_PROCESS_IDENTITY_COMMAND="$FIXTURES/identity-reused" \
    INSTANT_TRANSLATION_IDLE_SECONDS=0 bash scripts/measure-memory.sh
run_expect_failure env INSTANT_TRANSLATION_STRINGS_COMMAND="$FIXTURES/strings-fails" \
    bash scripts/verify-bundle.sh
run_expect_failure env INSTANT_TRANSLATION_FILE_COMMAND="$FIXTURES/file-fails" \
    bash scripts/verify-bundle.sh
run_expect_failure env INSTANT_TRANSLATION_TEST_MARKER="unregistered-secret-fixture" \
    bash scripts/package-release.sh
```

Provide footprint fixtures for exactly 51,200 KB (pass), 51,201 KB (fail), malformed output (fail), and command exit 2 (fail). Provide an early-exit child and a changed process-identity response; assert the sentinel process remains alive.

- [ ] **Step 2: Run shell regressions and verify RED**

Run `bash scripts/test-release-gates.sh`.

Expected: RED because the current memory script gates RSS, scan pipelines treat operational errors as non-matches, the fixture manifest does not exist, and cleanup does not compare process identity.

- [ ] **Step 3: Implement physical-footprint and exact ownership helpers**

Introduce explicit commands with fixed production defaults:

```bash
FOOTPRINT_COMMAND="${INSTANT_TRANSLATION_FOOTPRINT_COMMAND:-/usr/bin/footprint}"
PS_COMMAND="${INSTANT_TRANSLATION_PS_COMMAND:-/bin/ps}"
PROCESS_IDENTITY_COMMAND="${INSTANT_TRANSLATION_PROCESS_IDENTITY_COMMAND:-$PS_COMMAND}"
```

Capture the launched child's `lstart` plus exact executable command immediately. Before sampling or signalling, recompute and compare both. If identity is absent or different, fail without sending a signal. Always `wait` only for the recorded child PID.

Parse a real `footprint --pid "$PID" --format bytes --noCategories` fixture into bytes, require one unambiguous `phys_footprint` value, convert with `(bytes + 1023) / 1024`, and fail on missing/multiple/non-numeric values. Output physical footprint first, retain RSS as diagnostics, and gate only physical footprint plus CPU.

- [ ] **Step 4: Make bundle scanning fail closed**

Create temporary NUL-delimited manifests using ordinary redirection so `find` status is observable. Require at least one Mach-O. For each file classified by `/usr/bin/file` as Mach-O, run `strings` and `nm` into temporary files and check each command status before searching.

Use a helper that distinguishes `rg` status 0 (forbidden match), 1 (clean), and greater than 1 (scan failure). Scan source files separately for forbidden APIs. Verify logos only at:

```text
Contents/Resources/InstantTranslation_InstantTranslationApp.bundle/googletranslate.svg
Contents/Resources/InstantTranslation_InstantTranslationApp.bundle/openai.svg
Contents/Resources/InstantTranslation_InstantTranslationApp.bundle/deepseek.svg
Contents/Resources/InstantTranslation_InstantTranslationApp.bundle/openrouter.svg
```

Keep plist usage-key and codesign checks.

- [ ] **Step 5: Make the known-fixture scan complete and fail closed**

Create `scripts/known-test-credential-fixtures.txt` with one literal per line, including every existing manifest value plus:

```text
local-secret
restored-google
restored-llm
stored-google
stored-llm
TESTTEAM
TEAM123
```

Add a repository consistency check that extracts suspicious credential/team/account literals from `Tests/`, compares them with the sorted manifest, and fails when a test introduces an uncovered marker. Read the manifest with `mapfile`-free Bash 3.2-compatible loops. Materialize `find` results before scanning and treat any `find`, `grep`, or read error as failure. Scan the `.app`, ZIP bytes, checksum file, and clean extracted tree while accurately describing this as a known-fixture gate.

- [ ] **Step 6: Verify GREEN and mutations**

Run `bash scripts/test-release-gates.sh`. Temporarily make the fake `strings` command exit 2 and verify RED; restore. Temporarily report 51,201 KB physical footprint and verify RED; restore. Temporarily add a new credential marker under the test fixture tree without adding it to the manifest and verify RED; restore.

- [ ] **Step 7: Update the authoritative metric wording**

Change the existing design and Task 11 plan from ambiguous `RSS/resident` wording to `Apple per-process physical footprint <= 51,200 KB`; require RSS to remain diagnostic output. Record that Activity Monitor Memory, Xcode Memory Gauge, `top MEM`, `footprint`, and `vmmap Physical footprint` use the relevant ledger while `ps rss` includes clean/shared resident mappings.

- [ ] **Step 8: Run live release verification**

Run:

```bash
bash scripts/test-signing-gates.sh
bash scripts/test-packaging-amendment.sh
bash scripts/test-release-gates.sh
bash scripts/verify-bundle.sh
INSTANT_TRANSLATION_IDLE_SECONDS=5 bash scripts/measure-memory.sh
SIGNING_MODE=adhoc bash scripts/package-release.sh
(cd build/release && shasum -a 256 -c SHA256SUMS)
git diff --check
```

Expected: all commands pass; memory output includes physical footprint below 51,200 KB, RSS diagnostics, and CPU no greater than 0.5%.

- [ ] **Step 9: Commit**

```bash
git add scripts docs/superpowers/specs/2026-08-12-instant-translation-design.md docs/superpowers/plans/2026-08-12-instant-translation-implementation.md
git commit -m "fix(release): harden memory and artifact gates"
```

---

### Task 3: Add a Developer-Only Diagnostics Executable

**Files:**
- Modify: `Package.swift`
- Create: `Sources/InstantTranslationDiagnostics/DiagnosticsScenario.swift`
- Create: `Sources/InstantTranslationDiagnostics/DiagnosticsDependencies.swift`
- Create: `Sources/InstantTranslationDiagnostics/DiagnosticsApplication.swift`
- Create: `Sources/InstantTranslationDiagnostics/main.swift`
- Create: `Tests/InstantTranslationDiagnosticsTests/DiagnosticsScenarioTests.swift`
- Create: `scripts/run-diagnostics.sh`
- Modify: `scripts/test-release-gates.sh`

**Interfaces:**
- Consumes: `TranslationProvider`, `TranslationCoordinator`, `TranslationSession`, `TranslationView`, `TranslationPopoverController`, `StatusBarController`, `SettingsViewModel`, `SettingsWindowController`, `PreferencesStoring`, `CredentialStoring`, and `ProviderConnectionTesting`.
- Produces: executable product `InstantTranslationDiagnostics`; public `DiagnosticsScenario: String, CaseIterable`; script interface `scripts/run-diagnostics.sh <scenario>`.

- [ ] **Step 1: Write failing scenario catalog tests**

Define the exact CLI names in tests:

```swift
XCTAssertEqual(
    DiagnosticsScenario.allCases.map(\.rawValue),
    [
        "slow-request", "google-failure", "llm-failure",
        "invalid-credentials", "rate-limited", "offline",
        "google-timeout", "llm-timeout", "malformed-llm",
        "credential-reload", "rollback-incomplete",
    ]
)
```

For each scenario, assert exact provider behaviors, initial input, expected visible state, and whether Settings or the translation popover opens. Assert unknown input returns a usage error containing all valid names and no credentials.

- [ ] **Step 2: Write failing zero-live-I/O composition tests**

Create recording in-memory dependencies. Construct every scenario and assert:

- no `URLSessionHTTPTransport`, `KeychainCredentialStore`, `UserDefaultsPreferencesStore`, or `ClipboardInputSource` factory is invoked;
- translation scenarios use two deterministic providers with independent states;
- credential reload starts unavailable, then returns fixed non-secret placeholders after `reloadCredentials()`;
- rollback-incomplete publishes `.needsAttention` without writing production preferences;
- provider failures map to the same real result-card and Settings status policies as production.

- [ ] **Step 3: Run diagnostics tests and verify RED**

Run `swift test --filter DiagnosticsScenarioTests`.

Expected: RED because the product, target, scenario catalog, and deterministic dependencies do not exist.

- [ ] **Step 4: Add the package targets**

Add:

```swift
.executable(name: "InstantTranslationDiagnostics", targets: ["InstantTranslationDiagnostics"]),
```

and targets:

```swift
.executableTarget(
    name: "InstantTranslationDiagnostics",
    dependencies: [
        "InstantTranslationApp", "InstantTranslationFeature",
        "InstantTranslationCore", "InstantTranslationInfrastructure",
    ]
),
.testTarget(
    name: "InstantTranslationDiagnosticsTests",
    dependencies: ["InstantTranslationDiagnostics"]
),
```

Keep `package-app.sh` copying only `.build/release/InstantTranslation`.

- [ ] **Step 5: Implement the closed scenario model and dependencies**

Use a closed enum and typed configuration rather than string branches in the UI:

```swift
public enum DiagnosticsScenario: String, CaseIterable, Sendable {
    case slowRequest = "slow-request"
    case googleFailure = "google-failure"
    case llmFailure = "llm-failure"
    case invalidCredentials = "invalid-credentials"
    case rateLimited = "rate-limited"
    case offline
    case googleTimeout = "google-timeout"
    case llmTimeout = "llm-timeout"
    case malformedLLM = "malformed-llm"
    case credentialReload = "credential-reload"
    case rollbackIncomplete = "rollback-incomplete"
}
```

Implement in-memory stores with locks/actors and deterministic provider continuations. The slow scenario exposes an in-app `Complete Slow Request` diagnostic action rather than sleeping. All fixture strings are visibly synthetic and are added to the known-fixture manifest.

- [ ] **Step 6: Compose real production presentation**

Create `DiagnosticsApplicationController` that owns the real `TranslationSession`, `TranslationPopoverController`, `StatusBarController`, `SettingsViewModel`, and `SettingsWindowController`. Translation scenarios submit a fixed non-secret term and open the real popover. Settings scenarios open the real Settings window. A small diagnostic control window may contain only scenario name, expected result, `Complete Slow Request`, and Quit; it must not replace the production view being inspected.

All construction is `@MainActor`. No diagnostic type is referenced by the production executable target.

- [ ] **Step 7: Add the runner script and release exclusion test**

Implement:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENARIO="${1:-}"
if [[ -z "$SCENARIO" ]]; then
    echo "usage: scripts/run-diagnostics.sh <scenario>" >&2
    exit 64
fi
cd "$ROOT"
exec swift run InstantTranslationDiagnostics "$SCENARIO"
```

Extend release regressions to build/package the app and assert no `InstantTranslationDiagnostics` executable, scenario name catalog, diagnostics source, or diagnostics test bundle exists inside the `.app`, ZIP, or extracted tree.

- [ ] **Step 8: Verify GREEN and route mutation**

Run:

```bash
swift test --filter DiagnosticsScenarioTests
swift run InstantTranslationDiagnostics invalid-name
```

The first passes; the second exits 64 and lists all valid scenarios. Temporarily map `google-failure` to the LLM provider; rerun the focused routing test and observe RED, then restore and rerun GREEN.

- [ ] **Step 9: Run full regressions and commit**

Run `swift package clean && swift test`, `bash scripts/package-app.sh`, and release-exclusion scans. Then commit:

```bash
git add Package.swift Sources/InstantTranslationDiagnostics Tests/InstantTranslationDiagnosticsTests scripts/run-diagnostics.sh scripts/test-release-gates.sh
git commit -m "test(diagnostics): add deterministic manual scenarios"
```

---

### Task 4: Connect Public Documentation to Executable Gates

**Files:**
- Modify: `README.md`
- Modify: `PRIVACY.md`
- Modify: `docs/manual-test-checklist.md`

**Interfaces:**
- Consumes: Task 2 output fields and Task 3 scenario names.
- Produces: executable release and manual verification instructions with no falsely completed checkbox.

- [ ] **Step 1: Write documentation assertions before editing**

Add a temporary verification command in the task report that fails unless:

```bash
rg -q 'physical_footprint_kb=' docs/manual-test-checklist.md
for scenario in slow-request google-failure llm-failure invalid-credentials rate-limited offline google-timeout llm-timeout malformed-llm credential-reload rollback-incomplete; do
    rg -q "run-diagnostics.sh $scenario" docs/manual-test-checklist.md
done
```

Run it against the current docs and record RED because physical footprint and executable scenario commands are missing.

- [ ] **Step 2: Update README memory and diagnostics guidance**

Document that the unchanged 50 MB target uses Apple physical footprint, while `rss_kb` is diagnostic. Add a developer-only diagnostics section listing `scripts/run-diagnostics.sh <scenario>`, state that it uses synthetic in-memory dependencies, and state that it is not shipped in the release app.

- [ ] **Step 3: Update privacy boundaries**

State that developer diagnostics do not read real Keychain, clipboard, production `UserDefaults`, or network, and are excluded from public artifacts. Do not describe the diagnostics executable as an end-user feature.

- [ ] **Step 4: Make every manual fault step executable**

Replace natural-language stub/fault injection steps with exact commands. Examples:

```bash
bash scripts/run-diagnostics.sh slow-request
bash scripts/run-diagnostics.sh google-failure
bash scripts/run-diagnostics.sh llm-failure
bash scripts/run-diagnostics.sh rate-limited
bash scripts/run-diagnostics.sh credential-reload
bash scripts/run-diagnostics.sh rollback-incomplete
```

Record `physical_footprint_kb`, `rss_kb`, and CPU separately. Keep every checkbox unchecked unless a human actually performs it. Retain real-service checks with tester-owned Keychain credentials.

- [ ] **Step 5: Verify documentation and commit**

Run the assertion from Step 1 and expect GREEN. Validate all local Markdown paths, forbid global Gatekeeper-disable/default `sudo xattr` guidance, confirm all 13 numbered sections, and run `git diff --check`. Commit:

```bash
git add README.md PRIVACY.md docs/manual-test-checklist.md
git commit -m "docs: connect diagnostics to release checklist"
```

---

### Task 5: Integrate and Execute the Release Acceptance Matrix

**Files:**
- Modify: `.superpowers/sdd/2026-08-12-instant-translation-implementation/progress.md` (ignored ledger only)
- No production changes unless a reviewer reopens a scoped finding.

**Interfaces:**
- Consumes: Tasks 1–4 and existing signing/storage/provider/UI modules.
- Produces: one reviewed feature branch, verified ad-hoc release artifacts, and an explicit list of external manual gates.

- [ ] **Step 1: Integrate only reviewed commits**

For each task, run a fresh read-only reviewer against its exact base/head range. Fix every Critical/Important finding in the source task worktree with RED→GREEN, then request a scoped re-review. Cherry-pick only after the reviewer reports no open Critical/Important issue.

- [ ] **Step 2: Run a clean automated matrix**

From the integrated feature worktree:

```bash
swift package clean
swift test
swift build -c release
bash scripts/test-signing-gates.sh
bash scripts/test-packaging-amendment.sh
bash scripts/test-release-gates.sh
bash scripts/verify-bundle.sh
INSTANT_TRANSLATION_IDLE_SECONDS=60 bash scripts/measure-memory.sh
SIGNING_MODE=adhoc bash scripts/package-release.sh
(cd build/release && shasum -a 256 -c SHA256SUMS)
git diff --check
```

Expected: all commands exit 0; physical footprint no greater than 51,200 KB; CPU no greater than 0.5%; checksum reports `InstantTranslation-macOS.zip: OK`.

- [ ] **Step 3: Verify diagnostics without shipping them**

Run every scenario through its focused automated scenario test. Launch at least `slow-request`, `credential-reload`, and `rollback-incomplete` for manual UI inspection, then quit them. Inspect the release `.app` and extracted ZIP and assert the diagnostics executable/catalog is absent.

- [ ] **Step 4: Record external gates honestly**

Record Thread Sanitizer as blocked if dyld still reports `Sanitizer load violates platform policy`. Leave macOS 15/current-version appearance, VoiceOver, Instruments, real-provider, and Gatekeeper account checks unchecked until a person performs them. Automated success must not be relabeled as complete manual acceptance.

- [ ] **Step 5: Request final cross-cutting review**

Review the entire branch from the original implementation baseline through final HEAD for specification alignment, architecture, security, privacy, accessibility, release safety, diagnostics exclusion, and tests. Resolve all Critical/Important findings before completion.

- [ ] **Step 6: Commit any ledger-only status outside Git tracking and verify clean state**

Run:

```bash
git status --short
git log --oneline --decorate -12
```

Expected: no tracked or untracked product changes remain; only ignored SDD reports/ledger may exist. Do not mark the release ready while mandatory manual checklist items remain unchecked.
