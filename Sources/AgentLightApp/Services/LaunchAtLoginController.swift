import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    var isOn: Bool { self == .enabled || self == .requiresApproval }
}

struct LaunchAtLoginController {
    var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        guard enabled != status.isOn else { return }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
