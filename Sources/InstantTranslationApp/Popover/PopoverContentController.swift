import AppKit

@MainActor
private final class AppearanceAwareVisualEffectView: NSVisualEffectView {
    var appearanceDidChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceDidChange?()
    }
}

/// 弹窗尺寸策略：宽度固定，高度跟随内容的 fitting size，并夹在上下界之间。
/// 上界避免长译文把弹窗顶出屏幕；超出部分由各张结果卡片内部滚动消化，
/// 因此正常情况下 fitting size 本来就到不了上界。
struct PopoverContentMetrics: Equatable {
    /// 生产配置的唯一来源，测试直接断言它，改了production值测试就会红。
    static let standard = PopoverContentMetrics(
        width: TranslationView.contentWidth,
        minimumHeight: 200,
        maximumHeight: 560
    )

    let width: CGFloat
    let minimumHeight: CGFloat
    let maximumHeight: CGFloat

    func size(forFittingHeight fitting: CGFloat) -> NSSize {
        NSSize(
            width: width,
            height: min(max(fitting, minimumHeight), maximumHeight)
        )
    }
}

@MainActor
public final class PopoverContentController: NSViewController {
    public let materialView: NSVisualEffectView
    // Swift 6 的 deinit 非隔离；通知 token 只在主线程安装，并在析构时一次性移除。
    nonisolated(unsafe) private var accessibilityObserver: NSObjectProtocol?
    private let shouldReduceTransparency: @MainActor () -> Bool
    private weak var hostedContentView: NSView?
    private let metrics: PopoverContentMetrics

    /// 首帧还没有 fitting size，先按常见内容高度落座，免得弹窗一出现就动画改尺寸。
    private static let initialContentHeight: CGFloat = 430

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
        shouldReduceTransparency: @escaping @MainActor () -> Bool,
        metrics: PopoverContentMetrics = .standard
    ) {
        let materialView = AppearanceAwareVisualEffectView()
        self.materialView = materialView
        self.shouldReduceTransparency = shouldReduceTransparency
        self.metrics = metrics
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
        hostedContentView = contentView
        preferredContentSize = metrics.size(forFittingHeight: Self.initialContentHeight)
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

    override public func viewDidLayout() {
        super.viewDidLayout()
        guard let hostedContentView else { return }
        let fitting = hostedContentView.fittingSize.height
        guard fitting > 0 else { return }
        let updated = metrics.size(forFittingHeight: fitting)
        guard updated != preferredContentSize else { return }
        preferredContentSize = updated
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
