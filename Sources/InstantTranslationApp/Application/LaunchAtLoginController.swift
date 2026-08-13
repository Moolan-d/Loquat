import ServiceManagement

public enum LaunchAtLoginStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

    public var isRegistered: Bool {
        self == .enabled || self == .requiresApproval
    }

    public var isEnabled: Bool {
        self == .enabled
    }
}

@MainActor
public protocol LaunchAtLoginControlling: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func setEnabled(_ enabled: Bool) throws
}

public extension LaunchAtLoginControlling {
    var isEnabled: Bool { status.isEnabled }
}

@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
}

@MainActor
private final class MainAppLaunchAtLoginService: LaunchAtLoginServicing {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var status: LaunchAtLoginStatus {
        switch service.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .notFound
        }
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

    public var status: LaunchAtLoginStatus {
        service.status
    }

    public func setEnabled(_ enabled: Bool) throws {
        guard enabled != service.status.isRegistered else { return }
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}
