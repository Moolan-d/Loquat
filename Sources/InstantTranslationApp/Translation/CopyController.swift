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
@Observable
public final class CopyController {
    public private(set) var copiedProviderID: ProviderID?
    public private(set) var failedProviderID: ProviderID?

    private let pasteboard: PasteboardWriting
    private let feedbackDuration: Duration
    private var resetTask: Task<Void, Never>?

    public init(
        pasteboard: PasteboardWriting = SystemPasteboardWriter(),
        feedbackDuration: Duration = .seconds(1.2)
    ) {
        self.pasteboard = pasteboard
        self.feedbackDuration = feedbackDuration
    }

    public func copy(_ result: TranslationResult) {
        resetTask?.cancel()

        if pasteboard.write(result.primaryText) {
            copiedProviderID = result.providerID
            failedProviderID = nil
            resetTask = Task {
                try? await Task.sleep(for: feedbackDuration)
                guard !Task.isCancelled else { return }
                if copiedProviderID == result.providerID {
                    copiedProviderID = nil
                }
            }
        } else {
            copiedProviderID = nil
            failedProviderID = result.providerID
        }
    }
}

public enum TranslationAccessibility {
    public static func copyLabel(providerID: ProviderID) -> String {
        providerID == .google ? "Copy Google translation" : "Copy LLM translation"
    }
}
