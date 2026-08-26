# Compact On-Demand Translation Results Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 精简查词结果的首次 LLM 响应与弹窗布局，保留 provider 品牌图标，只展示 3 个差异化常用义项和 1 条最相关搭配，并把网络、俚语、嘻哈等补充语境改为用户点击后才发起的第二次 LLM 请求。

**Architecture:** 保留现有 Google 与 OpenAI-compatible LLM 并行首译架构。首次 LLM 请求仍返回主译文、简短说明、最多 3 个常用义项和最多 1 条搭配；额外语境通过 Core 中独立的 `ContextExpansionProvider` 能力、Feature 中独立的 `ContextExpansionState` 状态机按需获取。SwiftUI 移除结果区最外层滚动，Google 成功卡改为紧凑横排，LLM 卡在自身内容区超过高度上限时内部滚动。

**Tech Stack:** Swift 6.2、SwiftUI、AppKit、Observation、Swift Concurrency、Swift Package Manager、XCTest；macOS 15+；不新增第三方依赖。

**Spec:** `docs/superpowers/specs/2026-08-12-instant-translation-design.md`，以本计划的 Global Constraints 与 Product Decisions 覆盖原规范中关于结果卡布局及 LLM 两字段响应的旧描述。

## Global Constraints

- 当前工作区已有未提交的义项/搭配实现；执行前先读 `git status --short` 与 `git diff`，不得 reset、checkout、覆盖或丢弃这些改动。
- provider 身份继续由 `ProviderIconView` 和现有 bundled SVG 资源呈现；不得改成“基础翻译”“AI 解释”等通用图标或文字标题。
- Google 与 LLM 的首次请求仍然并行、独立成功、独立失败、独立重试；按需语境请求不得阻塞或重发任一首次翻译。
- 首次 LLM 响应最多包含 3 个常用且语义不同的义项、每个义项最多 1 组双语例句、以及最多 1 条最相关搭配；不得在首次 prompt 中主动索取网络、嘻哈或其他小众语境。
- “更多语境”仅对 `SenseExpansionPolicy` 判定为查词的输入显示，只有用户点击才发送 1 次额外 LLM 请求。
- 同一 `activeRequest` 的补充语境在内存中保留：加载中或成功后重复点击不得再次请求；新输入、换向重译、LLM provider 重试或 reset 会取消并清空旧补充状态。不做跨会话、磁盘或 `UserDefaults` 缓存。
- 默认主视图不得包含包住所有 provider 卡片的 `ScrollView`。内容过长时只允许单个 provider 卡片的正文区域出现内部滚动。
- `PopoverContentMetrics.standard.maximumHeight` 保持 560；不得通过增高弹窗规避布局问题。
- 输入提示沿用当前产品语言，文案保持 `Enter to translate`，移动到输入框内部尾部；仅当剪贴板超过 500 字符时，输入框下方才显示现有确认提示。
- 复制按钮仍然只复制该 provider 的 `primaryText`；义项、例句、搭配和按需语境不进入剪贴板。
- 新请求继续复用现有 HTTPS/loopback endpoint 校验、Authorization、60 秒超时、错误映射和非流式 Chat Completions 协议。
- 所有新增按钮必须有 `.accessibilityLabel` 与 `.help`；加载状态必须可由 VoiceOver 识别。
- 基线：2026-08-26 在当前未提交改动上执行 `swift test`，230 tests passed、0 failures。

## Product Decisions

- Google 成功卡采用 `provider icon → primaryText → copy` 单行布局；长译文可换行，但卡片正文超过自身高度上限后只在卡片内部滚动。
- LLM 成功卡采用 `provider icon/copy → primaryText → rationale → 义项 → 常用搭配 → 按需语境` 的阅读顺序。
- 对查词输入，`primaryText` 最多列出 3 个确有差异的目标语言对应词，使用目标语言标点分隔；整句翻译仍只返回一条连续译文。
- `rationale` 必须解释核心差异，不复述 `primaryText`。
- 初始义项只覆盖常见且可区分的语义；模型返回超过上限或完全重复的条目时，客户端按稳定顺序去重并截断。
- 常用搭配标题使用当前产品语言 `Common Collocation`，只显示 `phrases.first`。
- 按需入口文案为 `More Contexts`，副文案为 `Generated on demand by AI`；加载文案为 `Generating more contexts…`；空结果文案为 `No additional contexts found.`；失败沿用现有 provider 错误文案并显示 `Retry`。
- 按需结果只返回补充义项，不再返回主译文、rationale 或搭配；重点覆盖确有价值的俚语、网络和亚文化语境，且不得重复首次结果。

---

### Task 1: Add Domain Contracts for Bilingual Examples and On-Demand Context

**Files:**
- Modify: `Sources/InstantTranslationCore/Domain/TranslationModels.swift`
- Modify: `Sources/InstantTranslationCore/Domain/TranslationProvider.swift`
- Modify: `Sources/InstantTranslationCore/Translation/TranslationCoordinator.swift`
- Modify: `Tests/InstantTranslationCoreTests/TranslationModelsTests.swift`
- Modify: `Tests/InstantTranslationCoreTests/TranslationCoordinatorTests.swift`

**Interfaces:**
- Produces: `WordSense.exampleTranslation: String?`.
- Produces: `ContextExpansionResult(requestID:senses:)`.
- Produces: `ContextExpansionProvider.expandContext(for:excluding:)`.
- Produces: `TranslationCoordinator.expandContext(for:excluding:) async -> Result<ContextExpansionResult, TranslationProviderError>`.

- [ ] **Step 1: Write failing domain-model tests**

Add tests proving the source and translated example remain separate and the expansion result remains tied to the originating request:

```swift
func testWordSenseCarriesOptionalBilingualExample() {
    let sense = WordSense(
        label: "日常",
        meaning: "自尊心、面子",
        example: "His ego was bruised.",
        exampleTranslation: "他的自尊心受挫了。"
    )

    XCTAssertEqual(sense.example, "His ego was bruised.")
    XCTAssertEqual(sense.exampleTranslation, "他的自尊心受挫了。")
}

func testContextExpansionIsBoundToOriginalRequest() {
    let requestID = UUID()
    let expansion = ContextExpansionResult(
        requestID: requestID,
        senses: [.init(label: "网络", meaning: "过度自我关注", example: nil)]
    )

    XCTAssertEqual(expansion.requestID, requestID)
    XCTAssertEqual(expansion.senses.count, 1)
}
```

- [ ] **Step 2: Run the model tests and verify RED**

Run: `swift test --filter TranslationModelsTests`

Expected: compilation fails because `exampleTranslation`, `ContextExpansionResult`, and the new initializer arguments do not exist.

- [ ] **Step 3: Add the Core models and capability protocol**

Extend `WordSense` without breaking existing call sites by adding a defaulted parameter:

```swift
public struct WordSense: Hashable, Codable, Sendable {
    public let label: String
    public let meaning: String
    public let example: String?
    public let exampleTranslation: String?

    public init(
        label: String,
        meaning: String,
        example: String?,
        exampleTranslation: String? = nil
    ) {
        self.label = label
        self.meaning = meaning
        self.example = example
        self.exampleTranslation = exampleTranslation
    }
}

public struct ContextExpansionResult: Hashable, Sendable {
    public let requestID: UUID
    public let senses: [WordSense]

    public init(requestID: UUID, senses: [WordSense]) {
        self.requestID = requestID
        self.senses = senses
    }
}
```

Add a separate capability instead of widening `TranslationProvider`, so Google and existing test providers do not acquire meaningless methods:

```swift
public protocol ContextExpansionProvider: Sendable {
    func expandContext(
        for request: TranslationRequest,
        excluding existingResult: TranslationResult
    ) async throws -> ContextExpansionResult
}
```

- [ ] **Step 4: Write failing coordinator tests**

Add an `ExpandableProvider` test double conforming to both protocols. Test that the coordinator forwards the current request/result and maps thrown `TranslationProviderError`; test that a non-expandable or missing LLM returns `.unconfigured` without affecting normal translation events.

```swift
func testCoordinatorRunsLLMContextExpansionWithoutResubmittingTranslation() async throws {
    let provider = ExpandableProvider()
    let coordinator = TranslationCoordinator(providers: [provider])
    let existing = makeResult(providerID: .llm, requestID: Self.request.id)

    let outcome = await coordinator.expandContext(for: Self.request, excluding: existing)

    let expansion = try outcome.get()
    XCTAssertEqual(expansion.requestID, Self.request.id)
    XCTAssertEqual(await provider.translateCallCount, 0)
    XCTAssertEqual(await provider.expandCallCount, 1)
}
```

- [ ] **Step 5: Implement coordinator forwarding and error mapping**

Add the exact API below. The cast must target only `.llm`; do not loop through providers and do not add a second parallel group.

```swift
public func expandContext(
    for request: TranslationRequest,
    excluding existingResult: TranslationResult
) async -> Result<ContextExpansionResult, TranslationProviderError> {
    guard let provider = providers[.llm] as? any ContextExpansionProvider else {
        return .failure(.unconfigured)
    }
    do {
        return .success(try await provider.expandContext(for: request, excluding: existingResult))
    } catch let error as TranslationProviderError {
        return .failure(error)
    } catch is CancellationError {
        return .failure(.cancelled)
    } catch {
        return .failure(.invalidResponse)
    }
}
```

- [ ] **Step 6: Run Core tests and verify GREEN**

Run: `swift test --filter 'TranslationModelsTests|TranslationCoordinatorTests'`

Expected: all selected tests pass; existing provider concurrency tests remain unchanged.

- [ ] **Step 7: Commit the Core contract**

```bash
git add Sources/InstantTranslationCore Tests/InstantTranslationCoreTests
git commit -m "feat(core): add on-demand context expansion contract"
```

---

### Task 2: Split the Compact First Response from the Optional Context Request

**Files:**
- Modify: `Sources/InstantTranslationInfrastructure/Providers/LLMUserPrompt.swift`
- Create: `Sources/InstantTranslationInfrastructure/Providers/LLMContextPrompt.swift`
- Modify: `Sources/InstantTranslationInfrastructure/Providers/LLMResponseParser.swift`
- Modify: `Sources/InstantTranslationInfrastructure/Providers/OpenAICompatibleProvider.swift`
- Modify: `Tests/InstantTranslationInfrastructureTests/OpenAICompatibleProviderTests.swift`

**Interfaces:**
- Consumes: `ContextExpansionProvider`, `ContextExpansionResult`, bilingual `WordSense`.
- Produces: `LLMContextPrompt.build(for:excluding:)`.
- Produces: `LLMResponseParser.parseContextExpansion(_:)`.
- Produces: `OpenAICompatibleProvider: TranslationProvider, ContextExpansionProvider`.

- [ ] **Step 1: Replace prompt-contract tests with compact first-response expectations**

For a lookup, assert that the initial prompt contains all of the following requirements:

```swift
XCTAssertTrue(lookup.contains("at most 3"))
XCTAssertTrue(lookup.contains("at most 1"))
XCTAssertTrue(lookup.contains(#""exampleTranslation""#))
XCTAssertTrue(lookup.contains("Do not repeat"))
XCTAssertTrue(lookup.contains("up to 3 distinct target-language equivalents"))
XCTAssertFalse(lookup.contains("include slang or internet usage whenever"))
```

For a sentence, continue asserting that `senses`, `phrases`, and `exampleTranslation` are absent. Retain the existing checks proving the JSON contract stays in the code-owned user message rather than editable system prompts.

- [ ] **Step 2: Add failing parser tests for limits, trimming, and expansion-only JSON**

Cover these exact cases:

1. `parse(_:)` keeps only the first 3 nonblank, nonduplicate senses and the first valid phrase.
2. `example` and `exampleTranslation` decode independently; either may be absent.
3. Duplicate senses are removed using normalized `label + meaning` after trimming and lowercasing; original order wins.
4. `parseContextExpansion(_:)` accepts `{"senses":[...]}` and clamps to 3.
5. Invalid expansion JSON throws `.invalidResponse`; `{"senses":[]}` is a valid empty success.
6. Malformed optional entries are discarded without losing valid siblings.

Use a representative payload:

```swift
let parsed = try LLMResponseParser.parse(
    #"{"translation":"自我；自尊心；自负","rationale":"核心义是人的自我意识。","senses":[{"label":"心理学","meaning":"自我意识"},{"label":"日常","meaning":"自尊心、面子","example":"His ego was bruised.","exampleTranslation":"他的自尊心受挫了。"},{"label":"贬义","meaning":"自负、以自我为中心"},{"label":"贬义","meaning":"自负、以自我为中心"}],"phrases":[{"phrase":"alter ego","meaning":"另一个自我"},{"phrase":"ego boost","meaning":"提升自信"}]}"#
)

XCTAssertEqual(parsed.senses.count, 3)
XCTAssertEqual(parsed.phrases, [.init(phrase: "alter ego", meaning: "另一个自我")])
XCTAssertEqual(parsed.senses[1].exampleTranslation, "他的自尊心受挫了。")
```

- [ ] **Step 3: Run provider tests and verify RED**

Run: `swift test --filter OpenAICompatibleProviderTests`

Expected: failures for the old 4-sense/4-phrase prompt, missing bilingual field, missing expansion parser, and missing expansion provider method.

- [ ] **Step 4: Tighten `LLMUserPrompt`**

Keep the required translation/rationale envelope. Replace only the lookup appendix with an instruction equivalent to the following exact contract:

```text
Text is a word or short expression. The "translation" is one line containing up to 3 distinct target-language equivalents when multiple equivalents are genuinely useful; separate them with natural target-language punctuation and do not add definitions. Add "senses": at most 3 common, meaningfully distinct senses ordered by usefulness. Do not repeat the translation, rationale, or another sense. Exclude niche internet, fandom, music, and subculture meanings from this first response. Each sense has "label", "meaning", optional source-language "example", and optional target-language "exampleTranslation". Add "phrases": at most 1 object containing the single most useful fixed collocation with "phrase" and "meaning". Omit empty sections.
```

Also change the rationale instruction to: one short target-language explanation of the core distinction that does not restate the translation.

- [ ] **Step 5: Add `LLMContextPrompt` for the click-triggered request**

The builder must include source language, target language, source text, the existing `primaryText`, and existing sense labels/meanings. It must request one JSON object with only `senses`, at most 3 additional entries, no repetitions, and no phrases/rationale/translation.

```swift
public enum LLMContextPrompt {
    public static func build(
        for request: TranslationRequest,
        excluding result: TranslationResult
    ) -> String {
        let covered = result.senses
            .map { "- \($0.label): \($0.meaning)" }
            .joined(separator: "\n")
        return """
        Source language: \(request.sourceLanguage.rawValue)
        Target language: \(request.targetLanguage.rawValue)
        Text: \(request.text)
        Existing translation: \(result.primaryText)
        Already covered senses:
        \(covered.isEmpty ? "- none" : covered)

        Reply with one JSON object and nothing else. Add "senses": an array of at most 3 additional, genuinely useful contexts not already covered. Prefer current slang, internet, or subculture usage only when it is real and relevant. Each object has "label", "meaning", optional source-language "example", and optional target-language "exampleTranslation". Do not add "translation", "rationale", or "phrases". An empty array is valid when no additional context is worth showing.
        """
    }
}
```

- [ ] **Step 6: Implement deterministic response compaction**

Centralize normalization in `LLMResponseParser`; do not duplicate limits in SwiftUI. Preserve input order, trim every string, discard entries with blank required fields, remove senses that have the same normalized `meaning` even when their labels differ, then apply `prefix(3)` for senses and `prefix(1)` for phrases. Deduplicate phrases by normalized `phrase`. Keep broader semantic deduplication in the prompt; do not add fuzzy matching or embeddings.

Expose:

```swift
public struct ParsedContextExpansion: Equatable, Sendable {
    public let senses: [WordSense]
}

public static func parseContextExpansion(_ content: String) throws -> ParsedContextExpansion
```

- [ ] **Step 7: Refactor the OpenAI-compatible transport path and add expansion**

Make `OpenAICompatibleProvider` conform to both protocols. Extract the duplicated configuration, URL validation, envelope decoding, timeout, error mapping, and duration measurement into one private method:

```swift
private func responseContent(
    for request: TranslationRequest,
    userPrompt: String
) async throws -> (content: String, duration: Duration)
```

`translate(_:)` calls it with `LLMUserPrompt`, parses a normal translation result, and includes compact senses/phrase. `expandContext(for:excluding:)` calls it with `LLMContextPrompt`, parses only added senses, and returns:

```swift
ContextExpansionResult(requestID: request.id, senses: parsed.senses)
```

Do not call `expandContext` from `translate`; the test transport request count must remain exactly 1 after first translation.

- [ ] **Step 8: Verify request timing and payloads**

Add a test with two queued stub responses:

```swift
let initial = try await provider.translate(Self.request)
XCTAssertEqual(transport.requests.count, 1)
XCTAssertEqual(initial.phrases.count, 1)

let expansion = try await provider.expandContext(for: Self.request, excluding: initial)
XCTAssertEqual(transport.requests.count, 2)
XCTAssertEqual(expansion.requestID, Self.request.id)
XCTAssertTrue(requestBody(transport.requests[1]).contains("additional"))
```

Also retain all existing endpoint security, error mapping, plain-text translation fallback, and malformed decorative-field tests.

- [ ] **Step 9: Run Infrastructure tests and verify GREEN**

Run: `swift test --filter OpenAICompatibleProviderTests`

Expected: all selected tests pass with no real network or API usage.

- [ ] **Step 10: Commit the provider split**

```bash
git add Sources/InstantTranslationInfrastructure/Providers Tests/InstantTranslationInfrastructureTests/OpenAICompatibleProviderTests.swift
git commit -m "feat(llm): load niche contexts on demand"
```

---

### Task 3: Add the On-Demand Expansion State Machine to the Translation Session

**Files:**
- Create: `Sources/InstantTranslationFeature/ContextExpansionState.swift`
- Modify: `Sources/InstantTranslationFeature/TranslationSession.swift`
- Modify: `Tests/InstantTranslationFeatureTests/TranslationSessionTests.swift`

**Interfaces:**
- Consumes: `TranslationCoordinator.expandContext(for:excluding:)`.
- Produces: `TranslationSession.contextExpansionState`.
- Produces: `TranslationSession.requestMoreContexts()`.

- [ ] **Step 1: Define state-transition tests before implementation**

Add tests for all of these transitions:

1. A short-input LLM success changes `.unavailable` to `.available` without calling expansion.
2. A sentence LLM success stays `.unavailable`.
3. `requestMoreContexts()` from `.available` changes to `.loading(requestID:)` and calls expansion once.
4. A second call while `.loading` is ignored.
5. Success becomes `.success(result)`; a later click is ignored, so the active result is the in-memory cache.
6. Failure becomes `.failure(requestID:error:)`; clicking again explicitly retries once.
7. New submit, swap, reset, disabling LLM, or retrying the initial LLM result cancels and clears expansion state.
8. A late expansion result from an old request is ignored.
9. Closing/reopening the popover does not touch the state because no popover-close hook calls `reset` or `cancelAll`.

Use an actor-backed fake provider so request counts are concurrency-safe:

```swift
actor ExpansionProbe {
    private(set) var calls = 0
    func record() { calls += 1 }
}

struct ExpandableStubProvider: TranslationProvider, ContextExpansionProvider {
    let id = ProviderID.llm
    let probe: ExpansionProbe
    let expansion: ContextExpansionResult

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        makeLookupResult(requestID: request.id)
    }

    func expandContext(
        for request: TranslationRequest,
        excluding existingResult: TranslationResult
    ) async throws -> ContextExpansionResult {
        await probe.record()
        return ContextExpansionResult(requestID: request.id, senses: expansion.senses)
    }
}
```

- [ ] **Step 2: Run session tests and verify RED**

Run: `swift test --filter TranslationSessionTests`

Expected: compilation fails because the state and action do not exist.

- [ ] **Step 3: Add `ContextExpansionState`**

```swift
public enum ContextExpansionState: Equatable, Sendable {
    case unavailable
    case available
    case loading(requestID: UUID)
    case success(ContextExpansionResult)
    case failure(requestID: UUID, TranslationProviderError)
}
```

- [ ] **Step 4: Implement session ownership, cancellation, and stale-result protection**

Add:

```swift
public private(set) var contextExpansionState: ContextExpansionState = .unavailable
private let senseExpansionPolicy = SenseExpansionPolicy()
private var contextExpansionTask: Task<Void, Never>?
```

`receive(_:)` sets `.available` only after a successful `.llm` result for the current request when `senseExpansionPolicy.shouldExpand(request.text)` is true. `requestMoreContexts()` must guard that:

- `activeRequest` exists;
- LLM is enabled;
- LLM card is `.success(let existingResult)` for the same request;
- state is `.available` or `.failure` for the same request.

Then set `.loading(requestID:)`, start one task, await coordinator expansion, verify cancellation and request ID, and publish success/failure. Do not mutate the original `TranslationResult`; supplemental content stays in the separate state.

Add `cancelContextExpansion()` and call it from new submit, `reset`, `cancelAll`, LLM disable, direction swap via resubmit, and initial LLM retry. The helper cancels the task and sets `.unavailable`.

- [ ] **Step 5: Run session tests and verify GREEN**

Run: `swift test --filter TranslationSessionTests`

Expected: all selected tests pass, including existing late-event, retry isolation, and reset behavior.

- [ ] **Step 6: Commit the Feature state machine**

```bash
git add Sources/InstantTranslationFeature Tests/InstantTranslationFeatureTests/TranslationSessionTests.swift
git commit -m "feat(session): manage optional context expansion"
```

---

### Task 4: Rebuild the Result Presentation Without a Main Results Scroller

**Files:**
- Modify: `Sources/InstantTranslationApp/Translation/TranslationView.swift`
- Modify: `Sources/InstantTranslationApp/Translation/ResultCardView.swift`
- Create: `Sources/InstantTranslationApp/Translation/LLMResultContentView.swift`
- Modify: `Sources/InstantTranslationApp/Translation/ProviderAvailability.swift`
- Modify: `Tests/InstantTranslationAppTests/TranslationPresentationTests.swift`

**Interfaces:**
- Consumes: `ContextExpansionState` and `TranslationSession.requestMoreContexts()`.
- Produces: `TranslationResultLayout` constants and `TranslationResultsPresentation.visiblePhrases(_:)`.
- Produces: provider-specific success layouts with card-local scrolling.

- [ ] **Step 1: Write presentation-policy tests**

Add exact assertions that enforce one collocation and CTA visibility:

```swift
func testOnlyFirstCollocationIsVisible() {
    let result = makeResult(
        providerID: .llm,
        primaryText: "自我；自尊心；自负",
        phrases: [
            .init(phrase: "alter ego", meaning: "另一个自我"),
            .init(phrase: "ego boost", meaning: "提升自信"),
        ]
    )

    XCTAssertEqual(
        TranslationResultsPresentation.visiblePhrases(result).map(\.phrase),
        ["alter ego"]
    )
}

func testMoreContextsActionOnlyAppearsWhenAvailableOrFailed() {
    XCTAssertTrue(TranslationResultsPresentation.showsMoreContextsAction(.available))
    XCTAssertTrue(TranslationResultsPresentation.showsMoreContextsAction(
        .failure(requestID: UUID(), .timedOut)
    ))
    XCTAssertFalse(TranslationResultsPresentation.showsMoreContextsAction(.unavailable))
    XCTAssertFalse(TranslationResultsPresentation.showsMoreContextsAction(
        .success(.init(requestID: UUID(), senses: []))
    ))
}
```

- [ ] **Step 2: Run presentation tests and verify RED**

Run: `swift test --filter TranslationPresentationTests`

Expected: compilation fails because the new presentation policies and layout do not exist.

- [ ] **Step 3: Move the Enter hint inside the input surface**

In `TranslationView`, replace the always-present caption `HStack` with a field-level `HStack` containing `TranslationInputField`, a spacer-sized boundary, and trailing `Text("Enter to translate")`. Apply the existing background/stroke to this outer field container, not separately to the text editor. Give the hint `.allowsHitTesting(false)` and `.accessibilityHidden(true)` because the text field already has its accessibility label.

Keep only this conditional message below the field:

```swift
if session.requiresManualClipboardConfirmation {
    Text("Clipboard text exceeds 500 characters. Press Enter to translate.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
}
```

Do not change Enter/Shift+Enter behavior or the existing three-line input cap.

- [ ] **Step 4: Remove the outer results `ScrollView`**

In `TranslationView`, render the provider cards directly in a `VStack(spacing: 10)`. Delete `maximumResultsHeight` and the `ScrollView` wrapping all providers. Pass two new arguments only to `ResultCardView`:

```swift
contextExpansionState: providerID == .llm ? session.contextExpansionState : .unavailable,
requestMoreContexts: { session.requestMoreContexts() }
```

The popover continues using fixed width 370 and max height 560.

- [ ] **Step 5: Split provider-specific success bodies while preserving logos**

Keep idle/loading/failure handling in `ResultCardView`. For success:

- Google: render `ProviderIconView`, `primaryText`, spacer, and the existing copy button in one `HStack`; use `.font(.title3)` for short output and allow wrapping.
- LLM: render the existing provider icon/copy header, then delegate to `LLMResultContentView`.
- Both success bodies use the existing `ProviderIconView`; do not add provider-name text or generic source labels.

Extract the existing copy button into a private helper so accessibility feedback remains identical in both layouts.

- [ ] **Step 6: Implement card-local scroll limits**

Define one internal source of truth:

```swift
enum TranslationResultLayout {
    static let googleBodyMaximumHeight: CGFloat = 96
    static let llmBodyMaximumHeight: CGFloat = 330
}
```

Google places only its text region in a vertical `ScrollView` capped at 96. LLM keeps the provider header fixed and places everything below it in a vertical `ScrollView` capped at 330. Use `.scrollBounceBehavior(.basedOnSize)` so short results do not feel scrollable and overlay scroll indicators appear only when a card actually overflows.

Do not nest another `ScrollView` inside the LLM body. The input editor's own `NSScrollView` remains independent.

- [ ] **Step 7: Build the compact LLM hierarchy**

`LLMResultContentView` receives:

```swift
let result: TranslationResult
let contextExpansionState: ContextExpansionState
let requestMoreContexts: () -> Void
```

Render in this exact order:

1. `primaryText` with `.font(.title3.weight(.semibold))` and text selection.
2. Nonblank `rationale` as `.callout` with secondary foreground.
3. Divider and up to 3 senses. Each row uses the existing capsule label, meaning, and a bilingual example line. Render source example italic; render `exampleTranslation` non-italic after it or on the next wrapped line.
4. If one phrase exists, divider, `Text("Common Collocation")`, then a single phrase/meaning row using `visiblePhrases`.
5. The on-demand context area.

Do not repeat `primaryText` inside a “basic meaning” row; the prompt/parser owns semantic compaction and the view renders returned fields without fuzzy logic.

- [ ] **Step 8: Render every on-demand state**

Use one full-width borderless button row for `.available`:

```swift
Button(action: requestMoreContexts) {
    HStack {
        Image(systemName: "sparkles")
        VStack(alignment: .leading, spacing: 1) {
            Text("More Contexts")
            Text("Generated on demand by AI")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "chevron.right")
    }
    .contentShape(Rectangle())
}
.buttonStyle(.plain)
.accessibilityLabel("Generate more contexts with AI")
.help("Sends one additional LLM request")
```

State rendering:

- `.loading`: compact `ProgressView` plus `Generating more contexts…`; no enabled button.
- `.success` with senses: divider, `Text("More Contexts")`, then the same sense-row renderer used above.
- `.success` with no senses: `Text("No additional contexts found.")` in secondary caption styling.
- `.failure`: existing sanitized error message plus `Button("Retry", action: requestMoreContexts)`; label it `Retry generating more contexts`.
- `.unavailable`: render nothing.

Keep the expansion section inside the LLM body scroller so extra content can scroll without moving Google or the input/header.

- [ ] **Step 9: Run App presentation tests and verify GREEN**

Run: `swift test --filter TranslationPresentationTests`

Expected: all selected tests pass; existing logo, copy, input-height, provider-order, and accessibility assertions remain green.

- [ ] **Step 10: Commit the compact SwiftUI presentation**

```bash
git add Sources/InstantTranslationApp/Translation Tests/InstantTranslationAppTests/TranslationPresentationTests.swift
git commit -m "feat(popover): compact provider results and localize scrolling"
```

---

### Task 5: Add Layout Regression Coverage and Complete Acceptance Verification

**Files:**
- Create: `Tests/InstantTranslationAppTests/TranslationPopoverLayoutTests.swift`
- Modify: `README.md` only if its main screenshot is intentionally regenerated after manual acceptance; otherwise leave documentation assets unchanged.

**Interfaces:**
- Consumes: final `TranslationView`, `TranslationResultLayout`, and `PopoverContentMetrics.standard`.
- Produces: rendering regression tests for a default lookup and long provider content.

- [ ] **Step 1: Add a reusable AppKit render harness in the new test file**

Use `NSHostingView` and a borderless `NSWindow`, following the existing pattern in `SettingsPresentationTests.testTranslationPopoverHasNoPromptPresetControl`. The helper must set the host width to `TranslationView.contentWidth`, attach it to a window, call `layoutSubtreeIfNeeded()`, and return both the host and recursively collected `NSScrollView` instances.

Do not add ViewInspector or snapshot-test dependencies.

- [ ] **Step 2: Add a default lookup fitting-height test**

Create stub Google and expandable LLM providers that immediately return the representative `ego` payload from Task 2. Submit `ego`, wait until both card states succeed, render `TranslationView`, then assert:

```swift
XCTAssertLessThanOrEqual(
    host.fittingSize.height,
    PopoverContentMetrics.standard.maximumHeight
)
```

Also identify the input `NSScrollView` by its `NSTextView` document view. After excluding it, assert there is no scroll view whose frame spans both provider cards. Card-local scrollers may exist, but their width must be less than or equal to the card content width and their height must not exceed the corresponding `TranslationResultLayout` maximum.

- [ ] **Step 3: Add a long-content containment test**

Return a Google translation and LLM explanation long enough to exceed their card bounds. Assert the host still fits within 560 points and at least one card-local scroller has a document view taller than its visible bounds. This proves overflow moved into a card rather than reintroducing the main results scroller.

- [ ] **Step 4: Run the complete automated suite**

Run: `swift test`

Expected: all tests pass, with the baseline 230 tests plus the newly added coverage and 0 failures.

- [ ] **Step 5: Perform manual visual and behavior acceptance**

Run: `swift run InstantTranslation`

Verify each scenario:

1. Query `ego`: provider logos match configured Google/LLM brands; Google is one compact row; LLM shows at most 3 distinct senses and exactly 0 or 1 collocation; no outer scrollbar is visible.
2. The `Enter to translate` hint sits inside the input without blocking typing, selection, or a three-line input; Shift+Enter still inserts a newline.
3. Before clicking `More Contexts`, the HTTP test/proxy log shows only the normal Google and LLM first requests.
4. Clicking `More Contexts` shows loading in the LLM card and sends one additional LLM request only.
5. Repeated clicks during loading and after success send no additional request.
6. Expanded content scrolls only inside the LLM card; header, input, Google card, provider icon, and copy button remain stationary.
7. Expansion failure leaves the original LLM translation usable and copyable; `Retry` sends exactly one new expansion request.
8. A long sentence does not show the More Contexts action and does not ask the initial LLM for senses or phrases.
9. Light mode, dark mode, Reduce Transparency, keyboard navigation, and VoiceOver expose readable text and named buttons.

- [ ] **Step 6: Check the final diff for scope and protected work**

Run: `git status --short`

Run: `git diff --check`

Run: `git diff --stat`

Confirm there are no new dependencies, no credential/logging changes, no provider-logo asset replacements, no `UserDefaults` cache, and no edits that discard the pre-existing uncommitted sense-expansion work.

- [ ] **Step 7: Commit layout verification**

```bash
git add Tests/InstantTranslationAppTests/TranslationPopoverLayoutTests.swift README.md
git commit -m "test(popover): cover compact result overflow behavior"
```

If `README.md` was not intentionally changed, omit it from `git add`.

## Final Acceptance Criteria

- `swift test` passes with 0 failures.
- Initial `ego` translation produces at most one LLM HTTP request and does not request niche contexts.
- One click on `More Contexts` produces exactly one additional LLM HTTP request; loading/success duplicate clicks produce zero more requests.
- Initial response has at most 3 senses and 1 phrase after client-side compaction, even if the provider returns more.
- Google and configured LLM icons continue using existing bundled provider logos in every card state.
- The default popover has no results-level scrollbar and stays at or below 560 points high.
- Overflow is contained inside the relevant Google or LLM result card.
- Copy behavior, provider retry isolation, direction swapping, reset, clipboard confirmation, focus restoration, security policy, and plain-text LLM fallback remain unchanged.
