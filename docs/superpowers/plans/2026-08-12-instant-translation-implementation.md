# Instant Translation for macOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a menu-bar-only macOS 15+ application that independently compares Google Cloud Translation with an OpenAI-compatible terminology translation while remaining native, private, and below the 50 MB idle-memory target.

**Architecture:** Use a zero-runtime-dependency Swift package split into domain, infrastructure, feature-state, and AppKit/SwiftUI presentation targets. AppKit owns the accessory lifecycle, status item, transient popover, focus, native material, global shortcut, and settings window; SwiftUI renders content. Foundation, Security, ServiceManagement, Carbon, and AppKit provide networking, Keychain, launch-at-login, permission-free global shortcuts, and clipboard support.

**Tech Stack:** Swift 6.2, Swift Package Manager, AppKit, SwiftUI, Observation, Foundation `URLSession`, Security Keychain Services, ServiceManagement, Carbon `RegisterEventHotKey`, XCTest.

**Design reference:** `docs/superpowers/specs/2026-08-12-instant-translation-design.md`

## Global Constraints

- Target macOS 15 and later.
- Ship no third-party runtime dependencies, Electron runtime, WebView, polling loop, persistent socket, resident HTTP server, analytics, or telemetry.
- Keep release-build idle resident memory at or below 50 MB after 60 seconds; idle CPU must be effectively zero.
- Use AppKit for lifecycle, status item, transient popover, focus, outside-click dismissal, and `NSVisualEffectView`; use SwiftUI for popover content and Settings.
- Use an ephemeral `URLSessionConfiguration` with no disk cache, cookies, or persistent credential store.
- Send Google credentials through `X-Goog-Api-Key`, never in the URL.
- Require HTTPS for remote LLM Base URLs; permit HTTP only for `localhost`, `127.0.0.1`, and `::1`.
- Store API keys only in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Never persist clipboard text, source text, translated text, rationales, query history, pronunciation data, or audio.
- Request no Accessibility, Screen Recording, Microphone, or Automation permission in the first release.
- Default Launch at Login, global shortcut, and clipboard-on-open to off; default the LLM prompt preset to Technology & R&D.
- Clipboard-on-open automatically submits at most 500 Swift `Character` values; longer text is inserted and requires Enter.
- Google and LLM execute independently, publish independently, fail independently, and retry independently.
- Fixed first-release timeouts are 15 seconds for Google and 60 seconds for the LLM; perform no automatic retry.
- Bundled provider logos are selected locally from a fixed hostname map; do not download icons at runtime.
- Use bundle identifier `com.instanttranslation.macos`, Keychain service `com.instanttranslation.macos.credentials`, and executable name `InstantTranslation` consistently.

### Approved signing and credential-storage addendum (2026-08-13)

- Release tooling accepts exactly `SIGNING_MODE=adhoc` or `SIGNING_MODE=signed`; it never guesses from local identities.
- `adhoc` is the current self-use and GitHub Release mode. It uses the macOS file-based Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and must not add `kSecUseDataProtectionKeychain` to its SecItem queries.
- `signed` is reserved for a future Developer ID/provisioned build. It uses Data Protection Keychain queries, verified application/team identifiers, and the exact provisioned keychain access group.
- There is no runtime fallback from Data Protection Keychain to file-based Keychain. Backend selection is a construction-time consequence of the validated signing mode.
- Both backends keep API keys out of `UserDefaults`, logs, errors, URLs, and release artifacts. A read failure is not treated as a missing credential.
- A future `adhoc` → `signed` migration must be versioned and transactional per credential: read source, write destination, read-verify destination, then delete source. Failure preserves the source and exposes a sanitized retryable state.
- The current GitHub Release contains an ad-hoc-signed `.app` ZIP plus `SHA256SUMS`. Documentation states that it is not notarized and uses Apple's per-app System Settings → Privacy & Security → Open Anyway flow. It must not recommend disabling Gatekeeper globally or use `sudo xattr` as the default path.
- `signed` packaging continues to fail closed unless the supplied identity, actual TeamIdentifier, application identifier, provisioning profile, and exact keychain access group all match. Notarization is a distinct future gate.

## File Structure

```text
Package.swift
Sources/
  InstantTranslationCore/
    Domain/Language.swift
    Domain/TranslationModels.swift
    Domain/TranslationProvider.swift
    Domain/SpeechProvider.swift
    Input/InputSource.swift
    Input/ClipboardTextPolicy.swift
    Translation/DirectionResolver.swift
    Translation/TranslationCoordinator.swift
  InstantTranslationInfrastructure/
    Networking/HTTPTransport.swift
    Networking/EndpointPolicy.swift
    Networking/ProviderErrorMapper.swift
    Providers/GoogleTranslationProvider.swift
    Providers/LLMResponseParser.swift
    Providers/OpenAICompatibleProvider.swift
    Providers/ProviderBrandResolver.swift
    Storage/CredentialStore.swift
    Storage/PreferencesStore.swift
    Storage/DefaultPrompts.swift
    Diagnostics/TranslationLogger.swift
  InstantTranslationFeature/
    TranslationSession.swift
    ProviderCardState.swift
  InstantTranslationApp/
    Application/AppDelegate.swift
    Application/ApplicationContainer.swift
    Application/StatusBarController.swift
    Application/GlobalShortcutRegistrar.swift
    Application/LaunchAtLoginController.swift
    Popover/TranslationPopoverController.swift
    Popover/PopoverContentController.swift
    Popover/ClipboardInputSource.swift
    Translation/TranslationView.swift
    Translation/ResultCardView.swift
    Translation/ProviderIconView.swift
    Translation/CopyController.swift
    Settings/SettingsWindowController.swift
    Settings/SettingsViewModel.swift
    Settings/SettingsView.swift
    Settings/ShortcutCaptureView.swift
    Resources/ProviderLogos.xcassets/
  InstantTranslation/main.swift
Tests/
  InstantTranslationCoreTests/
  InstantTranslationInfrastructureTests/
  InstantTranslationFeatureTests/
  InstantTranslationAppTests/
scripts/package-app.sh
scripts/verify-bundle.sh
scripts/measure-memory.sh
Config/Info.plist
README.md
PRIVACY.md
THIRD_PARTY_NOTICES.md
docs/manual-test-checklist.md
```

Files stay grouped by the capability they change. Domain contracts do not import AppKit, SwiftUI, Security, or ServiceManagement. Infrastructure does not import SwiftUI. The executable target contains only the process entry point.

## Requirements Traceability

| Approved requirement | Implemented and verified in |
|---|---|
| Menu-bar-only accessory app, transient outside-click close, no Dock icon | Tasks 8 and 11 |
| Native light/dark switching, glass material, Reduce Transparency and Increase Contrast | Tasks 8, 9, and 11 |
| Manual input, automatic Chinese/English direction, manual swap | Tasks 2, 7, and 9 |
| Optional clipboard read on open; 500-character automatic-submit limit | Tasks 2, 7, 8, 10, and 11 |
| Google Cloud Translation and OpenAI-compatible LLM run and fail independently | Tasks 5, 6, 7, and 11 |
| General and Technology & R&D system prompts are Settings-only; Technology & R&D is default | Tasks 4 and 10 |
| Official provider marks instead of visible provider text in the popover | Tasks 6 and 9 |
| Per-result copy copies only the primary translation and keeps the popover open | Task 9 |
| Keychain-only secrets, ephemeral networking, no text/history/telemetry persistence | Tasks 3, 4, and 11 |
| Optional launch at login and permission-free global shortcut, both default off | Tasks 4, 8, 10, and 11 |
| Future OCR, selection, languages, pronunciation, and TTS remain extension seams only | Tasks 1, 2, and 11 |
| Idle RSS/CPU, warm-open, 200-query, and 500-open/close acceptance gates | Task 11 |

---

### Task 1: Bootstrap the Package and Domain Contracts

**Files:**
- Create: `Package.swift`
- Create: `Sources/InstantTranslationCore/Domain/Language.swift`
- Create: `Sources/InstantTranslationCore/Domain/TranslationModels.swift`
- Create: `Sources/InstantTranslationCore/Domain/TranslationProvider.swift`
- Create: `Sources/InstantTranslationCore/Domain/SpeechProvider.swift`
- Test: `Tests/InstantTranslationCoreTests/TranslationModelsTests.swift`

**Interfaces:**
- Consumes: none.
- Produces: `LanguageID`, `LanguageCatalog`, `InputSourceID`, `PromptPresetID`, `ProviderID`, `TranslationRequest`, `TranslationResult`, `Pronunciation`, `TranslationProvider`, `TranslationProviderError`, `SpeechRequest`, and `SpeechProvider`.

- [ ] **Step 1: Create the minimal Swift package manifest**

```swift
// Package.swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InstantTranslation",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "InstantTranslationCore", targets: ["InstantTranslationCore"]),
    ],
    targets: [
        .target(name: "InstantTranslationCore"),
        .testTarget(
            name: "InstantTranslationCoreTests",
            dependencies: ["InstantTranslationCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
```

- [ ] **Step 2: Write the failing domain-model test**

```swift
// Tests/InstantTranslationCoreTests/TranslationModelsTests.swift
import XCTest
@testable import InstantTranslationCore

final class TranslationModelsTests: XCTestCase {
    func testInitialCatalogContainsOnlyChineseAndEnglish() {
        XCTAssertEqual(LanguageCatalog.initial.languages.map(\.id), [.simplifiedChinese, .english])
        XCTAssertEqual(LanguageID.simplifiedChinese.googleCode, "zh-CN")
        XCTAssertEqual(LanguageID.english.googleCode, "en")
    }

    func testResultCarriesFuturePronunciationAndSpeechFieldsWithoutAudioObjects() {
        let pronunciation = Pronunciation(
            scheme: PronunciationScheme("ipa"),
            text: "/ˈkɒmpaɪlə/",
            language: .english,
            source: .llm
        )
        let result = TranslationResult(
            providerID: .llm,
            requestID: UUID(),
            primaryText: "compiler",
            rationale: "A standard software-engineering term.",
            sourceLanguage: .simplifiedChinese,
            targetLanguage: .english,
            pronunciations: [pronunciation],
            speakableText: "compiler",
            duration: .milliseconds(20)
        )
        XCTAssertEqual(result.pronunciations, [pronunciation])
        XCTAssertEqual(result.speakableText, "compiler")
    }
}
```

- [ ] **Step 3: Run the test and verify the red state**

Run: `swift test --filter TranslationModelsTests`

Expected: FAIL because `LanguageCatalog`, `Pronunciation`, and `TranslationResult` do not exist.

- [ ] **Step 4: Implement the domain values and extension contracts**

```swift
// Sources/InstantTranslationCore/Domain/Language.swift
import Foundation

public struct LanguageID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let simplifiedChinese = Self(rawValue: "zh-Hans")
    public static let english = Self(rawValue: "en")

    public var googleCode: String {
        self == .simplifiedChinese ? "zh-CN" : rawValue
    }
}

public struct LanguageDescriptor: Hashable, Sendable {
    public let id: LanguageID
    public let displayName: String
    public init(id: LanguageID, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct LanguageCatalog: Sendable {
    public let languages: [LanguageDescriptor]
    public init(languages: [LanguageDescriptor]) { self.languages = languages }
    public static let initial = Self(languages: [
        .init(id: .simplifiedChinese, displayName: "中文"),
        .init(id: .english, displayName: "English"),
    ])
}
```

```swift
// Sources/InstantTranslationCore/Domain/TranslationModels.swift
import Foundation

public struct InputSourceID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let manual = Self(rawValue: "manual")
    public static let clipboard = Self(rawValue: "clipboard")
    public static let selection = Self(rawValue: "selection")
    public static let ocr = Self(rawValue: "ocr")
}

public struct PromptPresetID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let general = Self(rawValue: "general")
    public static let technologyAndRnD = Self(rawValue: "technology-and-r-and-d")
}

public struct ProviderID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let google = Self(rawValue: "google-cloud-translation")
    public static let llm = Self(rawValue: "openai-compatible-llm")
}

public struct PronunciationScheme: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct Pronunciation: Hashable, Codable, Sendable {
    public let scheme: PronunciationScheme
    public let text: String
    public let language: LanguageID
    public let source: ProviderID

    public init(scheme: PronunciationScheme, text: String, language: LanguageID, source: ProviderID) {
        self.scheme = scheme
        self.text = text
        self.language = language
        self.source = source
    }
}

public enum DirectionOrigin: String, Codable, Equatable, Sendable { case detected, manual }

public struct TranslationRequest: Hashable, Sendable {
    public let id: UUID
    public let text: String
    public let inputSource: InputSourceID
    public let sourceLanguage: LanguageID
    public let targetLanguage: LanguageID
    public let directionOrigin: DirectionOrigin
    public let promptPresetID: PromptPresetID

    public init(
        id: UUID,
        text: String,
        inputSource: InputSourceID,
        sourceLanguage: LanguageID,
        targetLanguage: LanguageID,
        directionOrigin: DirectionOrigin,
        promptPresetID: PromptPresetID
    ) {
        self.id = id
        self.text = text
        self.inputSource = inputSource
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.directionOrigin = directionOrigin
        self.promptPresetID = promptPresetID
    }
}

public struct TranslationResult: Hashable, Sendable {
    public let providerID: ProviderID
    public let requestID: UUID
    public let primaryText: String
    public let rationale: String?
    public let sourceLanguage: LanguageID
    public let targetLanguage: LanguageID
    public let pronunciations: [Pronunciation]
    public let speakableText: String?
    public let duration: Duration

    public init(
        providerID: ProviderID,
        requestID: UUID,
        primaryText: String,
        rationale: String?,
        sourceLanguage: LanguageID,
        targetLanguage: LanguageID,
        pronunciations: [Pronunciation],
        speakableText: String?,
        duration: Duration
    ) {
        self.providerID = providerID
        self.requestID = requestID
        self.primaryText = primaryText
        self.rationale = rationale
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.pronunciations = pronunciations
        self.speakableText = speakableText
        self.duration = duration
    }
}
```

```swift
// Sources/InstantTranslationCore/Domain/TranslationProvider.swift
import Foundation

public enum TranslationProviderError: Error, Equatable, Sendable {
    case unconfigured
    case invalidCredentials
    case rateLimited
    case networkUnavailable
    case timedOut
    case insecureEndpoint
    case invalidResponse
    case server(statusCode: Int)
    case cancelled
}

public protocol TranslationProvider: Sendable {
    var id: ProviderID { get }
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
}
```

```swift
// Sources/InstantTranslationCore/Domain/SpeechProvider.swift
public struct SpeechRequest: Hashable, Sendable {
    public let text: String
    public let language: LanguageID
    public let voiceID: String?
    public let rate: Double
    public let pitch: Double

    public init(text: String, language: LanguageID, voiceID: String?, rate: Double, pitch: Double) {
        self.text = text
        self.language = language
        self.voiceID = voiceID
        self.rate = rate
        self.pitch = pitch
    }
}

public protocol SpeechProvider: Sendable {
    func speak(_ request: SpeechRequest) async throws
    func stop() async
}
```

- [ ] **Step 5: Run the core tests**

Run: `swift test --filter TranslationModelsTests`

Expected: PASS with 2 tests.

- [ ] **Step 6: Commit the domain foundation**

```bash
git add Package.swift Sources/InstantTranslationCore Tests/InstantTranslationCoreTests
git commit -m "feat(core): define translation domain contracts"
```

---

### Task 2: Input Normalization, Clipboard Policy, and Direction Resolution

**Files:**
- Create: `Sources/InstantTranslationCore/Input/InputSource.swift`
- Create: `Sources/InstantTranslationCore/Input/ClipboardTextPolicy.swift`
- Create: `Sources/InstantTranslationCore/Translation/DirectionResolver.swift`
- Test: `Tests/InstantTranslationCoreTests/InputAndDirectionTests.swift`

**Interfaces:**
- Consumes: `LanguageID`, `InputSourceID`.
- Produces: `SourceText`, `InputSource.read()`, `ManualInputSource`, `ClipboardTextPolicy.evaluate(_:)`, `ClipboardDecision`, and `DirectionResolver.resolve(_:)`.

- [ ] **Step 1: Write the failing input-policy tests**

```swift
// Tests/InstantTranslationCoreTests/InputAndDirectionTests.swift
import XCTest
@testable import InstantTranslationCore

final class InputAndDirectionTests: XCTestCase {
    func testManualInputTrimsEdgesAndPreservesInternalWhitespace() async throws {
        let source = ManualInputSource(rawValue: "  just-in-time  compilation  ")
        let text = try await source.read()
        XCTAssertEqual(text?.value, "just-in-time  compilation")
        XCTAssertEqual(text?.sourceID, .manual)
    }

    func testClipboardIgnoresEmptyTranslatesFiveHundredAndConfirmsFiveHundredOne() {
        let policy = ClipboardTextPolicy(automaticCharacterLimit: 500)
        XCTAssertEqual(policy.evaluate(nil), .ignore)
        XCTAssertEqual(policy.evaluate("  \n  "), .ignore)
        XCTAssertEqual(policy.evaluate(String(repeating: "a", count: 500)).shouldSubmit, true)
        XCTAssertEqual(policy.evaluate(String(repeating: "a", count: 501)).shouldSubmit, false)
    }

    func testDirectionUsesHanContentOtherwiseEnglish() {
        let resolver = DirectionResolver()
        XCTAssertEqual(resolver.resolve("即时编译").source, .simplifiedChinese)
        XCTAssertEqual(resolver.resolve("即时编译").target, .english)
        XCTAssertEqual(resolver.resolve("JIT compilation").source, .english)
        XCTAssertEqual(resolver.resolve("JIT compilation").target, .simplifiedChinese)
    }
}
```

- [ ] **Step 2: Run the tests and verify the red state**

Run: `swift test --filter InputAndDirectionTests`

Expected: FAIL because the input and direction types do not exist.

- [ ] **Step 3: Implement normalized input and clipboard decisions**

```swift
// Sources/InstantTranslationCore/Input/InputSource.swift
import Foundation

public struct SourceText: Hashable, Sendable {
    public let value: String
    public let sourceID: InputSourceID

    public init?(rawValue: String, sourceID: InputSourceID) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        self.value = normalized
        self.sourceID = sourceID
    }
}

public protocol InputSource: Sendable {
    var id: InputSourceID { get }
    func read() async throws -> SourceText?
}

public struct ManualInputSource: InputSource {
    public let id = InputSourceID.manual
    private let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public func read() async throws -> SourceText? {
        SourceText(rawValue: rawValue, sourceID: id)
    }
}
```

```swift
// Sources/InstantTranslationCore/Input/ClipboardTextPolicy.swift
public enum ClipboardDecision: Equatable, Sendable {
    case ignore
    case translate(SourceText)
    case requireConfirmation(SourceText)

    public var shouldSubmit: Bool {
        if case .translate = self { return true }
        return false
    }
}

public struct ClipboardTextPolicy: Sendable {
    public let automaticCharacterLimit: Int
    public init(automaticCharacterLimit: Int = 500) {
        self.automaticCharacterLimit = automaticCharacterLimit
    }

    public func evaluate(_ rawValue: String?) -> ClipboardDecision {
        guard let rawValue,
              let text = SourceText(rawValue: rawValue, sourceID: .clipboard)
        else { return .ignore }
        return text.value.count <= automaticCharacterLimit
            ? .translate(text)
            : .requireConfirmation(text)
    }
}
```

```swift
// Sources/InstantTranslationCore/Translation/DirectionResolver.swift
public struct TranslationDirection: Equatable, Sendable {
    public let source: LanguageID
    public let target: LanguageID

    public init(source: LanguageID, target: LanguageID) {
        self.source = source
        self.target = target
    }
}

public struct DirectionResolver: Sendable {
    public init() {}

    public func resolve(_ text: String) -> TranslationDirection {
        let containsHan = text.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value) ||
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0xF900...0xFAFF).contains(scalar.value)
        }
        return containsHan
            ? .init(source: .simplifiedChinese, target: .english)
            : .init(source: .english, target: .simplifiedChinese)
    }
}
```

- [ ] **Step 4: Run the core tests**

Run: `swift test --filter InputAndDirectionTests`

Expected: PASS with 3 tests.

- [ ] **Step 5: Commit input behavior**

```bash
git add Sources/InstantTranslationCore Tests/InstantTranslationCoreTests
git commit -m "feat(core): add input and direction policies"
```

---

### Task 3: Secure, Ephemeral Networking and Safe Diagnostics

**Files:**
- Modify: `Package.swift`
- Create: `Sources/InstantTranslationInfrastructure/Networking/HTTPTransport.swift`
- Create: `Sources/InstantTranslationInfrastructure/Networking/EndpointPolicy.swift`
- Create: `Sources/InstantTranslationInfrastructure/Networking/ProviderErrorMapper.swift`
- Create: `Sources/InstantTranslationInfrastructure/Diagnostics/TranslationLogger.swift`
- Test: `Tests/InstantTranslationInfrastructureTests/NetworkingSecurityTests.swift`

**Interfaces:**
- Consumes: `TranslationProviderError`, `ProviderID`.
- Produces: `HTTPTransport.send(_:)`, `HTTPResponse`, `URLSessionHTTPTransport.makeConfiguration()`, `EndpointPolicy.validatedAPIBaseURL(_:)`, `ProviderErrorMapper`, `TranslationLogEvent`, and `TranslationLogger`.

- [ ] **Step 1: Add infrastructure targets to the manifest**

Add these entries without changing the existing core entries:

```swift
// Package.swift product entry
.library(
    name: "InstantTranslationInfrastructure",
    targets: ["InstantTranslationInfrastructure"]
),

// Package.swift target entries
.target(
    name: "InstantTranslationInfrastructure",
    dependencies: ["InstantTranslationCore"]
),
.testTarget(
    name: "InstantTranslationInfrastructureTests",
    dependencies: ["InstantTranslationInfrastructure", "InstantTranslationCore"]
),
```

- [ ] **Step 2: Write failing security tests**

```swift
// Tests/InstantTranslationInfrastructureTests/NetworkingSecurityTests.swift
import XCTest
@testable import InstantTranslationInfrastructure

final class NetworkingSecurityTests: XCTestCase {
    func testEphemeralConfigurationHasNoPersistentStores() {
        let configuration = URLSessionHTTPTransport.makeConfiguration()
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testEndpointPolicyAllowsHTTPSAndLoopbackHTTPOnly() throws {
        XCTAssertNoThrow(try EndpointPolicy.validatedAPIBaseURL("https://api.openai.com/v1"))
        XCTAssertNoThrow(try EndpointPolicy.validatedAPIBaseURL("http://127.0.0.1:11434/v1"))
        XCTAssertNoThrow(try EndpointPolicy.validatedAPIBaseURL("http://[::1]:1234/v1"))
        XCTAssertThrowsError(try EndpointPolicy.validatedAPIBaseURL("http://example.com/v1"))
        XCTAssertThrowsError(try EndpointPolicy.validatedAPIBaseURL("https://user:pass@example.com/v1?key=secret"))
    }

    func testDiagnosticEventCannotContainRequestTextOrCredentials() {
        let event = TranslationLogEvent(
            providerID: .llm,
            requestID: UUID(),
            statusCode: 429,
            durationMilliseconds: 80
        )
        let description = event.description
        XCTAssertFalse(description.contains("Authorization"))
        XCTAssertFalse(description.contains("translation text"))
    }

    func testProviderErrorMapperCoversAuthenticationRateNetworkTimeoutAndCancellation() {
        XCTAssertEqual(ProviderErrorMapper.map(statusCode: 403), .invalidCredentials)
        XCTAssertEqual(ProviderErrorMapper.map(statusCode: 429), .rateLimited)
        XCTAssertEqual(ProviderErrorMapper.map(URLError(.notConnectedToInternet)), .networkUnavailable)
        XCTAssertEqual(ProviderErrorMapper.map(URLError(.timedOut)), .timedOut)
        XCTAssertEqual(ProviderErrorMapper.map(CancellationError()), .cancelled)
    }
}
```

- [ ] **Step 3: Run the tests and verify the red state**

Run: `swift test --filter NetworkingSecurityTests`

Expected: FAIL because the networking and diagnostics types do not exist.

- [ ] **Step 4: Implement the transport and endpoint policy**

```swift
// Sources/InstantTranslationInfrastructure/Networking/HTTPTransport.swift
import Foundation

public struct HTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int

    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public actor URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        session = URLSession(configuration: Self.makeConfiguration())
    }

    public static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        return configuration
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return HTTPResponse(data: data, statusCode: response.statusCode)
    }
}
```

```swift
// Sources/InstantTranslationInfrastructure/Networking/EndpointPolicy.swift
import Foundation
import InstantTranslationCore

public enum EndpointPolicy {
    public static func validatedAPIBaseURL(_ value: String) throws -> URL {
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else { throw TranslationProviderError.insecureEndpoint }

        let loopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard scheme == "https" || (scheme == "http" && loopback) else {
            throw TranslationProviderError.insecureEndpoint
        }
        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let url = components.url else { throw TranslationProviderError.insecureEndpoint }
        return url
    }
}
```

```swift
// Sources/InstantTranslationInfrastructure/Networking/ProviderErrorMapper.swift
import Foundation
import InstantTranslationCore

public enum ProviderErrorMapper {
    public static func map(statusCode: Int) -> TranslationProviderError {
        switch statusCode {
        case 401, 403: .invalidCredentials
        case 429: .rateLimited
        default: .server(statusCode: statusCode)
        }
    }

    public static func map(_ error: Error) -> TranslationProviderError {
        if error is CancellationError { return .cancelled }
        guard let urlError = error as? URLError else { return .invalidResponse }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
            return .networkUnavailable
        case .timedOut:
            return .timedOut
        case .cancelled:
            return .cancelled
        default:
            return .invalidResponse
        }
    }
}
```

```swift
// Sources/InstantTranslationInfrastructure/Diagnostics/TranslationLogger.swift
import Foundation
import OSLog
import InstantTranslationCore

public struct TranslationLogEvent: CustomStringConvertible, Sendable {
    public let providerID: ProviderID
    public let requestID: UUID
    public let statusCode: Int?
    public let durationMilliseconds: Int
    public init(providerID: ProviderID, requestID: UUID, statusCode: Int?, durationMilliseconds: Int) {
        self.providerID = providerID
        self.requestID = requestID
        self.statusCode = statusCode
        self.durationMilliseconds = durationMilliseconds
    }
    public var description: String {
        "provider=\(providerID.rawValue) request=\(requestID.uuidString) status=\(statusCode.map(String.init) ?? "none") durationMs=\(durationMilliseconds)"
    }
}

public struct TranslationLogger: Sendable {
    private let logger = Logger(subsystem: "com.instanttranslation.macos", category: "translation")
    public init() {}
    public func record(_ event: TranslationLogEvent) {
        logger.info("\(event.description, privacy: .public)")
    }
}
```

- [ ] **Step 5: Run infrastructure tests**

Run: `swift test --filter NetworkingSecurityTests`

Expected: PASS with 4 tests.

- [ ] **Step 6: Commit secure networking**

```bash
git add Package.swift Sources/InstantTranslationInfrastructure Tests/InstantTranslationInfrastructureTests
git commit -m "feat(infrastructure): add secure ephemeral networking"
```

---

### Task 4: Keychain Credentials, Preferences, and Prompt Defaults

**Files:**
- Create: `Sources/InstantTranslationInfrastructure/Storage/CredentialStore.swift`
- Create: `Sources/InstantTranslationInfrastructure/Storage/PreferencesStore.swift`
- Create: `Sources/InstantTranslationInfrastructure/Storage/DefaultPrompts.swift`
- Test: `Tests/InstantTranslationInfrastructureTests/StorageTests.swift`

**Interfaces:**
- Consumes: `PromptPresetID`.
- Produces: `CredentialKey`, `CredentialStoring`, `KeychainCredentialStore`, `KeyboardShortcut`, `AppPreferences`, `PreferencesStoring`, `UserDefaultsPreferencesStore`, and `DefaultPrompts`.

- [ ] **Step 1: Write failing storage tests**

```swift
// Tests/InstantTranslationInfrastructureTests/StorageTests.swift
import XCTest
@testable import InstantTranslationInfrastructure
import InstantTranslationCore

final class StorageTests: XCTestCase {
    func testDefaultPreferencesAreOptInAndTechnologyFocused() async throws {
        let suite = "InstantTranslationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        let preferences = await store.load()
        XCTAssertFalse(preferences.launchAtLogin)
        XCTAssertNil(preferences.globalShortcut)
        XCTAssertFalse(preferences.translateClipboardOnOpen)
        XCTAssertEqual(preferences.defaultPromptPresetID, .technologyAndRnD)
    }

    func testKeychainRoundTripUsesApplicationService() throws {
        let account = "test.\(UUID().uuidString)"
        let store = KeychainCredentialStore(service: "com.instanttranslation.macos.credentials.tests")
        defer { try? store.delete(.custom(account)) }
        try store.write("secret-value", for: .custom(account))
        XCTAssertEqual(try store.read(.custom(account)), "secret-value")
    }
}
```

- [ ] **Step 2: Run the tests and verify the red state**

Run: `swift test --filter StorageTests`

Expected: FAIL because the storage types do not exist.

- [ ] **Step 3: Implement prompt defaults and preferences**

```swift
// Sources/InstantTranslationInfrastructure/Storage/DefaultPrompts.swift
public enum DefaultPrompts {
    public static let general = """
    You are a concise Chinese-English terminology translator. Translate from the supplied source language to the supplied target language. Prefer the established official term when one exists, preserve product names and acronyms, and do not add Markdown. Return one JSON object with exactly two string fields: "translation" for the primary translation and "rationale" for one short reason in the source language.
    """

    public static let technologyAndRnD = """
    You are a Chinese-English terminology translator specializing in software engineering, computer science, product development, and technology R&D. Translate from the supplied source language to the supplied target language. Prefer terminology used in official documentation and established technical literature; preserve product names, code identifiers, and acronyms. Do not add Markdown. Return one JSON object with exactly two string fields: "translation" for the primary translation and "rationale" for one short technical reason in the source language.
    """
}
```

```swift
// Sources/InstantTranslationInfrastructure/Storage/PreferencesStore.swift
import Foundation
import InstantTranslationCore

public struct KeyboardShortcut: Codable, Equatable, Sendable {
    public let keyCode: UInt32
    public let carbonModifiers: UInt32
    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public var launchAtLogin = false
    public var globalShortcut: KeyboardShortcut?
    public var translateClipboardOnOpen = false
    public var llmBaseURL = ""
    public var llmModel = ""
    public var generalPrompt = DefaultPrompts.general
    public var technologyAndRnDPrompt = DefaultPrompts.technologyAndRnD
    public var defaultPromptPresetID = PromptPresetID.technologyAndRnD

    public init() {}
}

public protocol PreferencesStoring: Sendable {
    func load() async -> AppPreferences
    func save(_ preferences: AppPreferences) async throws
}

public actor UserDefaultsPreferencesStore: PreferencesStoring {
    private let defaults: UserDefaults
    private let key = "appPreferences"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> AppPreferences {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(AppPreferences.self, from: data)
        else { return AppPreferences() }
        return value
    }

    public func save(_ preferences: AppPreferences) throws {
        defaults.set(try JSONEncoder().encode(preferences), forKey: key)
    }
}
```

- [ ] **Step 4: Implement Keychain storage with the required accessibility class**

```swift
// Sources/InstantTranslationInfrastructure/Storage/CredentialStore.swift
import Foundation
import Security

public enum CredentialKey: Hashable, Sendable {
    case googleAPIKey
    case llmAPIKey
    case custom(String)

    var account: String {
        switch self {
        case .googleAPIKey: "google-api-key"
        case .llmAPIKey: "llm-api-key"
        case .custom(let value): value
        }
    }
}

public protocol CredentialStoring: Sendable {
    func read(_ key: CredentialKey) throws -> String?
    func write(_ value: String, for key: CredentialKey) throws
    func delete(_ key: CredentialKey) throws
}

public final class KeychainCredentialStore: CredentialStoring, @unchecked Sendable {
    private let service: String
    public init(service: String = "com.instanttranslation.macos.credentials") {
        self.service = service
    }

    public func read(_ key: CredentialKey) throws -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.status(status)
        }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ value: String, for key: CredentialKey) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(baseQuery(key) as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.status(updateStatus)
        }
        var item = baseQuery(key)
        attributes.forEach { item[$0.key] = $0.value }
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    public func delete(_ key: CredentialKey) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    private func baseQuery(_ key: CredentialKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.account,
        ]
    }
}

public enum KeychainError: Error, Equatable, Sendable {
    case status(OSStatus)
}
```

- [ ] **Step 5: Run storage tests and inspect UserDefaults for leaked secrets**

Run: `swift test --filter StorageTests`

Expected: PASS with 2 tests. The temporary UserDefaults suite contains preferences only and never contains `secret-value`.

- [ ] **Step 6: Commit storage**

```bash
git add Sources/InstantTranslationInfrastructure/Storage Tests/InstantTranslationInfrastructureTests/StorageTests.swift
git commit -m "feat(storage): persist preferences and secure credentials"
```

---

### Task 5: Google Cloud Translation Provider

**Files:**
- Create: `Sources/InstantTranslationInfrastructure/Providers/GoogleTranslationProvider.swift`
- Test: `Tests/InstantTranslationInfrastructureTests/GoogleTranslationProviderTests.swift`
- Test support: `Tests/InstantTranslationInfrastructureTests/Support/StubHTTPTransport.swift`

**Interfaces:**
- Consumes: `TranslationProvider`, `HTTPTransport`, `CredentialStoring`, `TranslationRequest`.
- Produces: `GoogleTranslationProvider` with provider ID `.google` and a fixed 15-second request timeout.

- [ ] **Step 1: Create the reusable stub transport and failing Google tests**

```swift
// Tests/InstantTranslationInfrastructureTests/Support/StubHTTPTransport.swift
import Foundation
@testable import InstantTranslationInfrastructure

actor StubHTTPTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    let response: HTTPResponse
    init(statusCode: Int, body: String) {
        response = HTTPResponse(data: Data(body.utf8), statusCode: statusCode)
    }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        return response
    }
}
```

```swift
// Tests/InstantTranslationInfrastructureTests/GoogleTranslationProviderTests.swift
import XCTest
import InstantTranslationCore
@testable import InstantTranslationInfrastructure

final class GoogleTranslationProviderTests: XCTestCase {
    func testBuildsOfficialV2RequestWithHeaderCredentialAndPlainTextBody() async throws {
        let transport = StubHTTPTransport(
            statusCode: 200,
            body: #"{"data":{"translations":[{"translatedText":"Just-in-time compilation"}]}}"#
        )
        let provider = GoogleTranslationProvider(transport: transport) { "google-secret" }
        let request = TranslationRequest(
            id: UUID(), text: "即时编译", inputSource: .manual,
            sourceLanguage: .simplifiedChinese, targetLanguage: .english,
            directionOrigin: .detected, promptPresetID: .technologyAndRnD
        )
        let result = try await provider.translate(request)
        let requests = await transport.requests
        let sent = try XCTUnwrap(requests.first)
        XCTAssertEqual(sent.url?.absoluteString, "https://translation.googleapis.com/language/translate/v2")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Goog-Api-Key"), "google-secret")
        XCTAssertFalse(sent.url?.absoluteString.contains("google-secret") ?? true)
        XCTAssertEqual(result.primaryText, "Just-in-time compilation")
        XCTAssertNil(result.rationale)
    }

    func testMapsAuthenticationAndRateLimitFailures() async {
        for (status, expected) in [(401, TranslationProviderError.invalidCredentials), (429, .rateLimited)] {
            let provider = GoogleTranslationProvider(
                transport: StubHTTPTransport(statusCode: status, body: "{}"),
                apiKey: { "key" }
            )
            do {
                _ = try await provider.translate(Self.request)
                XCTFail("Expected provider error")
            } catch {
                XCTAssertEqual(error as? TranslationProviderError, expected)
            }
        }
    }

    func testMissingKeyIsUnconfigured() async {
        let provider = GoogleTranslationProvider(
            transport: StubHTTPTransport(statusCode: 200, body: "{}"),
            apiKey: { nil }
        )
        do { _ = try await provider.translate(Self.request); XCTFail("Expected unconfigured") }
        catch { XCTAssertEqual(error as? TranslationProviderError, .unconfigured) }
    }

    func testInvalidSuccessPayloadIsRejected() async {
        let provider = GoogleTranslationProvider(
            transport: StubHTTPTransport(statusCode: 200, body: #"{"data":{}}"#),
            apiKey: { "key" }
        )
        do { _ = try await provider.translate(Self.request); XCTFail("Expected invalid response") }
        catch { XCTAssertEqual(error as? TranslationProviderError, .invalidResponse) }
    }

    private static let request = TranslationRequest(
        id: UUID(), text: "compiler", inputSource: .manual,
        sourceLanguage: .english, targetLanguage: .simplifiedChinese,
        directionOrigin: .detected, promptPresetID: .technologyAndRnD
    )
}
```

- [ ] **Step 2: Run the tests and verify the red state**

Run: `swift test --filter GoogleTranslationProviderTests`

Expected: FAIL because `GoogleTranslationProvider` does not exist.

- [ ] **Step 3: Implement the Google provider**

```swift
// Sources/InstantTranslationInfrastructure/Providers/GoogleTranslationProvider.swift
import Foundation
import InstantTranslationCore

public struct GoogleTranslationProvider: TranslationProvider {
    public let id = ProviderID.google
    private let transport: any HTTPTransport
    private let apiKey: @Sendable () async throws -> String?

    public init(
        transport: any HTTPTransport,
        apiKey: @escaping @Sendable () async throws -> String?
    ) {
        self.transport = transport
        self.apiKey = apiKey
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        guard let key = try await apiKey(), !key.isEmpty else {
            throw TranslationProviderError.unconfigured
        }
        let url = URL(string: "https://translation.googleapis.com/language/translate/v2")!
        var urlRequest = URLRequest(url: url, timeoutInterval: 15)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        urlRequest.httpBody = try JSONEncoder().encode(GoogleBody(
            q: request.text,
            source: request.sourceLanguage.googleCode,
            target: request.targetLanguage.googleCode,
            format: "text"
        ))
        let clock = ContinuousClock()
        let start = clock.now
        let response: HTTPResponse
        do { response = try await transport.send(urlRequest) }
        catch { throw ProviderErrorMapper.map(error) }
        guard (200..<300).contains(response.statusCode) else {
            throw ProviderErrorMapper.map(statusCode: response.statusCode)
        }
        let envelope: GoogleEnvelope
        do { envelope = try JSONDecoder().decode(GoogleEnvelope.self, from: response.data) }
        catch { throw TranslationProviderError.invalidResponse }
        guard let translated = envelope.data.translations.first?.translatedText,
              !translated.isEmpty
        else { throw TranslationProviderError.invalidResponse }
        return TranslationResult(
            providerID: id,
            requestID: request.id,
            primaryText: translated,
            rationale: nil,
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage,
            pronunciations: [],
            speakableText: translated,
            duration: start.duration(to: clock.now)
        )
    }
}

private struct GoogleBody: Encodable { let q, source, target, format: String }
private struct GoogleEnvelope: Decodable { let data: GoogleData }
private struct GoogleData: Decodable { let translations: [GoogleTranslation] }
private struct GoogleTranslation: Decodable { let translatedText: String }
```

- [ ] **Step 4: Run Google provider tests**

Run: `swift test --filter GoogleTranslationProviderTests`

Expected: PASS with 4 tests.

- [ ] **Step 5: Commit the Google provider**

```bash
git add Sources/InstantTranslationInfrastructure/Providers/GoogleTranslationProvider.swift Tests/InstantTranslationInfrastructureTests
git commit -m "feat(providers): add Google Cloud translation"
```

---

### Task 6: OpenAI-Compatible Provider, Response Degradation, and Provider Brands

**Files:**
- Create: `Sources/InstantTranslationInfrastructure/Providers/LLMResponseParser.swift`
- Create: `Sources/InstantTranslationInfrastructure/Providers/OpenAICompatibleProvider.swift`
- Create: `Sources/InstantTranslationInfrastructure/Providers/ProviderBrandResolver.swift`
- Test: `Tests/InstantTranslationInfrastructureTests/OpenAICompatibleProviderTests.swift`
- Test: `Tests/InstantTranslationInfrastructureTests/ProviderBrandResolverTests.swift`

**Interfaces:**
- Consumes: `TranslationProvider`, `EndpointPolicy`, `HTTPTransport`, `AppPreferences`, `CredentialStoring`.
- Produces: `LLMProviderConfiguration`, `LLMResponseParser.parse(_:)`, `OpenAICompatibleProvider`, `ProviderBrand`, and `ProviderBrandResolver.resolve(baseURL:)`.

- [ ] **Step 1: Write failing parser, request, and brand tests**

```swift
// Tests/InstantTranslationInfrastructureTests/OpenAICompatibleProviderTests.swift
import XCTest
import InstantTranslationCore
@testable import InstantTranslationInfrastructure

final class OpenAICompatibleProviderTests: XCTestCase {
    func testParsesJSONAndFencedJSONThenDegradesToFirstPlainTextLine() throws {
        XCTAssertEqual(
            try LLMResponseParser.parse(#"{"translation":"compiler","rationale":"Standard term."}"#),
            .init(translation: "compiler", rationale: "Standard term.")
        )
        XCTAssertEqual(
            try LLMResponseParser.parse("```json\n{\"translation\":\"compiler\",\"rationale\":\"Standard term.\"}\n```"),
            .init(translation: "compiler", rationale: "Standard term.")
        )
        XCTAssertEqual(
            try LLMResponseParser.parse("compiler\nAdditional prose"),
            .init(translation: "compiler", rationale: nil)
        )
    }

    func testBuildsNonStreamingChatCompletionsRequest() async throws {
        let transport = StubHTTPTransport(
            statusCode: 200,
            body: #"{"choices":[{"message":{"content":"{\"translation\":\"compiler\",\"rationale\":\"Standard term.\"}"}}]}"#
        )
        let configuration = LLMProviderConfiguration(
            baseURL: "https://api.openai.com/v1",
            apiKey: "llm-secret",
            model: "gpt-5-mini",
            systemPrompt: DefaultPrompts.technologyAndRnD
        )
        let provider = OpenAICompatibleProvider(transport: transport) { _ in configuration }
        let result = try await provider.translate(Self.request)
        let requests = await transport.requests
        let sent = try XCTUnwrap(requests.first)
        XCTAssertEqual(sent.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer llm-secret")
        XCTAssertEqual(result.primaryText, "compiler")
        XCTAssertEqual(result.rationale, "Standard term.")
    }

    func testMissingConfigurationIsUnconfigured() async {
        let provider = OpenAICompatibleProvider(
            transport: StubHTTPTransport(statusCode: 200, body: "{}"),
            configuration: { _ in nil }
        )
        do { _ = try await provider.translate(Self.request); XCTFail("Expected unconfigured") }
        catch { XCTAssertEqual(error as? TranslationProviderError, .unconfigured) }
    }

    func testInvalidChatEnvelopeIsRejected() async {
        let configuration = LLMProviderConfiguration(
            baseURL: "https://api.openai.com/v1", apiKey: "key",
            model: "model", systemPrompt: DefaultPrompts.general
        )
        let provider = OpenAICompatibleProvider(
            transport: StubHTTPTransport(statusCode: 200, body: #"{"choices":[]}"#),
            configuration: { _ in configuration }
        )
        do { _ = try await provider.translate(Self.request); XCTFail("Expected invalid response") }
        catch { XCTAssertEqual(error as? TranslationProviderError, .invalidResponse) }
    }

    private static let request = TranslationRequest(
        id: UUID(), text: "编译器", inputSource: .manual,
        sourceLanguage: .simplifiedChinese, targetLanguage: .english,
        directionOrigin: .detected, promptPresetID: .technologyAndRnD
    )
}
```

```swift
// Tests/InstantTranslationInfrastructureTests/ProviderBrandResolverTests.swift
import XCTest
@testable import InstantTranslationInfrastructure

final class ProviderBrandResolverTests: XCTestCase {
    func testKnownHostsAndGenericFallback() {
        XCTAssertEqual(ProviderBrandResolver.resolve(baseURL: "https://api.openai.com/v1"), .openAI)
        XCTAssertEqual(ProviderBrandResolver.resolve(baseURL: "https://api.deepseek.com/v1"), .deepSeek)
        XCTAssertEqual(ProviderBrandResolver.resolve(baseURL: "https://openrouter.ai/api/v1"), .openRouter)
        XCTAssertEqual(ProviderBrandResolver.resolve(baseURL: "http://localhost:11434/v1"), .genericAI)
    }
}
```

- [ ] **Step 2: Run the tests and verify the red state**

Run: `swift test --filter 'OpenAICompatibleProviderTests|ProviderBrandResolverTests'`

Expected: FAIL because the parser, provider, configuration, and brand resolver do not exist.

- [ ] **Step 3: Implement deterministic response parsing**

```swift
// Sources/InstantTranslationInfrastructure/Providers/LLMResponseParser.swift
import Foundation
import InstantTranslationCore

public struct ParsedLLMResponse: Equatable, Sendable {
    public let translation: String
    public let rationale: String?
    public init(translation: String, rationale: String?) {
        self.translation = translation
        self.rationale = rationale
    }
}

public enum LLMResponseParser {
    public static func parse(_ content: String) throws -> ParsedLLMResponse {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let unfenced: String
        if trimmed.hasPrefix("```") && trimmed.hasSuffix("```") {
            let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
            unfenced = lines.dropFirst().dropLast().joined(separator: "\n")
        } else {
            unfenced = trimmed
        }
        if let data = unfenced.data(using: .utf8),
           let value = try? JSONDecoder().decode(JSONValue.self, from: data),
           !value.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ParsedLLMResponse(
                translation: value.translation.trimmingCharacters(in: .whitespacesAndNewlines),
                rationale: value.rationale?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard let first = unfenced.split(separator: "\n").map(String.init)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty })
        else { throw TranslationProviderError.invalidResponse }
        return ParsedLLMResponse(translation: first, rationale: nil)
    }
}

private struct JSONValue: Decodable {
    let translation: String
    let rationale: String?
}
```

- [ ] **Step 4: Implement the provider and brand resolver**

```swift
// Sources/InstantTranslationInfrastructure/Providers/ProviderBrandResolver.swift
import Foundation

public enum ProviderBrand: String, Equatable, Sendable {
    case googleTranslate, openAI, deepSeek, openRouter, genericAI
}

public enum ProviderBrandResolver {
    public static func resolve(baseURL: String) -> ProviderBrand {
        guard let host = URLComponents(string: baseURL)?.host?.lowercased() else { return .genericAI }
        if host == "api.openai.com" || host.hasSuffix(".openai.com") { return .openAI }
        if host == "api.deepseek.com" || host.hasSuffix(".deepseek.com") { return .deepSeek }
        if host == "openrouter.ai" || host.hasSuffix(".openrouter.ai") { return .openRouter }
        return .genericAI
    }
}
```

```swift
// Sources/InstantTranslationInfrastructure/Providers/OpenAICompatibleProvider.swift
import Foundation
import InstantTranslationCore

public struct LLMProviderConfiguration: Sendable {
    public let baseURL: String
    public let apiKey: String
    public let model: String
    public let systemPrompt: String
    public init(baseURL: String, apiKey: String, model: String, systemPrompt: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
    }
}

public struct OpenAICompatibleProvider: TranslationProvider {
    public let id = ProviderID.llm
    private let transport: any HTTPTransport
    private let configuration: @Sendable (PromptPresetID) async throws -> LLMProviderConfiguration?

    public init(
        transport: any HTTPTransport,
        configuration: @escaping @Sendable (PromptPresetID) async throws -> LLMProviderConfiguration?
    ) {
        self.transport = transport
        self.configuration = configuration
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        guard let configuration = try await configuration(request.promptPresetID),
              !configuration.apiKey.isEmpty,
              !configuration.model.isEmpty,
              !configuration.systemPrompt.isEmpty
        else { throw TranslationProviderError.unconfigured }
        let baseURL = try EndpointPolicy.validatedAPIBaseURL(configuration.baseURL)
        let url = baseURL.appending(path: "chat/completions")
        var urlRequest = URLRequest(url: url, timeoutInterval: 60)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        let userPrompt = "Source language: \(request.sourceLanguage.rawValue)\nTarget language: \(request.targetLanguage.rawValue)\nText: \(request.text)"
        urlRequest.httpBody = try JSONEncoder().encode(ChatRequest(
            model: configuration.model,
            messages: [
                .init(role: "system", content: configuration.systemPrompt),
                .init(role: "user", content: userPrompt),
            ],
            temperature: 0,
            stream: false
        ))
        let clock = ContinuousClock()
        let start = clock.now
        let response: HTTPResponse
        do { response = try await transport.send(urlRequest) }
        catch { throw ProviderErrorMapper.map(error) }
        guard (200..<300).contains(response.statusCode) else {
            throw ProviderErrorMapper.map(statusCode: response.statusCode)
        }
        let envelope: ChatEnvelope
        do { envelope = try JSONDecoder().decode(ChatEnvelope.self, from: response.data) }
        catch { throw TranslationProviderError.invalidResponse }
        guard let content = envelope.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw TranslationProviderError.invalidResponse }
        let parsed = try LLMResponseParser.parse(content)
        return TranslationResult(
            providerID: id, requestID: request.id,
            primaryText: parsed.translation, rationale: parsed.rationale,
            sourceLanguage: request.sourceLanguage, targetLanguage: request.targetLanguage,
            pronunciations: [], speakableText: parsed.translation,
            duration: start.duration(to: clock.now)
        )
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Int
    let stream: Bool
}
private struct ChatMessage: Codable { let role, content: String }
private struct ChatEnvelope: Decodable { let choices: [ChatChoice] }
private struct ChatChoice: Decodable { let message: ChatMessage }
```

- [ ] **Step 5: Run provider tests**

Run: `swift test --filter 'OpenAICompatibleProviderTests|ProviderBrandResolverTests'`

Expected: PASS with 5 tests total.

- [ ] **Step 6: Commit the LLM provider**

```bash
git add Sources/InstantTranslationInfrastructure/Providers Tests/InstantTranslationInfrastructureTests
git commit -m "feat(providers): add OpenAI-compatible translation"
```

---

### Task 7: Concurrent Coordinator and Current-Query Session

**Files:**
- Modify: `Package.swift`
- Create: `Sources/InstantTranslationCore/Translation/TranslationCoordinator.swift`
- Create: `Sources/InstantTranslationFeature/ProviderCardState.swift`
- Create: `Sources/InstantTranslationFeature/TranslationSession.swift`
- Test: `Tests/InstantTranslationCoreTests/TranslationCoordinatorTests.swift`
- Test: `Tests/InstantTranslationFeatureTests/TranslationSessionTests.swift`

**Interfaces:**
- Consumes: `TranslationProvider`, `TranslationRequest`, `ClipboardDecision`, `DirectionResolver`, `PromptPresetID`.
- Produces: `ProviderEvent`, `TranslationCoordinator.events(for:providerIDs:)`, `TranslationCoordinator.retry(providerID:request:)`, `ProviderCardState`, and `@MainActor TranslationSession`.

- [ ] **Step 1: Add the feature target and tests to `Package.swift`**

```swift
// Product entry
.library(name: "InstantTranslationFeature", targets: ["InstantTranslationFeature"]),

// Target entries
.target(
    name: "InstantTranslationFeature",
    dependencies: ["InstantTranslationCore", "InstantTranslationInfrastructure"]
),
.testTarget(
    name: "InstantTranslationFeatureTests",
    dependencies: ["InstantTranslationFeature", "InstantTranslationCore"]
),
```

- [ ] **Step 2: Write failing concurrency and stale-response tests**

```swift
// Tests/InstantTranslationCoreTests/TranslationCoordinatorTests.swift
import XCTest
@testable import InstantTranslationCore

final class TranslationCoordinatorTests: XCTestCase {
    func testPublishesFastProviderWithoutWaitingForSlowProvider() async throws {
        let fast = DelayedProvider(id: .google, delay: .milliseconds(5), text: "fast")
        let slow = DelayedProvider(id: .llm, delay: .milliseconds(100), text: "slow")
        let coordinator = TranslationCoordinator(providers: [fast, slow])
        var iterator = coordinator.events(for: Self.request).makeAsyncIterator()
        let first = await iterator.next()
        guard case .success(let result)? = first else { return XCTFail("Expected success") }
        XCTAssertEqual(result.providerID, .google)
        XCTAssertEqual(result.primaryText, "fast")
    }

    func testLLMCanPublishBeforeGoogle() async {
        let google = DelayedProvider(id: .google, delay: .milliseconds(100), text: "slow")
        let llm = DelayedProvider(id: .llm, delay: .milliseconds(5), text: "fast")
        var iterator = TranslationCoordinator(providers: [google, llm])
            .events(for: Self.request).makeAsyncIterator()
        guard case .success(let result)? = await iterator.next() else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(result.providerID, .llm)
    }

    func testOneFailureDoesNotSuppressOtherSuccess() async {
        let success = DelayedProvider(id: .google, delay: .milliseconds(5), text: "ok")
        let failure = FailingProvider(id: .llm, error: .rateLimited)
        var sawSuccess = false
        var sawFailure = false
        for await event in TranslationCoordinator(providers: [success, failure]).events(for: Self.request) {
            switch event {
            case .success(let result): sawSuccess = result.providerID == .google
            case .failure(let providerID, _, let error):
                sawFailure = providerID == .llm && error == .rateLimited
            }
        }
        XCTAssertTrue(sawSuccess)
        XCTAssertTrue(sawFailure)
    }

    private static let request = TranslationRequest(
        id: UUID(), text: "term", inputSource: .manual,
        sourceLanguage: .english, targetLanguage: .simplifiedChinese,
        directionOrigin: .detected, promptPresetID: .technologyAndRnD
    )
}

private struct DelayedProvider: TranslationProvider {
    let id: ProviderID
    let delay: Duration
    let text: String
    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        try await Task.sleep(for: delay)
        return TranslationResult(
            providerID: id, requestID: request.id, primaryText: text, rationale: nil,
            sourceLanguage: request.sourceLanguage, targetLanguage: request.targetLanguage,
            pronunciations: [], speakableText: text, duration: delay
        )
    }
}

private struct FailingProvider: TranslationProvider {
    let id: ProviderID
    let error: TranslationProviderError
    func translate(_ request: TranslationRequest) async throws -> TranslationResult { throw error }
}
```

```swift
// Tests/InstantTranslationFeatureTests/TranslationSessionTests.swift
import XCTest
import InstantTranslationCore
@testable import InstantTranslationFeature

@MainActor
final class TranslationSessionTests: XCTestCase {
    func testDifferentInputCancelsOldSessionAndRejectsLateEvents() async throws {
        let provider = ControlledProvider(id: .google)
        let coordinator = TranslationCoordinator(providers: [provider])
        let session = TranslationSession(coordinator: coordinator, promptPresetID: .technologyAndRnD)
        session.submit(rawText: "old", sourceID: .manual)
        let oldID = try XCTUnwrap(session.activeRequest?.id)
        session.submit(rawText: "new", sourceID: .manual)
        let newID = try XCTUnwrap(session.activeRequest?.id)
        XCTAssertNotEqual(oldID, newID)
        session.receive(.success(Self.result(requestID: oldID, text: "stale")))
        XCTAssertNotEqual(session.states[.google], .success(Self.result(requestID: oldID, text: "stale")))
    }

    private static func result(requestID: UUID, text: String) -> TranslationResult {
        .init(
            providerID: .google, requestID: requestID, primaryText: text, rationale: nil,
            sourceLanguage: .english, targetLanguage: .simplifiedChinese,
            pronunciations: [], speakableText: text, duration: .zero
        )
    }
}

private struct ControlledProvider: TranslationProvider {
    let id: ProviderID
    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        try await Task.sleep(for: .seconds(5))
        throw TranslationProviderError.cancelled
    }
}
```

- [ ] **Step 3: Run tests and verify the red state**

Run: `swift test --filter 'TranslationCoordinatorTests|TranslationSessionTests'`

Expected: FAIL because the coordinator, events, state, and session do not exist.

- [ ] **Step 4: Implement independent provider event streaming**

```swift
// Sources/InstantTranslationCore/Translation/TranslationCoordinator.swift
import Foundation

public enum ProviderEvent: Sendable {
    case success(TranslationResult)
    case failure(providerID: ProviderID, requestID: UUID, error: TranslationProviderError)
}

public struct TranslationCoordinator: Sendable {
    private let providers: [ProviderID: any TranslationProvider]
    public init(providers: [any TranslationProvider]) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    }

    public func events(
        for request: TranslationRequest,
        providerIDs: Set<ProviderID> = [.google, .llm]
    ) -> AsyncStream<ProviderEvent> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: ProviderEvent.self) { group in
                    for (id, provider) in providers where providerIDs.contains(id) {
                        group.addTask {
                            do { return .success(try await provider.translate(request)) }
                            catch let error as TranslationProviderError {
                                return .failure(providerID: id, requestID: request.id, error: error)
                            }
                            catch {
                                return .failure(providerID: id, requestID: request.id, error: .invalidResponse)
                            }
                        }
                    }
                    for await event in group { continuation.yield(event) }
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func retry(providerID: ProviderID, request: TranslationRequest) async -> ProviderEvent {
        guard let provider = providers[providerID] else {
            return .failure(providerID: providerID, requestID: request.id, error: .unconfigured)
        }
        do { return .success(try await provider.translate(request)) }
        catch let error as TranslationProviderError {
            return .failure(providerID: providerID, requestID: request.id, error: error)
        }
        catch { return .failure(providerID: providerID, requestID: request.id, error: .invalidResponse) }
    }
}
```

- [ ] **Step 5: Implement the main-actor session**

```swift
// Sources/InstantTranslationFeature/ProviderCardState.swift
import Foundation
import InstantTranslationCore

public enum ProviderCardState: Equatable, Sendable {
    case idle
    case loading(requestID: UUID)
    case success(TranslationResult)
    case failure(requestID: UUID, TranslationProviderError)
}
```

```swift
// Sources/InstantTranslationFeature/TranslationSession.swift
import Foundation
import Observation
import InstantTranslationCore

@MainActor @Observable
public final class TranslationSession {
    public var input = ""
    public private(set) var activeRequest: TranslationRequest?
    public private(set) var states: [ProviderID: ProviderCardState] = [
        .google: .idle, .llm: .idle,
    ]
    public private(set) var requiresManualClipboardConfirmation = false
    public var promptPresetID: PromptPresetID
    private let coordinator: TranslationCoordinator
    private let resolver = DirectionResolver()
    private var activeTask: Task<Void, Never>?
    private var retryTasks: [ProviderID: Task<Void, Never>] = [:]

    public init(
        coordinator: TranslationCoordinator,
        promptPresetID: PromptPresetID
    ) {
        self.coordinator = coordinator
        self.promptPresetID = promptPresetID
    }

    public func submit(rawText: String, sourceID: InputSourceID, manualDirection: TranslationDirection? = nil) {
        guard let source = SourceText(rawValue: rawText, sourceID: sourceID) else { return }
        activeTask?.cancel()
        retryTasks.values.forEach { $0.cancel() }
        retryTasks.removeAll(keepingCapacity: true)
        input = source.value
        requiresManualClipboardConfirmation = false
        let direction = manualDirection ?? resolver.resolve(source.value)
        let request = TranslationRequest(
            id: UUID(), text: source.value, inputSource: source.sourceID,
            sourceLanguage: direction.source, targetLanguage: direction.target,
            directionOrigin: manualDirection == nil ? .detected : .manual,
            promptPresetID: promptPresetID
        )
        activeRequest = request
        states[.google] = .loading(requestID: request.id)
        states[.llm] = .loading(requestID: request.id)
        activeTask = Task { [coordinator] in
            for await event in coordinator.events(for: request) {
                guard !Task.isCancelled else { return }
                receive(event)
            }
        }
    }

    public func applyClipboardDecision(_ decision: ClipboardDecision) {
        switch decision {
        case .ignore: break
        case .translate(let source):
            guard source.value != input else { return }
            submit(rawText: source.value, sourceID: .clipboard)
        case .requireConfirmation(let source):
            guard source.value != input else { return }
            activeTask?.cancel()
            retryTasks.values.forEach { $0.cancel() }
            retryTasks.removeAll(keepingCapacity: true)
            input = source.value
            activeRequest = nil
            states[.google] = .idle
            states[.llm] = .idle
            requiresManualClipboardConfirmation = true
        }
    }

    public func receive(_ event: ProviderEvent) {
        guard let request = activeRequest else { return }
        switch event {
        case .success(let result) where result.requestID == request.id:
            states[result.providerID] = .success(result)
        case .failure(let providerID, let requestID, let error) where requestID == request.id:
            states[providerID] = .failure(requestID: requestID, error)
        default: break
        }
    }

    public func swapDirectionAndResubmit() {
        guard let request = activeRequest else {
            guard let source = SourceText(rawValue: input, sourceID: .manual) else { return }
            let detected = resolver.resolve(source.value)
            submit(
                rawText: source.value,
                sourceID: .manual,
                manualDirection: .init(source: detected.target, target: detected.source)
            )
            return
        }
        submit(
            rawText: input,
            sourceID: .manual,
            manualDirection: .init(source: request.targetLanguage, target: request.sourceLanguage)
        )
    }

    public func retry(providerID: ProviderID) {
        guard let request = activeRequest else { return }
        retryTasks[providerID]?.cancel()
        states[providerID] = .loading(requestID: request.id)
        retryTasks[providerID] = Task { [coordinator] in
            receive(await coordinator.retry(providerID: providerID, request: request))
        }
    }

    public func cancelAll() {
        activeTask?.cancel()
        activeTask = nil
        retryTasks.values.forEach { $0.cancel() }
        retryTasks.removeAll()
    }
}
```

- [ ] **Step 6: Run concurrency and session tests**

Run: `swift test --filter 'TranslationCoordinatorTests|TranslationSessionTests'`

Expected: PASS with 8 tests after adding these four cases to `TranslationSessionTests`:

```swift
func testSwapReversesActiveDirectionAndMarksItManual() throws {
    let session = TranslationSession(
        coordinator: TranslationCoordinator(providers: [ControlledProvider(id: .google)]),
        promptPresetID: .technologyAndRnD
    )
    session.submit(rawText: "compiler", sourceID: .manual)
    session.swapDirectionAndResubmit()
    let request = try XCTUnwrap(session.activeRequest)
    XCTAssertEqual(request.sourceLanguage, .simplifiedChinese)
    XCTAssertEqual(request.targetLanguage, .english)
    XCTAssertEqual(request.directionOrigin, .manual)
    session.cancelAll()
}

func testRetryChangesOnlySelectedProviderCard() throws {
    let session = TranslationSession(
        coordinator: TranslationCoordinator(providers: [ControlledProvider(id: .google)]),
        promptPresetID: .technologyAndRnD
    )
    session.submit(rawText: "compiler", sourceID: .manual)
    let requestID = try XCTUnwrap(session.activeRequest?.id)
    let llmResult = Self.result(requestID: requestID, text: "编译器")
    session.receive(.success(TranslationResult(
        providerID: .llm, requestID: llmResult.requestID,
        primaryText: llmResult.primaryText, rationale: nil,
        sourceLanguage: llmResult.sourceLanguage, targetLanguage: llmResult.targetLanguage,
        pronunciations: [], speakableText: llmResult.speakableText, duration: .zero
    )))
    session.retry(providerID: .google)
    XCTAssertEqual(session.states[.google], .loading(requestID: requestID))
    guard case .success(let retained)? = session.states[.llm] else {
        return XCTFail("LLM result must remain visible")
    }
    XCTAssertEqual(retained.primaryText, "编译器")
    session.cancelAll()
}

func testDuplicateClipboardTextDoesNotStartANewRequest() throws {
    let session = TranslationSession(
        coordinator: TranslationCoordinator(providers: [ControlledProvider(id: .google)]),
        promptPresetID: .technologyAndRnD
    )
    session.submit(rawText: "compiler", sourceID: .manual)
    let firstID = try XCTUnwrap(session.activeRequest?.id)
    let clipboard = try XCTUnwrap(SourceText(rawValue: "compiler", sourceID: .clipboard))
    session.applyClipboardDecision(.translate(clipboard))
    XCTAssertEqual(session.activeRequest?.id, firstID)
    session.cancelAll()
}

func testSelectedPromptIsCopiedIntoRequest() {
    let session = TranslationSession(
        coordinator: TranslationCoordinator(providers: [ControlledProvider(id: .google)]),
        promptPresetID: .general
    )
    session.submit(rawText: "compiler", sourceID: .manual)
    XCTAssertEqual(session.activeRequest?.promptPresetID, .general)
    session.cancelAll()
}
```

- [ ] **Step 7: Commit runtime state**

```bash
git add Package.swift Sources/InstantTranslationCore Sources/InstantTranslationFeature Tests
git commit -m "feat(feature): coordinate independent translation sessions"
```

---

### Task 8: AppKit Accessory Shell, Status Item, Transient Popover, and App Bundle

**Files:**
- Modify: `Package.swift`
- Create: `Sources/InstantTranslation/main.swift`
- Create: `Sources/InstantTranslationApp/Application/AppDelegate.swift`
- Create: `Sources/InstantTranslationApp/Application/ApplicationContainer.swift`
- Create: `Sources/InstantTranslationApp/Application/StatusBarController.swift`
- Create: `Sources/InstantTranslationApp/Application/GlobalShortcutRegistrar.swift`
- Create: `Sources/InstantTranslationApp/Popover/TranslationPopoverController.swift`
- Create: `Sources/InstantTranslationApp/Popover/PopoverContentController.swift`
- Create: `Sources/InstantTranslationApp/Popover/ClipboardInputSource.swift`
- Create: `Sources/InstantTranslationApp/Translation/TranslationView.swift`
- Create: `Sources/InstantTranslationApp/Resources/ProviderLogos.xcassets/Contents.json`
- Create: `Config/Info.plist`
- Create: `.gitignore`
- Create: `scripts/package-app.sh`
- Test: `Tests/InstantTranslationAppTests/AppShellTests.swift`

**Interfaces:**
- Consumes: `TranslationSession`, preferences, credential store, coordinator, providers.
- Produces: `AppDelegate`, `ApplicationContainer`, `StatusBarController`, `GlobalShortcutRegistering`, `CarbonGlobalShortcutRegistrar`, `TranslationPopoverController`, `ClipboardInputSource`, executable `InstantTranslation`, and `build/InstantTranslation.app`.

- [ ] **Step 1: Add app library, executable, resources, and app-test targets**

```swift
// Package.swift product entries
.library(name: "InstantTranslationApp", targets: ["InstantTranslationApp"]),
.executable(name: "InstantTranslation", targets: ["InstantTranslation"]),

// Package.swift target entries
.target(
    name: "InstantTranslationApp",
    dependencies: [
        "InstantTranslationCore",
        "InstantTranslationInfrastructure",
        "InstantTranslationFeature",
    ],
    resources: [.process("Resources")]
),
.executableTarget(
    name: "InstantTranslation",
    dependencies: ["InstantTranslationApp"]
),
.testTarget(
    name: "InstantTranslationAppTests",
    dependencies: [
        "InstantTranslationApp",
        "InstantTranslationFeature",
        "InstantTranslationCore",
        "InstantTranslationInfrastructure",
    ]
),
```

Create the resource root immediately so SwiftPM's `.process("Resources")` rule is valid before provider assets arrive in Task 9:

`Sources/InstantTranslationApp/Resources/ProviderLogos.xcassets/Contents.json`:

```json
{
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 2: Write failing shell tests**

```swift
// Tests/InstantTranslationAppTests/AppShellTests.swift
import AppKit
import XCTest
import InstantTranslationInfrastructure
@testable import InstantTranslationApp

@MainActor
final class AppShellTests: XCTestCase {
    func testPopoverIsTransientAndUsesNativeMaterial() {
        let controller = TranslationPopoverController(contentView: NSView())
        XCTAssertEqual(controller.popover.behavior, .transient)
        XCTAssertEqual(controller.contentController.materialView.material, .popover)
    }

    func testStatusBarUsesTemplateSymbolAndHasNoDockActivationPolicy() {
        AppDelegate().configureActivationPolicy()
        let controller = StatusBarController(
            popoverController: TranslationPopoverController(contentView: NSView()),
            shortcutRegistrar: FakeShortcutRegistrar()
        )
        XCTAssertTrue(controller.statusItem.button?.image?.isTemplate ?? false)
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
    }

    func testClipboardSourceIgnoresNonTextPasteboardContent() async throws {
        let source = ClipboardInputSource(readString: { nil })
        XCTAssertNil(try await source.read())
    }
}

private final class FakeShortcutRegistrar: GlobalShortcutRegistering {
    func register(_ shortcut: KeyboardShortcut?, action: @escaping @MainActor () -> Void) throws {}
    func unregister() {}
}
```

- [ ] **Step 3: Run shell tests and verify the red state**

Run: `swift test --filter AppShellTests`

Expected: FAIL because the AppKit shell types do not exist.

- [ ] **Step 4: Implement the entry point, accessory lifecycle, and native popover**

```swift
// Sources/InstantTranslation/main.swift
import AppKit
import InstantTranslationApp

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
```

```swift
// Sources/InstantTranslationApp/Application/AppDelegate.swift
import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var container: ApplicationContainer?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        configureActivationPolicy()
        Task {
            let container = await ApplicationContainer.make()
            self.container = container
            container.start()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        container?.stop()
    }

    public func configureActivationPolicy() {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

```swift
// Sources/InstantTranslationApp/Popover/PopoverContentController.swift
import AppKit

@MainActor
public final class PopoverContentController: NSViewController {
    public let materialView = NSVisualEffectView()

    public init(contentView: NSView) {
        super.init(nibName: nil, bundle: nil)
        materialView.material = .popover
        materialView.blendingMode = .behindWindow
        materialView.state = .followsWindowActiveState
        materialView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view = materialView
        materialView.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: materialView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: materialView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: materialView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: materialView.bottomAnchor),
        ])
        preferredContentSize = NSSize(width: 370, height: 430)
    }

    required init?(coder: NSCoder) { nil }
}
```

```swift
// Sources/InstantTranslationApp/Popover/TranslationPopoverController.swift
import AppKit
import OSLog

@MainActor
public final class TranslationPopoverController {
    public let popover = NSPopover()
    public let contentController: PopoverContentController
    public var onWillShow: (@MainActor () -> Void)?
    private let signposter = OSSignposter(
        subsystem: "com.instanttranslation.macos",
        category: "popover"
    )

    public init(contentView: NSView) {
        contentController = PopoverContentController(contentView: contentView)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = contentController
    }

    public func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown { popover.performClose(nil) }
        else {
            onWillShow?()
            let interval = signposter.beginInterval("PopoverOpen")
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            signposter.endInterval("PopoverOpen", interval)
        }
    }

    public func close() { popover.performClose(nil) }
}
```

- [ ] **Step 5: Implement the status item and permission-free Carbon shortcut**

```swift
// Sources/InstantTranslationApp/Application/GlobalShortcutRegistrar.swift
import Carbon.HIToolbox
import InstantTranslationInfrastructure

@MainActor
public protocol GlobalShortcutRegistering: AnyObject {
    func register(_ shortcut: KeyboardShortcut?, action: @escaping @MainActor () -> Void) throws
    func unregister()
}

public enum ShortcutRegistrationError: Error, Equatable {
    case carbonStatus(OSStatus)
}

@MainActor
public final class CarbonGlobalShortcutRegistrar: GlobalShortcutRegistering {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (@MainActor () -> Void)?

    public func register(_ shortcut: KeyboardShortcut?, action: @escaping @MainActor () -> Void) throws {
        unregister()
        guard let shortcut else { return }
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let owner = Unmanaged<CarbonGlobalShortcutRegistrar>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { owner.action?() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard handlerStatus == noErr else {
            throw ShortcutRegistrationError.carbonStatus(handlerStatus)
        }
        let identifier = EventHotKeyID(signature: OSType(0x4954524E), id: 1)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, identifier, GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr else {
            if let handler { RemoveEventHandler(handler) }
            handler = nil
            throw ShortcutRegistrationError.carbonStatus(status)
        }
    }

    public func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        action = nil
    }
}
```

```swift
// Sources/InstantTranslationApp/Application/StatusBarController.swift
import AppKit
import InstantTranslationInfrastructure

@MainActor
public final class StatusBarController {
    public let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popoverController: TranslationPopoverController
    private let shortcutRegistrar: GlobalShortcutRegistering

    public init(
        popoverController: TranslationPopoverController,
        shortcutRegistrar: GlobalShortcutRegistering
    ) {
        self.popoverController = popoverController
        self.shortcutRegistrar = shortcutRegistrar
        let image = NSImage(systemSymbolName: "character.bubble.fill", accessibilityDescription: "Instant Translation")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let settings = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            settings.target = self
            menu.addItem(.separator())
            let quit = menu.addItem(withTitle: "Quit Instant Translation", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quit.target = NSApp
            statusItem.popUpMenu(menu)
        } else {
            popoverController.toggle(relativeTo: button)
        }
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .openInstantTranslationSettings, object: nil)
    }
}

public extension Notification.Name {
    static let openInstantTranslationSettings = Notification.Name("openInstantTranslationSettings")
}
```

- [ ] **Step 6: Implement clipboard reading on popover open**

```swift
// Sources/InstantTranslationApp/Popover/ClipboardInputSource.swift
import AppKit
import InstantTranslationCore

public struct ClipboardInputSource: InputSource, @unchecked Sendable {
    public let id = InputSourceID.clipboard
    private let readString: @MainActor @Sendable () -> String?
    public init(
        readString: @escaping @MainActor @Sendable () -> String? = {
            NSPasteboard.general.string(forType: .string)
        }
    ) {
        self.readString = readString
    }
    public func read() async throws -> SourceText? {
        await MainActor.run {
            guard let value = readString() else { return nil }
            return SourceText(rawValue: value, sourceID: id)
        }
    }
}
```

Create a deliberately small Task-8 view so the shell compiles before Task 9 replaces its body:

```swift
// Sources/InstantTranslationApp/Translation/TranslationView.swift
import SwiftUI
import InstantTranslationCore
import InstantTranslationFeature

public struct TranslationView: View {
    @Bindable private var session: TranslationSession

    public init(session: TranslationSession) { self.session = session }

    public var body: some View {
        VStack(spacing: 12) {
            TextField("", text: $session.input)
                .textFieldStyle(.roundedBorder)
                .onSubmit { session.submit(rawText: session.input, sourceID: .manual) }
                .accessibilityLabel("Text to translate")
            Text("Enter to translate").font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 370)
    }
}
```

Build the complete composition root instead of letting a view instantiate services:

```swift
// Sources/InstantTranslationApp/Application/ApplicationContainer.swift
import AppKit
import OSLog
import SwiftUI
import InstantTranslationCore
import InstantTranslationFeature
import InstantTranslationInfrastructure

@MainActor
public final class ApplicationContainer {
    public let session: TranslationSession
    public let preferencesStore: any PreferencesStoring
    public let credentialStore: any CredentialStoring
    public let statusBarController: StatusBarController
    public let popoverController: TranslationPopoverController

    private let shortcutRegistrar: GlobalShortcutRegistering
    private let clipboardSource: any InputSource
    private let logger = Logger(subsystem: "com.instanttranslation.macos", category: "application")

    private init(
        session: TranslationSession,
        preferencesStore: any PreferencesStoring,
        credentialStore: any CredentialStoring,
        statusBarController: StatusBarController,
        popoverController: TranslationPopoverController,
        shortcutRegistrar: GlobalShortcutRegistering,
        clipboardSource: any InputSource
    ) {
        self.session = session
        self.preferencesStore = preferencesStore
        self.credentialStore = credentialStore
        self.statusBarController = statusBarController
        self.popoverController = popoverController
        self.shortcutRegistrar = shortcutRegistrar
        self.clipboardSource = clipboardSource
    }

    public static func make() async -> ApplicationContainer {
        let preferencesStore = UserDefaultsPreferencesStore()
        let credentialStore = KeychainCredentialStore()
        let transport = URLSessionHTTPTransport()
        let google = GoogleTranslationProvider(transport: transport) {
            try credentialStore.read(.googleAPIKey)
        }
        let llm = OpenAICompatibleProvider(transport: transport) { presetID in
            let preferences = await preferencesStore.load()
            guard let apiKey = try credentialStore.read(.llmAPIKey),
                  !apiKey.isEmpty,
                  !preferences.llmBaseURL.isEmpty,
                  !preferences.llmModel.isEmpty
            else { return nil }
            let prompt = presetID == .general
                ? preferences.generalPrompt
                : preferences.technologyAndRnDPrompt
            return LLMProviderConfiguration(
                baseURL: preferences.llmBaseURL,
                apiKey: apiKey,
                model: preferences.llmModel,
                systemPrompt: prompt
            )
        }
        let preferences = await preferencesStore.load()
        let coordinator = TranslationCoordinator(providers: [google, llm])
        let session = TranslationSession(
            coordinator: coordinator,
            promptPresetID: preferences.defaultPromptPresetID
        )
        let content = NSHostingView(rootView: TranslationView(session: session))
        let popover = TranslationPopoverController(contentView: content)
        let shortcut = CarbonGlobalShortcutRegistrar()
        let statusBar = StatusBarController(
            popoverController: popover,
            shortcutRegistrar: shortcut
        )
        let container = ApplicationContainer(
            session: session,
            preferencesStore: preferencesStore,
            credentialStore: credentialStore,
            statusBarController: statusBar,
            popoverController: popover,
            shortcutRegistrar: shortcut,
            clipboardSource: ClipboardInputSource()
        )
        popover.onWillShow = { [weak container] in container?.prepareClipboard() }
        return container
    }

    public func start() {
        Task {
            let preferences = await preferencesStore.load()
            do {
                try shortcutRegistrar.register(preferences.globalShortcut) { [weak statusBarController] in
                    statusBarController?.toggleFromShortcut()
                }
            } catch {
                logger.error("shortcut registration failed")
            }
        }
    }

    public func stop() {
        shortcutRegistrar.unregister()
        session.cancelAll()
    }

    private func prepareClipboard() {
        Task {
            let preferences = await preferencesStore.load()
            guard preferences.translateClipboardOnOpen else { return }
            do {
                let text = try await clipboardSource.read()
                session.applyClipboardDecision(ClipboardTextPolicy().evaluate(text?.value))
            } catch {
                logger.error("clipboard read failed")
            }
        }
    }
}
```

Add this public method to `StatusBarController`; it is the single path used by the optional shortcut:

```swift
public func toggleFromShortcut() {
    guard let button = statusItem.button else { return }
    popoverController.toggle(relativeTo: button)
}
```

The transient popover does not call `session.cancelAll()` on close, so a request continues while the user clicks elsewhere. Only process termination cancels it.

- [ ] **Step 7: Create the bundle metadata and deterministic packaging script**

```xml
<!-- Config/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>InstantTranslation</string>
  <key>CFBundleIdentifier</key><string>com.instanttranslation.macos</string>
  <key>CFBundleName</key><string>Instant Translation</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
```

```bash
#!/usr/bin/env bash
# scripts/package-app.sh
set -euo pipefail
swift build -c release
APP="build/InstantTranslation.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/InstantTranslation "$APP/Contents/MacOS/InstantTranslation"
cp Config/Info.plist "$APP/Contents/Info.plist"
find .build/release -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;
codesign --force --deep --sign - "$APP"
echo "$APP"
```

Run `chmod +x scripts/package-app.sh`. Add `.build/`, `build/`, `.swiftpm/`, and `.DS_Store` to `.gitignore`; do not ignore `Package.resolved` if one is introduced later.

- [ ] **Step 8: Run shell tests and build the `.app`**

Run: `swift test --filter AppShellTests && bash scripts/package-app.sh`

Expected: tests PASS; `build/InstantTranslation.app/Contents/MacOS/InstantTranslation` exists; `plutil -p build/InstantTranslation.app/Contents/Info.plist` shows `LSUIElement => true` and no protected-resource usage-description keys.

- [ ] **Step 9: Commit the application shell**

```bash
git add .gitignore Package.swift Sources/InstantTranslation Sources/InstantTranslationApp Config scripts/package-app.sh Tests/InstantTranslationAppTests
git commit -m "feat(app): add native menu bar shell"
```

---

### Task 9: Translation UI, Provider Logos, Copy Feedback, and Accessibility

**Files:**
- Modify: `Sources/InstantTranslationApp/Application/ApplicationContainer.swift`
- Modify: `Sources/InstantTranslationApp/Translation/TranslationView.swift`
- Create: `Sources/InstantTranslationApp/Translation/ResultCardView.swift`
- Create: `Sources/InstantTranslationApp/Translation/ProviderIconView.swift`
- Create: `Sources/InstantTranslationApp/Translation/CopyController.swift`
- Modify: `Sources/InstantTranslationApp/Resources/ProviderLogos.xcassets/Contents.json`
- Create: provider imagesets for `GoogleTranslate`, `OpenAI`, `DeepSeek`, and `OpenRouter`
- Create: `THIRD_PARTY_NOTICES.md`
- Test: `Tests/InstantTranslationAppTests/TranslationPresentationTests.swift`

**Interfaces:**
- Consumes: `TranslationSession`, `ProviderCardState`, `ProviderBrandResolver`.
- Produces: `TranslationView`, `ResultCardView`, `ProviderIconView`, `PasteboardWriting`, and `CopyController.copy(_:)`.

- [ ] **Step 1: Write failing copy and presentation-policy tests**

```swift
// Tests/InstantTranslationAppTests/TranslationPresentationTests.swift
import XCTest
import InstantTranslationCore
@testable import InstantTranslationApp

@MainActor
final class TranslationPresentationTests: XCTestCase {
    func testLLMCopyWritesPrimaryTranslationWithoutRationale() {
        let pasteboard = FakePasteboard()
        let controller = CopyController(pasteboard: pasteboard)
        let result = TranslationResult(
            providerID: .llm, requestID: UUID(), primaryText: "compiler",
            rationale: "Standard term.", sourceLanguage: .simplifiedChinese,
            targetLanguage: .english, pronunciations: [], speakableText: "compiler",
            duration: .zero
        )
        controller.copy(result)
        XCTAssertEqual(pasteboard.value, "compiler")
        XCTAssertEqual(controller.copiedProviderID, .llm)
    }

    func testAccessibilityLabelsAreStable() {
        XCTAssertEqual(TranslationAccessibility.copyLabel(providerID: .google), "Copy Google translation")
        XCTAssertEqual(TranslationAccessibility.copyLabel(providerID: .llm), "Copy LLM translation")
    }

    func testCopyFeedbackMovesIndependentlyBetweenProviderCards() {
        let pasteboard = FakePasteboard()
        let controller = CopyController(pasteboard: pasteboard)
        let requestID = UUID()
        let google = TranslationResult(
            providerID: .google, requestID: requestID, primaryText: "编译器",
            rationale: nil, sourceLanguage: .english, targetLanguage: .simplifiedChinese,
            pronunciations: [], speakableText: "编译器", duration: .zero
        )
        let llm = TranslationResult(
            providerID: .llm, requestID: requestID, primaryText: "compiler",
            rationale: "Standard term.", sourceLanguage: .simplifiedChinese, targetLanguage: .english,
            pronunciations: [], speakableText: "compiler", duration: .zero
        )
        controller.copy(google)
        XCTAssertEqual(controller.copiedProviderID, .google)
        controller.copy(llm)
        XCTAssertEqual(controller.copiedProviderID, .llm)
        XCTAssertEqual(pasteboard.value, "compiler")
    }
}

@MainActor private final class FakePasteboard: PasteboardWriting {
    var value: String?
    func write(_ value: String) -> Bool { self.value = value; return true }
}
```

- [ ] **Step 2: Run the tests and verify the red state**

Run: `swift test --filter TranslationPresentationTests`

Expected: FAIL because the copy and accessibility types do not exist.

- [ ] **Step 3: Implement copy behavior and accessibility copy**

```swift
// Sources/InstantTranslationApp/Translation/CopyController.swift
import AppKit
import Observation
import InstantTranslationCore

@MainActor public protocol PasteboardWriting: AnyObject {
    func write(_ value: String) -> Bool
}

@MainActor public final class SystemPasteboardWriter: PasteboardWriting {
    public func write(_ value: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(value, forType: .string)
    }
}

@MainActor @Observable
public final class CopyController {
    public private(set) var copiedProviderID: ProviderID?
    public private(set) var failedProviderID: ProviderID?
    private let pasteboard: PasteboardWriting
    private var resetTask: Task<Void, Never>?

    public init(pasteboard: PasteboardWriting = SystemPasteboardWriter()) {
        self.pasteboard = pasteboard
    }

    public func copy(_ result: TranslationResult) {
        resetTask?.cancel()
        if pasteboard.write(result.primaryText) {
            copiedProviderID = result.providerID
            failedProviderID = nil
            resetTask = Task {
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                if copiedProviderID == result.providerID { copiedProviderID = nil }
            }
        } else {
            failedProviderID = result.providerID
        }
    }
}

public enum TranslationAccessibility {
    public static func copyLabel(providerID: ProviderID) -> String {
        providerID == .google ? "Copy Google translation" : "Copy LLM translation"
    }
}
```

- [ ] **Step 4: Vendor pinned CC0 provider marks as bundled assets**

Use Simple Icons `16.28.0` only as the build-time source for these four SVG files:

```text
https://raw.githubusercontent.com/simple-icons/simple-icons/16.28.0/icons/googletranslate.svg
https://raw.githubusercontent.com/simple-icons/simple-icons/16.28.0/icons/openai.svg
https://raw.githubusercontent.com/simple-icons/simple-icons/16.28.0/icons/deepseek.svg
https://raw.githubusercontent.com/simple-icons/simple-icons/16.28.0/icons/openrouter.svg
```

Create these exact paths:

```text
Sources/InstantTranslationApp/Resources/ProviderLogos.xcassets/GoogleTranslate.imageset/googletranslate.svg
Sources/InstantTranslationApp/Resources/ProviderLogos.xcassets/OpenAI.imageset/openai.svg
Sources/InstantTranslationApp/Resources/ProviderLogos.xcassets/DeepSeek.imageset/deepseek.svg
Sources/InstantTranslationApp/Resources/ProviderLogos.xcassets/OpenRouter.imageset/openrouter.svg
```

Each adjacent `Contents.json` uses the matching filename. For example, Google is:

```json
{
  "images" : [{ "filename" : "googletranslate.svg", "idiom" : "universal" }],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "template"
  }
}
```

Use these complete objects for the remaining files:

`OpenAI.imageset/Contents.json`:

```json
{
  "images" : [{ "filename" : "openai.svg", "idiom" : "universal" }],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" }
}
```

`DeepSeek.imageset/Contents.json`:

```json
{
  "images" : [{ "filename" : "deepseek.svg", "idiom" : "universal" }],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" }
}
```

`OpenRouter.imageset/Contents.json`:

```json
{
  "images" : [{ "filename" : "openrouter.svg", "idiom" : "universal" }],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" }
}
```

Record Simple Icons version `16.28.0`, CC0-1.0, all four source URLs, and a statement that the provider names and marks remain their owners' trademarks in `THIRD_PARTY_NOTICES.md`. Verify that `rg -n 'https?://' Sources/InstantTranslationApp` finds no runtime icon URL strings; URLs may appear only in `THIRD_PARTY_NOTICES.md`.

- [ ] **Step 5: Implement the single-column native translation view**

Use an observable presentation value so changing the LLM Base URL can update the logo without coupling the feature target to provider branding:

```swift
// Sources/InstantTranslationApp/Translation/ProviderIconView.swift
import Observation
import SwiftUI
import InstantTranslationCore
import InstantTranslationInfrastructure

@MainActor @Observable
public final class ProviderAppearance {
    public var llmBrand: ProviderBrand
    public init(llmBrand: ProviderBrand) { self.llmBrand = llmBrand }
}

public struct ProviderIconView: View {
    public let providerID: ProviderID
    public let llmBrand: ProviderBrand

    public var body: some View {
        let brand = providerID == .google ? ProviderBrand.googleTranslate : llmBrand
        Group {
            if brand == .genericAI {
                Image(systemName: "sparkles")
            } else {
                Image(assetName(brand), bundle: .module)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }

    private func assetName(_ brand: ProviderBrand) -> String {
        switch brand {
        case .googleTranslate: "GoogleTranslate"
        case .openAI: "OpenAI"
        case .deepSeek: "DeepSeek"
        case .openRouter: "OpenRouter"
        case .genericAI: ""
        }
    }
}
```

```swift
// Sources/InstantTranslationApp/Translation/TranslationView.swift
import SwiftUI
import InstantTranslationCore
import InstantTranslationFeature

@MainActor
public struct TranslationView: View {
    @Bindable private var session: TranslationSession
    @Bindable private var appearance: ProviderAppearance
    @State private var copyController: CopyController
    @FocusState private var inputFocused: Bool

    public init(session: TranslationSession, appearance: ProviderAppearance) {
        self.session = session
        self.appearance = appearance
        _copyController = State(initialValue: CopyController())
    }

    private var shownDirection: TranslationDirection {
        if let request = session.activeRequest {
            return .init(source: request.sourceLanguage, target: request.targetLanguage)
        }
        return DirectionResolver().resolve(session.input)
    }

    public var body: some View {
        VStack(spacing: 10) {
            DirectionControl(direction: shownDirection) { session.swapDirectionAndResubmit() }
            TextField("", text: $session.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .onSubmit { session.submit(rawText: session.input, sourceID: .manual) }
                .accessibilityLabel("Text to translate")
            HStack {
                if session.requiresManualClipboardConfirmation {
                    Text("Clipboard text exceeds 500 characters. Press Enter to translate.")
                }
                Spacer()
                Text("Enter to translate")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ResultCardView(
                providerID: .google,
                state: session.states[.google] ?? .idle,
                llmBrand: appearance.llmBrand,
                copyController: copyController,
                retry: { session.retry(providerID: .google) }
            )
            ResultCardView(
                providerID: .llm,
                state: session.states[.llm] ?? .idle,
                llmBrand: appearance.llmBrand,
                copyController: copyController,
                retry: { session.retry(providerID: .llm) }
            )
        }
        .padding(14)
        .frame(width: 370)
        .background(.clear)
        .onAppear { inputFocused = true }
    }
}

private struct DirectionControl: View {
    let direction: TranslationDirection
    let swap: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Text("\(shortName(direction.source)) → \(shortName(direction.target))")
            Button(action: swap) { Image(systemName: "arrow.left.arrow.right") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Swap translation direction")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func shortName(_ language: LanguageID) -> String {
        language == .simplifiedChinese ? "中" : "英"
    }
}
```

```swift
// Sources/InstantTranslationApp/Translation/ResultCardView.swift
import SwiftUI
import InstantTranslationCore
import InstantTranslationFeature
import InstantTranslationInfrastructure

@MainActor
public struct ResultCardView: View {
    let providerID: ProviderID
    let state: ProviderCardState
    let llmBrand: ProviderBrand
    @Bindable var copyController: CopyController
    let retry: () -> Void

    public init(
        providerID: ProviderID,
        state: ProviderCardState,
        llmBrand: ProviderBrand,
        copyController: CopyController,
        retry: @escaping () -> Void
    ) {
        self.providerID = providerID
        self.state = state
        self.llmBrand = llmBrand
        self.copyController = copyController
        self.retry = retry
    }

    public var body: some View {
        Group {
            switch state {
            case .idle:
                Color.clear.frame(height: 52)
            case .loading:
                HStack {
                    ProviderIconView(providerID: providerID, llmBrand: llmBrand)
                    ProgressView().controlSize(.small)
                    Spacer()
                }
            case .success(let result):
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ProviderIconView(providerID: providerID, llmBrand: llmBrand)
                        Spacer()
                        Button {
                            copyController.copy(result)
                        } label: {
                            Image(systemName: copyController.copiedProviderID == providerID ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(TranslationAccessibility.copyLabel(providerID: providerID))
                    }
                    Text(result.primaryText).textSelection(.enabled)
                    if let rationale = result.rationale, !rationale.isEmpty {
                        Text(rationale).font(.caption).foregroundStyle(.secondary)
                    }
                    if copyController.failedProviderID == providerID {
                        Text("Copy failed").font(.caption).foregroundStyle(.red)
                    }
                }
            case .failure(_, let error):
                HStack(alignment: .top) {
                    ProviderIconView(providerID: providerID, llmBrand: llmBrand)
                    Text(message(for: error)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry", action: retry).controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    private func message(for error: TranslationProviderError) -> String {
        switch error {
        case .unconfigured: "Configure this service in Settings."
        case .invalidCredentials: "Check the API key."
        case .rateLimited: "Rate limit reached. Try again later."
        case .networkUnavailable: "Network unavailable."
        case .timedOut: "Request timed out."
        case .insecureEndpoint: "The Base URL is not allowed."
        case .invalidResponse: "The service returned an invalid response."
        case .server(let statusCode): "Service error (\(statusCode))."
        case .cancelled: "Request cancelled."
        }
    }
}
```

This switch renders every provider independently. Copy writes only `primaryText`, never closes the popover, and uses a credential-free error message.

In `ApplicationContainer.make()`, resolve the initial appearance from the already-loaded preferences, pass it to the view, and retain it for Task 10:

```swift
let appearance = ProviderAppearance(
    llmBrand: ProviderBrandResolver.resolve(baseURL: preferences.llmBaseURL)
)
let content = NSHostingView(rootView: TranslationView(session: session, appearance: appearance))
```

Add this retained property:

```swift
public let providerAppearance: ProviderAppearance
```

Append `providerAppearance: ProviderAppearance` to the private initializer, assign `self.providerAppearance = providerAppearance`, and pass `providerAppearance: appearance` in the `ApplicationContainer(...)` construction call. Provider icons are selected only from bundled assets and never initiate network work. Do not place the visible words “Google Translate,” “LLM,” “General,” “Technology & R&D,” or “Input term” in the main popover.

- [ ] **Step 6: Verify reduced-transparency and contrast behavior in code**

Add this observer and update method to `PopoverContentController`, calling `updateMaterial()` at the end of `init`:

```swift
private var accessibilityObserver: NSObjectProtocol?

private func startObservingAccessibilityDisplayOptions() {
    accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        MainActor.assumeIsolated { self?.updateMaterial() }
    }
}

private func updateMaterial() {
    materialView.wantsLayer = true
    if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
        materialView.material = .windowBackground
        materialView.blendingMode = .withinWindow
        materialView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    } else {
        materialView.material = .popover
        materialView.blendingMode = .behindWindow
        materialView.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

deinit {
    if let accessibilityObserver {
        NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
    }
}
```

Call `startObservingAccessibilityDisplayOptions()` once from `init`. Keep all SwiftUI foregrounds and separators semantic (`.primary`, `.secondary`, and `Color(nsColor: .separatorColor)`); do not hard-code light/dark RGB surfaces.

- [ ] **Step 7: Run presentation tests and package resources**

Run: `swift test --filter TranslationPresentationTests && bash scripts/package-app.sh`

Expected: tests PASS; the app resource bundle contains the four logo assets; `strings build/InstantTranslation.app/Contents/MacOS/InstantTranslation | rg 'cdn.simpleicons|raw.githubusercontent'` returns no output.

- [ ] **Step 8: Commit translation presentation**

```bash
git add Sources/InstantTranslationApp Tests/InstantTranslationAppTests THIRD_PARTY_NOTICES.md
git commit -m "feat(ui): add dual-source translation popover"
```

---

### Task 10: Settings, Launch at Login, Shortcut Recording, and Connection Tests

**Files:**
- Create: `Sources/InstantTranslationApp/Application/LaunchAtLoginController.swift`
- Create: `Sources/InstantTranslationApp/Settings/SettingsWindowController.swift`
- Create: `Sources/InstantTranslationApp/Settings/SettingsViewModel.swift`
- Create: `Sources/InstantTranslationApp/Settings/SettingsView.swift`
- Create: `Sources/InstantTranslationApp/Settings/ShortcutCaptureView.swift`
- Modify: `Sources/InstantTranslationApp/Application/ApplicationContainer.swift`
- Modify: `Sources/InstantTranslationApp/Application/StatusBarController.swift`
- Test: `Tests/InstantTranslationAppTests/SettingsViewModelTests.swift`
- Test support: `Tests/InstantTranslationAppTests/Support/SettingsFakes.swift`

**Interfaces:**
- Consumes: `PreferencesStoring`, `CredentialStoring`, `TranslationCoordinator`, `GlobalShortcutRegistering`.
- Produces: `LaunchAtLoginControlling`, `LaunchAtLoginController`, `SettingsViewModel`, `SettingsWindowController`, and `ShortcutCaptureView`.

- [ ] **Step 1: Write failing settings tests**

```swift
// Tests/InstantTranslationAppTests/SettingsViewModelTests.swift
import XCTest
import InstantTranslationCore
import InstantTranslationInfrastructure
@testable import InstantTranslationApp

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testSavesSecretsToCredentialStoreAndNotPreferences() async throws {
        let preferences = MemoryPreferencesStore()
        let credentials = MemoryCredentialStore()
        let model = await SettingsViewModel.make(
            preferencesStore: preferences,
            credentialStore: credentials,
            launchAtLogin: FakeLaunchAtLoginController(),
            shortcutRegistrar: FakeSettingsShortcutRegistrar(),
            shortcutAction: {},
            connectionTester: FakeConnectionTester(),
            providerAppearance: ProviderAppearance(llmBrand: .genericAI),
            session: nil
        )
        model.googleAPIKey = "google-secret"
        model.llmAPIKey = "llm-secret"
        model.llmBaseURL = "https://api.openai.com/v1"
        model.llmModel = "gpt-5-mini"
        try await model.save()
        XCTAssertEqual(try credentials.read(.googleAPIKey), "google-secret")
        XCTAssertEqual(try credentials.read(.llmAPIKey), "llm-secret")
        let storedPreferences = await preferences.load()
        let encodedPreferences = String(data: try JSONEncoder().encode(storedPreferences), encoding: .utf8)
        XCTAssertFalse(encodedPreferences?.contains("google-secret") ?? true)
        XCTAssertFalse(encodedPreferences?.contains("llm-secret") ?? true)
    }

    func testRestoresEachPromptIndependently() async throws {
        let model = await SettingsViewModel.make(
            preferencesStore: MemoryPreferencesStore(),
            credentialStore: MemoryCredentialStore(),
            launchAtLogin: FakeLaunchAtLoginController(),
            shortcutRegistrar: FakeSettingsShortcutRegistrar(),
            shortcutAction: {},
            connectionTester: FakeConnectionTester(),
            providerAppearance: ProviderAppearance(llmBrand: .genericAI),
            session: nil
        )
        model.generalPrompt = "changed general"
        model.technologyAndRnDPrompt = "changed tech"
        model.restoreGeneralPrompt()
        XCTAssertEqual(model.generalPrompt, DefaultPrompts.general)
        XCTAssertEqual(model.technologyAndRnDPrompt, "changed tech")
    }
}
```

```swift
// Tests/InstantTranslationAppTests/Support/SettingsFakes.swift
import Foundation
import InstantTranslationInfrastructure
@testable import InstantTranslationApp

actor MemoryPreferencesStore: PreferencesStoring {
    private var value: AppPreferences
    init(_ value: AppPreferences = AppPreferences()) { self.value = value }
    func load() -> AppPreferences { value }
    func save(_ preferences: AppPreferences) { value = preferences }
}

final class MemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [CredentialKey: String] = [:]
    func read(_ key: CredentialKey) -> String? { lock.withLock { values[key] } }
    func write(_ value: String, for key: CredentialKey) { lock.withLock { values[key] = value } }
    func delete(_ key: CredentialKey) { lock.withLock { values[key] = nil } }
}

@MainActor final class FakeLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled = false
    func setEnabled(_ enabled: Bool) { isEnabled = enabled }
}

@MainActor final class FakeSettingsShortcutRegistrar: GlobalShortcutRegistering {
    private(set) var registeredShortcut: KeyboardShortcut?
    func register(_ shortcut: KeyboardShortcut?, action: @escaping @MainActor () -> Void) {
        registeredShortcut = shortcut
    }
    func unregister() { registeredShortcut = nil }
}

struct FakeConnectionTester: ProviderConnectionTesting {
    var result: ConnectionTestState = .success
    func testGoogle(apiKey: String) async -> ConnectionTestState { result }
    func testLLM(configuration: LLMProviderConfiguration) async -> ConnectionTestState { result }
}
```

These fakes make no UserDefaults, Keychain, ServiceManagement, Carbon, pasteboard, or network calls.

- [ ] **Step 2: Run settings tests and verify the red state**

Run: `swift test --filter SettingsViewModelTests`

Expected: FAIL because the Settings view model and launch-at-login contracts do not exist.

- [ ] **Step 3: Implement launch-at-login and settings persistence**

```swift
// Sources/InstantTranslationApp/Application/LaunchAtLoginController.swift
import ServiceManagement

@MainActor public protocol LaunchAtLoginControlling: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor public final class LaunchAtLoginController: LaunchAtLoginControlling {
    public var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    public func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
}
```

Define connection tests as an injected boundary so Settings tests never contact real services:

```swift
// At the top of Sources/InstantTranslationApp/Settings/SettingsViewModel.swift
import Foundation
import Observation
import InstantTranslationCore
import InstantTranslationFeature
import InstantTranslationInfrastructure

public enum ConnectionTestState: Equatable, Sendable {
    case idle, testing, success
    case failure(TranslationProviderError)
}

public protocol ProviderConnectionTesting: Sendable {
    func testGoogle(apiKey: String) async -> ConnectionTestState
    func testLLM(configuration: LLMProviderConfiguration) async -> ConnectionTestState
}

public struct ProviderConnectionTester: ProviderConnectionTesting {
    private let transport: any HTTPTransport
    public init(transport: any HTTPTransport) { self.transport = transport }

    public func testGoogle(apiKey: String) async -> ConnectionTestState {
        await test(GoogleTranslationProvider(transport: transport) { apiKey }, preset: .general)
    }

    public func testLLM(configuration: LLMProviderConfiguration) async -> ConnectionTestState {
        await test(OpenAICompatibleProvider(transport: transport) { _ in configuration }, preset: .general)
    }

    private func test(_ provider: any TranslationProvider, preset: PromptPresetID) async -> ConnectionTestState {
        let request = TranslationRequest(
            id: UUID(), text: "test", inputSource: .manual,
            sourceLanguage: .english, targetLanguage: .simplifiedChinese,
            directionOrigin: .manual, promptPresetID: preset
        )
        do { _ = try await provider.translate(request); return .success }
        catch let error as TranslationProviderError { return .failure(error) }
        catch { return .failure(.invalidResponse) }
    }
}
```

Add the view model below the connection tester in the same file:

```swift
@MainActor @Observable
public final class SettingsViewModel {
    public var launchAtLogin: Bool
    public var globalShortcut: KeyboardShortcut?
    public var translateClipboardOnOpen: Bool
    public var llmBaseURL: String
    public var llmModel: String
    public var generalPrompt: String
    public var technologyAndRnDPrompt: String
    public var defaultPromptPresetID: PromptPresetID
    public var googleAPIKey: String
    public var llmAPIKey: String
    public private(set) var googleConnectionState = ConnectionTestState.idle
    public private(set) var llmConnectionState = ConnectionTestState.idle
    public private(set) var saveError: String?

    private let preferencesStore: any PreferencesStoring
    private let credentialStore: any CredentialStoring
    private let launchController: LaunchAtLoginControlling
    private let shortcutRegistrar: GlobalShortcutRegistering
    private let shortcutAction: @MainActor () -> Void
    private let connectionTester: any ProviderConnectionTesting
    private let providerAppearance: ProviderAppearance
    private weak var session: TranslationSession?

    public static func make(
        preferencesStore: any PreferencesStoring,
        credentialStore: any CredentialStoring,
        launchAtLogin: LaunchAtLoginControlling,
        shortcutRegistrar: GlobalShortcutRegistering,
        shortcutAction: @escaping @MainActor () -> Void,
        connectionTester: any ProviderConnectionTesting,
        providerAppearance: ProviderAppearance,
        session: TranslationSession?
    ) async -> SettingsViewModel {
        let preferences = await preferencesStore.load()
        let googleAPIKey = (try? credentialStore.read(.googleAPIKey)) ?? ""
        let llmAPIKey = (try? credentialStore.read(.llmAPIKey)) ?? ""
        return SettingsViewModel(
            preferences: preferences,
            googleAPIKey: googleAPIKey,
            llmAPIKey: llmAPIKey,
            actualLaunchAtLogin: launchAtLogin.isEnabled,
            preferencesStore: preferencesStore,
            credentialStore: credentialStore,
            launchController: launchAtLogin,
            shortcutRegistrar: shortcutRegistrar,
            shortcutAction: shortcutAction,
            connectionTester: connectionTester,
            providerAppearance: providerAppearance,
            session: session
        )
    }

    private init(
        preferences: AppPreferences,
        googleAPIKey: String,
        llmAPIKey: String,
        actualLaunchAtLogin: Bool,
        preferencesStore: any PreferencesStoring,
        credentialStore: any CredentialStoring,
        launchController: LaunchAtLoginControlling,
        shortcutRegistrar: GlobalShortcutRegistering,
        shortcutAction: @escaping @MainActor () -> Void,
        connectionTester: any ProviderConnectionTesting,
        providerAppearance: ProviderAppearance,
        session: TranslationSession?
    ) {
        launchAtLogin = actualLaunchAtLogin
        globalShortcut = preferences.globalShortcut
        translateClipboardOnOpen = preferences.translateClipboardOnOpen
        llmBaseURL = preferences.llmBaseURL
        llmModel = preferences.llmModel
        generalPrompt = preferences.generalPrompt
        technologyAndRnDPrompt = preferences.technologyAndRnDPrompt
        defaultPromptPresetID = preferences.defaultPromptPresetID
        self.googleAPIKey = googleAPIKey
        self.llmAPIKey = llmAPIKey
        self.preferencesStore = preferencesStore
        self.credentialStore = credentialStore
        self.launchController = launchController
        self.shortcutRegistrar = shortcutRegistrar
        self.shortcutAction = shortcutAction
        self.connectionTester = connectionTester
        self.providerAppearance = providerAppearance
        self.session = session
    }

    public func save() async throws {
        do {
            let baseURL = llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = llmModel.trimmingCharacters(in: .whitespacesAndNewlines)
            let googleKey = googleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let llmKey = llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !baseURL.isEmpty { _ = try EndpointPolicy.validatedAPIBaseURL(baseURL) }
            try storeCredential(googleKey, key: .googleAPIKey)
            try storeCredential(llmKey, key: .llmAPIKey)

            var preferences = AppPreferences()
            preferences.launchAtLogin = launchAtLogin
            preferences.globalShortcut = globalShortcut
            preferences.translateClipboardOnOpen = translateClipboardOnOpen
            preferences.llmBaseURL = baseURL
            preferences.llmModel = model
            preferences.generalPrompt = generalPrompt
            preferences.technologyAndRnDPrompt = technologyAndRnDPrompt
            preferences.defaultPromptPresetID = defaultPromptPresetID
            try await preferencesStore.save(preferences)

            if launchController.isEnabled != launchAtLogin {
                try launchController.setEnabled(launchAtLogin)
            }
            shortcutRegistrar.unregister()
            try shortcutRegistrar.register(globalShortcut, action: shortcutAction)
            session?.promptPresetID = defaultPromptPresetID
            providerAppearance.llmBrand = ProviderBrandResolver.resolve(baseURL: baseURL)
            llmBaseURL = baseURL
            llmModel = model
            googleAPIKey = googleKey
            llmAPIKey = llmKey
            saveError = nil
        } catch {
            saveError = message(for: error)
            throw error
        }
    }

    public func restoreGeneralPrompt() { generalPrompt = DefaultPrompts.general }
    public func restoreTechnologyAndRnDPrompt() {
        technologyAndRnDPrompt = DefaultPrompts.technologyAndRnD
    }

    public func testGoogleConnection() async {
        googleConnectionState = .testing
        googleConnectionState = await connectionTester.testGoogle(
            apiKey: googleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    public func testLLMConnection() async {
        llmConnectionState = .testing
        let prompt = defaultPromptPresetID == .general ? generalPrompt : technologyAndRnDPrompt
        llmConnectionState = await connectionTester.testLLM(configuration: .init(
            baseURL: llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
            model: llmModel.trimmingCharacters(in: .whitespacesAndNewlines),
            systemPrompt: prompt
        ))
    }

    private func storeCredential(_ value: String, key: CredentialKey) throws {
        if value.isEmpty { try credentialStore.delete(key) }
        else { try credentialStore.write(value, for: key) }
    }

    private func message(for error: Error) -> String {
        switch error {
        case TranslationProviderError.insecureEndpoint: "Use HTTPS, or HTTP only on this Mac."
        case is KeychainError: "Could not store credentials in Keychain."
        case is ShortcutRegistrationError: "That shortcut could not be registered."
        default: "Settings could not be saved."
        }
    }
}
```

- [ ] **Step 4: Implement the settings window and shortcut capture**

Use this single retained controller so reopening Settings reuses the same window and model:

```swift
// Sources/InstantTranslationApp/Settings/SettingsWindowController.swift
import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowController: NSWindowController {
    public init(model: SettingsViewModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Instant Translation Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        super.init(window: window)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showSettings),
            name: .openInstantTranslationSettings,
            object: nil
        )
        installApplicationMenu()
    }

    required init?(coder: NSCoder) { nil }

    @objc public func showSettings() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func installApplicationMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settings.target = self
        appMenu.addItem(settings)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
```

`SettingsView` uses three `Form` sections and defines its prompt editor locally:

```swift
// Sources/InstantTranslationApp/Settings/SettingsView.swift
import SwiftUI
import InstantTranslationCore

@MainActor
public struct SettingsView: View {
    @Bindable private var model: SettingsViewModel
    public init(model: SettingsViewModel) { self.model = model }

    public var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: $model.launchAtLogin)
                Toggle("Read Clipboard and Translate on Open", isOn: $model.translateClipboardOnOpen)
                ShortcutCaptureView(shortcut: $model.globalShortcut)
            }
            Section("Translation Services") {
                SecureField("Google Cloud Translation API Key", text: $model.googleAPIKey)
                TextField("LLM Base URL", text: $model.llmBaseURL)
                SecureField("LLM API Key", text: $model.llmAPIKey)
                TextField("LLM Model", text: $model.llmModel)
                Text("Connection tests send one small real request and may incur provider charges.")
                HStack {
                    Button("Test Google") { Task { await model.testGoogleConnection() } }
                    Button("Test LLM") { Task { await model.testLLMConnection() } }
                }
                ConnectionStateView(label: "Google", state: model.googleConnectionState)
                ConnectionStateView(label: "LLM", state: model.llmConnectionState)
            }
            Section("LLM Prompts") {
                Picker("Default preset", selection: $model.defaultPromptPresetID) {
                    Text("General").tag(PromptPresetID.general)
                    Text("Technology & R&D").tag(PromptPresetID.technologyAndRnD)
                }
                PromptEditor(title: "General", text: $model.generalPrompt, restore: model.restoreGeneralPrompt)
                PromptEditor(title: "Technology & R&D", text: $model.technologyAndRnDPrompt, restore: model.restoreTechnologyAndRnDPrompt)
            }
            HStack {
                Spacer()
                Button("Save") { Task { try? await model.save() } }
                    .keyboardShortcut(.defaultAction)
            }
            if let saveError = model.saveError {
                Text(saveError).foregroundStyle(.red).accessibilityLabel("Settings error: \(saveError)")
            }
        }
        .padding(20)
    }
}

private struct PromptEditor: View {
    let title: String
    @Binding var text: String
    let restore: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Button("Restore Default", action: restore)
            }
            TextEditor(text: $text)
                .frame(minHeight: 120)
                .accessibilityLabel("\(title) system prompt")
        }
    }
}

private struct ConnectionStateView: View {
    let label: String
    let state: ConnectionTestState

    var body: some View {
        switch state {
        case .idle: EmptyView()
        case .testing: Text("\(label): Testing…").foregroundStyle(.secondary)
        case .success: Label("\(label): Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let error): Text("\(label): \(message(error))").foregroundStyle(.red)
        }
    }

    private func message(_ error: TranslationProviderError) -> String {
        switch error {
        case .unconfigured: "Configuration is incomplete."
        case .invalidCredentials: "Authentication failed."
        case .rateLimited: "Rate limited."
        case .networkUnavailable: "Network unavailable."
        case .timedOut: "Timed out."
        case .insecureEndpoint: "Base URL is not allowed."
        case .invalidResponse: "Invalid response."
        case .server(let code): "Service error (\(code))."
        case .cancelled: "Cancelled."
        }
    }
}
```

Prompt selection remains confined to Settings and never appears in the translation popover.

```swift
// Sources/InstantTranslationApp/Settings/ShortcutCaptureView.swift
import AppKit
import Carbon.HIToolbox
import SwiftUI
import InstantTranslationInfrastructure

@MainActor
public struct ShortcutCaptureView: NSViewRepresentable {
    @Binding var shortcut: KeyboardShortcut?
    public init(shortcut: Binding<KeyboardShortcut?>) { _shortcut = shortcut }

    public func makeNSView(context: Context) -> ShortcutRecorderView {
        let binding = $shortcut
        return ShortcutRecorderView { binding.wrappedValue = $0 }
    }

    public func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.shortcut = shortcut
    }
}

@MainActor
public final class ShortcutRecorderView: NSView {
    public var shortcut: KeyboardShortcut? { didSet { needsDisplay = true } }
    private var isRecording = false
    private let onChange: (KeyboardShortcut?) -> Void
    public override var acceptsFirstResponder: Bool { true }
    public override var intrinsicContentSize: NSSize { .init(width: 180, height: 28) }

    init(onChange: @escaping (KeyboardShortcut?) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        needsDisplay = true
    }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { isRecording = false; needsDisplay = true; return }
        if event.keyCode == 51 {
            shortcut = nil
            onChange(nil)
            isRecording = false
            return
        }
        let modifierOnly: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        guard !modifierOnly.contains(event.keyCode) else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let value = KeyboardShortcut(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers)
        shortcut = value
        onChange(value)
        isRecording = false
    }

    public override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        let label = isRecording ? "Press shortcut…" : Self.label(for: shortcut)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = label.size(withAttributes: attributes)
        label.draw(at: .init(x: 8, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }

    private static func label(for shortcut: KeyboardShortcut?) -> String {
        guard let shortcut else { return "Not Set" }
        var value = ""
        if shortcut.carbonModifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if shortcut.carbonModifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if shortcut.carbonModifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if shortcut.carbonModifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        let commonKeys: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
            38: "J", 40: "K", 45: "N", 46: "M", 49: "Space",
        ]
        return value + (commonKeys[shortcut.keyCode] ?? "Key \(shortcut.keyCode)")
    }
}
```

This recorder observes only the focused Settings control. It does not call `NSEvent.addGlobalMonitorForEvents` or request Accessibility permission.

Add these retained properties and initializer parameters to `ApplicationContainer`:

```swift
public let providerAppearance: ProviderAppearance
public let settingsViewModel: SettingsViewModel
public let settingsWindowController: SettingsWindowController
```

Then replace the Task-9 construction tail after `statusBar` is created with:

```swift
let settingsViewModel = await SettingsViewModel.make(
    preferencesStore: preferencesStore,
    credentialStore: credentialStore,
    launchAtLogin: LaunchAtLoginController(),
    shortcutRegistrar: shortcut,
    shortcutAction: { [weak statusBar] in statusBar?.toggleFromShortcut() },
    connectionTester: ProviderConnectionTester(transport: transport),
    providerAppearance: appearance,
    session: session
)
let settingsWindowController = SettingsWindowController(model: settingsViewModel)
let container = ApplicationContainer(
    session: session,
    preferencesStore: preferencesStore,
    credentialStore: credentialStore,
    statusBarController: statusBar,
    popoverController: popover,
    shortcutRegistrar: shortcut,
    clipboardSource: ClipboardInputSource(),
    providerAppearance: appearance,
    settingsViewModel: settingsViewModel,
    settingsWindowController: settingsWindowController
)
popover.onWillShow = { [weak container] in container?.prepareClipboard() }
return container
```

Append these parameters and assignments to the private initializer:

```swift
providerAppearance: ProviderAppearance,
settingsViewModel: SettingsViewModel,
settingsWindowController: SettingsWindowController
// initializer body
self.providerAppearance = providerAppearance
self.settingsViewModel = settingsViewModel
self.settingsWindowController = settingsWindowController
```

The Settings model is the only writer of stored configuration after startup.

- [ ] **Step 5: Implement explicit connection tests**

`testGoogleConnection()` passes the current Google key to `ProviderConnectionTester`, which submits fixed text `test` from English to Chinese using only Google. `testLLMConnection()` passes an `LLMProviderConfiguration` built from the current Base URL, key, model, and selected prompt and submits only to the LLM. Each action displays `testing`, `success`, or the mapped provider error and never retries automatically. It must not run when the user merely edits or saves settings.

- [ ] **Step 6: Run settings and storage tests**

Run: `swift test --filter 'SettingsViewModelTests|StorageTests'`

Expected: PASS. Then run `defaults read com.instanttranslation.macos 2>/dev/null | rg 'google-secret|llm-secret'` and expect no output.

- [ ] **Step 7: Commit Settings**

```bash
git add Sources/InstantTranslationApp Tests/InstantTranslationAppTests
git commit -m "feat(settings): configure services and app behavior"
```

---

### Task 11: End-to-End Verification, Performance Gates, Privacy Documentation, and Release Checklist

**Files:**
- Create: `Tests/InstantTranslationFeatureTests/TranslationStressTests.swift`
- Create: `scripts/verify-bundle.sh`
- Create: `scripts/measure-memory.sh`
- Create: `scripts/package-release.sh`
- Create: `README.md`
- Create: `PRIVACY.md`
- Create: `docs/manual-test-checklist.md`

**Interfaces:**
- Consumes: the complete application.
- Produces: deterministic verification scripts, a stress-test suite, user setup documentation, privacy disclosure, and the release acceptance record.

- [ ] **Step 1: Write the failing 200-query and 500-popover stress tests**

```swift
// Tests/InstantTranslationFeatureTests/TranslationStressTests.swift
import XCTest
import InstantTranslationCore
@testable import InstantTranslationFeature

@MainActor
final class TranslationStressTests: XCTestCase {
    func testTwoHundredStubTranslationsFinishWithOnlyCurrentSessionRetained() async throws {
        let coordinator = TranslationCoordinator(providers: [ImmediateProvider(id: .google), ImmediateProvider(id: .llm)])
        let session = TranslationSession(coordinator: coordinator, promptPresetID: .technologyAndRnD)
        for index in 0..<200 {
            session.submit(rawText: "term-\(index)", sourceID: .manual)
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(session.input, "term-199")
        XCTAssertEqual(session.activeRequest?.text, "term-199")
        XCTAssertEqual(session.states.count, 2)
    }
}

private struct ImmediateProvider: TranslationProvider {
    let id: ProviderID
    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        .init(
            providerID: id, requestID: request.id, primaryText: "result", rationale: nil,
            sourceLanguage: request.sourceLanguage, targetLanguage: request.targetLanguage,
            pronunciations: [], speakableText: "result", duration: .zero
        )
    }
}
```

Add this test and helper to `AppShellTests`:

```swift
func testFiveHundredPopoverControllerConstructionsReleaseContent() {
    var references: [WeakBox<PopoverContentController>] = []
    for _ in 0..<500 {
        autoreleasepool {
            let controller = TranslationPopoverController(contentView: NSView())
            references.append(WeakBox(controller.contentController))
        }
    }
    XCTAssertTrue(references.allSatisfy { $0.value == nil })
}

private final class WeakBox<Value: AnyObject> {
    weak var value: Value?
    init(_ value: Value) { self.value = value }
}
```

This catches obvious controller-retention cycles before manual Instruments testing.

- [ ] **Step 2: Run stress tests and fix all retained-state failures**

Run: `swift test --filter 'TranslationStressTests|AppShellTests'`

Expected: PASS; Thread Sanitizer is not part of `swift test`, so also run `xcodebuild -scheme InstantTranslation -destination 'platform=macOS' test -enableThreadSanitizer YES` and expect no data-race report.

- [ ] **Step 3: Add deterministic bundle verification**

```bash
#!/usr/bin/env bash
# scripts/verify-bundle.sh
set -euo pipefail
bash scripts/package-app.sh >/dev/null
APP="build/InstantTranslation.app"
test -x "$APP/Contents/MacOS/InstantTranslation"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP/Contents/Info.plist")" = "true"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")" = "15.0"
for key in NSAccessibilityUsageDescription NSScreenCaptureUsageDescription NSMicrophoneUsageDescription NSAppleEventsUsageDescription; do
  if /usr/libexec/PlistBuddy -c "Print :$key" "$APP/Contents/Info.plist" >/dev/null 2>&1; then
    echo "Unexpected protected-resource key: $key" >&2
    exit 1
  fi
done
if strings "$APP/Contents/MacOS/InstantTranslation" | rg -q 'cdn.simpleicons|raw.githubusercontent|WKWebView'; then
  echo "Found a forbidden runtime URL or WebView symbol" >&2
  exit 1
fi
codesign --verify --deep --strict "$APP"
```

Run `chmod +x scripts/verify-bundle.sh`.

- [ ] **Step 4: Add the release memory measurement gate**

```bash
#!/usr/bin/env bash
# scripts/measure-memory.sh
set -euo pipefail
bash scripts/package-app.sh >/dev/null
APP="$PWD/build/InstantTranslation.app"
"$APP/Contents/MacOS/InstantTranslation" &
PID="$!"
cleanup() { kill "$PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 60
RSS_KB="$(ps -o rss= -p "$PID" | tr -d ' ')"
CPU="$(ps -o %cpu= -p "$PID" | tr -d ' ')"
echo "rss_kb=$RSS_KB cpu_percent=$CPU"
test "$RSS_KB" -le 51200
awk -v cpu="$CPU" 'BEGIN { exit !(cpu <= 0.5) }'
```

Run `chmod +x scripts/measure-memory.sh`.

Run `bash scripts/measure-memory.sh` on a clean login session and record the model, OS version, RSS, and CPU in the manual checklist. If RSS exceeds 50 MB, use Instruments Allocations and Leaks before changing the target; do not weaken the threshold.

- [ ] **Step 5: Write user, privacy, and manual verification documentation**

`README.md` must document:

- macOS 15+ requirement;
- menu-bar and optional shortcut workflows;
- Google Cloud Translation Basic v2 setup, API restriction to Cloud Translation API, and a warning that a distributed desktop client cannot provide a reliable website/IP application restriction for a user-supplied key;
- OpenAI-compatible Base URL semantics, model, and prompt presets;
- clipboard-on-open behavior and the 500-character confirmation threshold;
- Keychain storage and absence of history;
- `swift test`, `bash scripts/package-app.sh`, and local installation commands;
- `SIGNING_MODE=adhoc` as the current GitHub Release mode, the lack of notarization, the SHA-256 verification command, and Apple's per-application Open Anyway flow without global Gatekeeper disablement or a default `sudo xattr` instruction; and
- deferred extension seams for selection, OCR, languages, pronunciation, and TTS without presenting them as shipped features.

`PRIVACY.md` must state that text is sent only to the two configured translation services when submitted, no text/history/telemetry is persisted, credentials stay in Keychain, and the first release requests no protected macOS permissions.

`docs/manual-test-checklist.md` must contain checkboxes for:

1. light, dark, Increase Contrast, and Reduce Transparency;
2. VoiceOver names for status item, input, direction, copy, retry, and Settings controls;
3. keyboard-only open, type, submit, copy, settings, and close;
4. outside-click dismissal while an in-flight stub request continues;
5. clipboard empty, duplicate, 500-character, 501-character, and non-text cases;
6. Google-only failure, LLM-only failure, 401/403, 429, offline, timeout, and malformed LLM content;
7. 500 open/close cycles under Instruments Leaks;
8. 200 stub translations under Instruments Allocations;
9. warm popover open under 100 ms measured with Points of Interest; and
10. no Accessibility, Screen Recording, Microphone, or Automation prompt;
11. file-based Keychain round trips in an ad-hoc application bundle and no API key appears in `UserDefaults`;
12. `package-release.sh` emits an application ZIP and matching `SHA256SUMS`, and checksum verification succeeds after extracting into a clean temporary directory; and
13. the documented Gatekeeper recovery uses only the per-application Open Anyway flow.

- [ ] **Step 6: Run the complete verification matrix**

Run:

```bash
swift test
swift build -c release
bash scripts/verify-bundle.sh
bash scripts/measure-memory.sh
SIGNING_MODE=adhoc bash scripts/package-release.sh
shasum -a 256 -c build/release/SHA256SUMS
git diff --check
```

Expected:

- all unit, component, integration, security, and stress tests PASS;
- release build succeeds;
- bundle verification succeeds and contains no protected-resource usage keys;
- the ad-hoc release ZIP and `SHA256SUMS` are generated deterministically enough for the checksum to verify, and no secret is present in either artifact;
- idle RSS is at most 51,200 KB and idle CPU is at most 0.5%; and
- `git diff --check` reports no whitespace errors.

- [ ] **Step 7: Perform the manual checklist on macOS 15 and the current macOS version**

Record actual results in `docs/manual-test-checklist.md`. Every item must pass before marking the release ready. Real Google and LLM connection tests are run only from Settings with developer-owned Keychain credentials; they are never invoked by CI.

- [ ] **Step 8: Commit verification and documentation**

```bash
git add Tests scripts README.md PRIVACY.md THIRD_PARTY_NOTICES.md docs/manual-test-checklist.md
git commit -m "test: add release acceptance gates"
```

---

## Final Release Gate

Before claiming the implementation complete, use `superpowers:verification-before-completion` and rerun the exact Task 11 verification matrix from a clean worktree. Confirm `git status --short` is empty after the final commit. Do not add OCR, selected-text capture, extra languages, pronunciation rendering, TTS, history, dynamic plugins, Sparkle, or analytics during this plan; their contracts exist only to prevent first-release coupling.
