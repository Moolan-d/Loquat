import AppKit
import SwiftUI
import InstantTranslationApp
import InstantTranslationCore
import InstantTranslationFeature

@MainActor
public final class DiagnosticsApplicationController {
    public let scenario: DiagnosticsScenario
    public let session: TranslationSession
    public let popoverController: TranslationPopoverController
    public let statusBarController: StatusBarController
    public let settingsViewModel: SettingsViewModel
    public let settingsWindowController: SettingsWindowController

    private let composition: DiagnosticsComposition
    private let controlWindow: NSWindow

    public static func make(
        scenario: DiagnosticsScenario
    ) async -> DiagnosticsApplicationController {
        let composition = await DiagnosticsDependencies.makeComposition(for: scenario)
        let focusController = TranslationInputFocusController()
        let translationContent = NSHostingView(
            rootView: TranslationView(
                session: composition.session,
                appearance: composition.providerAppearance,
                focusController: focusController
            )
        )
        let popover = TranslationPopoverController(
            contentView: translationContent,
            focusRequester: focusController
        )
        let statusBar = StatusBarController(
            popoverController: popover,
            shortcutRegistrar: composition.shortcutRegistrar
        )
        let settings = SettingsWindowController(model: composition.settingsViewModel)
        return DiagnosticsApplicationController(
            scenario: scenario,
            composition: composition,
            popoverController: popover,
            statusBarController: statusBar,
            settingsWindowController: settings
        )
    }

    private init(
        scenario: DiagnosticsScenario,
        composition: DiagnosticsComposition,
        popoverController: TranslationPopoverController,
        statusBarController: StatusBarController,
        settingsWindowController: SettingsWindowController
    ) {
        self.scenario = scenario
        self.composition = composition
        session = composition.session
        self.popoverController = popoverController
        self.statusBarController = statusBarController
        settingsViewModel = composition.settingsViewModel
        self.settingsWindowController = settingsWindowController
        controlWindow = Self.makeControlWindow(
            scenario: scenario,
            expectedVisibleState: scenario.configuration.expectedVisibleState
        )
        installControlActions()
    }

    public func present() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        controlWindow.makeKeyAndOrderFront(nil)
        switch scenario.configuration.destination {
        case .translationPopover:
            statusBarController.toggleFromShortcut()
        case .settings:
            settingsWindowController.showSettings(nil)
        }
    }

    private func installControlActions() {
        guard let stack = controlWindow.contentView as? NSStackView else { return }
        if scenario == .slowRequest {
            let complete = NSButton(
                title: "Complete Slow Request",
                target: self,
                action: #selector(completeSlowRequest)
            )
            complete.bezelStyle = .rounded
            stack.addArrangedSubview(complete)
        }
        let quit = NSButton(
            title: "Quit",
            target: NSApplication.shared,
            action: #selector(NSApplication.terminate(_:))
        )
        quit.bezelStyle = .rounded
        stack.addArrangedSubview(quit)
    }

    @objc private func completeSlowRequest() {
        Task { await composition.completeSlowRequest() }
    }

    private static func makeControlWindow(
        scenario: DiagnosticsScenario,
        expectedVisibleState: String
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 190),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Instant Translation Diagnostics"
        window.isReleasedWhenClosed = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        let name = NSTextField(labelWithString: "Scenario: \(scenario.rawValue)")
        name.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let expected = NSTextField(labelWithString: "Expected: \(expectedVisibleState)")
        expected.maximumNumberOfLines = 3
        expected.lineBreakMode = .byWordWrapping
        stack.addArrangedSubview(name)
        stack.addArrangedSubview(expected)
        window.contentView = stack
        window.center()
        return window
    }
}

@MainActor
final class DiagnosticsAppDelegate: NSObject, NSApplicationDelegate {
    private let scenario: DiagnosticsScenario
    private var controller: DiagnosticsApplicationController?

    init(scenario: DiagnosticsScenario) {
        self.scenario = scenario
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            let controller = await DiagnosticsApplicationController.make(scenario: scenario)
            self.controller = controller
            controller.present()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.session.cancelAll()
    }
}
