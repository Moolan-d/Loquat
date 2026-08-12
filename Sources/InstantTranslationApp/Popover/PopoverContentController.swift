import AppKit

@MainActor
private final class AppearanceAwareVisualEffectView: NSVisualEffectView {
    var appearanceDidChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceDidChange?()
    }
}

@MainActor
public final class PopoverContentController: NSViewController {
    public let materialView: NSVisualEffectView
    // Swift 6 的 deinit 非隔离；通知 token 只在主线程安装，并在析构时一次性移除。
    nonisolated(unsafe) private var accessibilityObserver: NSObjectProtocol?
    private let shouldReduceTransparency: @MainActor () -> Bool

    public convenience init(contentView: NSView) {
        self.init(
            contentView: contentView,
            shouldReduceTransparency: {
                NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            }
        )
    }

    init(
        contentView: NSView,
        shouldReduceTransparency: @escaping @MainActor () -> Bool
    ) {
        let materialView = AppearanceAwareVisualEffectView()
        self.materialView = materialView
        self.shouldReduceTransparency = shouldReduceTransparency
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
        materialView.appearanceDidChange = { [weak self] in
            self?.updateMaterial()
        }
        startObservingAccessibilityDisplayOptions()
        updateMaterial()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func startObservingAccessibilityDisplayOptions() {
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateMaterial()
            }
        }
    }

    private func updateMaterial() {
        materialView.wantsLayer = true
        if shouldReduceTransparency() {
            materialView.material = .windowBackground
            materialView.blendingMode = .withinWindow
            var resolvedBackground = NSColor.windowBackgroundColor.cgColor
            materialView.effectiveAppearance.performAsCurrentDrawingAppearance {
                resolvedBackground = NSColor.windowBackgroundColor.cgColor
            }
            materialView.layer?.backgroundColor = resolvedBackground
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
}
