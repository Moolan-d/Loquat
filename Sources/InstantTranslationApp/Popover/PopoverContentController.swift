import AppKit

@MainActor
public final class PopoverContentController: NSViewController {
    public let materialView = NSVisualEffectView()
    // Swift 6 的 deinit 非隔离；通知 token 只在主线程安装，并在析构时一次性移除。
    nonisolated(unsafe) private var accessibilityObserver: NSObjectProtocol?

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
}
