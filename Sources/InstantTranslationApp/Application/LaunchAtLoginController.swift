import ServiceManagement

@MainActor
public protocol LaunchAtLoginControlling: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    var isEnabled: Bool { get }
    func register() throws
    func unregister() throws
}

@MainActor
private final class MainAppLaunchAtLoginService: LaunchAtLoginServicing {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var isEnabled: Bool {
        service.status == .enabled
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}

@MainActor
public final class LaunchAtLoginController: LaunchAtLoginControlling {
    private let service: any LaunchAtLoginServicing

    public convenience init() {
        self.init(service: MainAppLaunchAtLoginService())
    }

    init(service: any LaunchAtLoginServicing) {
        self.service = service
    }

    public var isEnabled: Bool {
        service.isEnabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        guard enabled != service.isEnabled else { return }
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}
