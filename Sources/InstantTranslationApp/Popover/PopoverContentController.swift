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

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
