import Carbon.HIToolbox
import InstantTranslationInfrastructure

@MainActor
public protocol GlobalShortcutRegistering: AnyObject {
    func register(
        _ shortcut: KeyboardShortcut?,
        action: @escaping @MainActor () -> Void
    ) throws
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

    public init() {}

    public func register(
        _ shortcut: KeyboardShortcut?,
        action: @escaping @MainActor () -> Void
    ) throws {
        unregister()
        guard let shortcut else { return }
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // Carbon C callback 只负责跨到 MainActor；界面状态与闭包所有权不泄露到 C 边界。
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let owner = Unmanaged<CarbonGlobalShortcutRegistrar>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                MainActor.assumeIsolated { owner.action?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard handlerStatus == noErr else {
            self.action = nil
            throw ShortcutRegistrationError.carbonStatus(handlerStatus)
        }

        let identifier = EventHotKeyID(signature: OSType(0x4954524E), id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard status == noErr else {
            if let handler {
                RemoveEventHandler(handler)
            }
            handler = nil
            self.action = nil
            throw ShortcutRegistrationError.carbonStatus(status)
        }
    }

    public func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let handler {
            RemoveEventHandler(handler)
        }
        hotKey = nil
        handler = nil
        action = nil
    }
}
