import AppKit
import Observation
import InstantTranslationCore

@MainActor
public protocol PasteboardWriting: AnyObject {
    func write(_ value: String) -> Bool
}

@MainActor
public final class SystemPasteboardWriter: PasteboardWriting {
    public init() {}

    public func write(_ value: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(value, forType: .string)
    }
}

@MainActor
protocol CopyFeedbackCancellation: AnyObject {
    func cancel()
}

@MainActor
protocol CopyFeedbackScheduling: AnyObject {
    func schedule(
        after duration: Duration,
        action: @escaping @MainActor () -> Void
    ) -> any CopyFeedbackCancellation
}

@MainActor
private final class TaskCopyFeedbackScheduler: CopyFeedbackScheduling {
    func schedule(
        after duration: Duration,
        action: @escaping @MainActor () -> Void
    ) -> any CopyFeedbackCancellation {
        let task = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            action()
        }
        return TaskCopyFeedbackCancellation(task: task)
    }
}

@MainActor
private final class TaskCopyFeedbackCancellation: CopyFeedbackCancellation {
    private let task: Task<Void, Never>

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task.cancel()
    }
}

@MainActor
@Observable
public final class CopyController {
    public private(set) var copiedProviderID: ProviderID?
    public private(set) var failedProviderID: ProviderID?

    private let pasteboard: PasteboardWriting
    private let feedbackDuration: Duration
    private let scheduler: any CopyFeedbackScheduling
    private var resetCancellation: (any CopyFeedbackCancellation)?

    public init(pasteboard: PasteboardWriting = SystemPasteboardWriter()) {
        self.pasteboard = pasteboard
        feedbackDuration = .seconds(1.2)
        scheduler = TaskCopyFeedbackScheduler()
    }

    init(
        pasteboard: PasteboardWriting,
        scheduler: any CopyFeedbackScheduling,
        feedbackDuration: Duration = .seconds(1.2)
    ) {
        self.pasteboard = pasteboard
        self.scheduler = scheduler
        self.feedbackDuration = feedbackDuration
    }

    public func copy(_ result: TranslationResult) {
        resetCancellation?.cancel()

        if pasteboard.write(result.primaryText) {
            copiedProviderID = result.providerID
            failedProviderID = nil
            resetCancellation = scheduler.schedule(after: feedbackDuration) { [weak self] in
                if self?.copiedProviderID == result.providerID {
                    self?.copiedProviderID = nil
                }
            }
        } else {
            copiedProviderID = nil
            failedProviderID = result.providerID
        }
    }
}

public enum TranslationCardAccessibilityState: Sendable {
    case idle
    case loading
    case success
    case failure
}

public enum TranslationCopyAccessibilityState: Sendable {
    case idle
    case copied
    case failed
}

public enum TranslationAccessibility {
    public static func copyLabel(providerID: ProviderID) -> String {
        "Copy \(providerName(providerID)) translation"
    }

    public static func cardLabel(
        providerID: ProviderID,
        state: TranslationCardAccessibilityState
    ) -> String {
        let identity = "\(providerName(providerID)) translation"
        return switch state {
        case .idle:
            identity
        case .loading:
            "\(identity), loading"
        case .success:
            "\(identity), result"
        case .failure:
            "\(identity), failed"
        }
    }

    public static func loadingLabel(providerID: ProviderID) -> String {
        "\(providerName(providerID)) translation loading"
    }

    public static func retryLabel(providerID: ProviderID) -> String {
        "Retry \(providerName(providerID)) translation"
    }

    public static func copyFeedback(
        providerID: ProviderID,
        copiedProviderID: ProviderID?,
        failedProviderID: ProviderID?
    ) -> TranslationCopyAccessibilityState {
        if copiedProviderID == providerID {
            return .copied
        }
        if failedProviderID == providerID {
            return .failed
        }
        return .idle
    }

    public static func copyValue(_ state: TranslationCopyAccessibilityState) -> String {
        switch state {
        case .idle:
            ""
        case .copied:
            "Copied"
        case .failed:
            "Copy failed"
        }
    }

    private static func providerName(_ providerID: ProviderID) -> String {
        providerID == .google ? "Google" : "LLM"
    }
}
