import ServiceManagement

/// Where Cue stands as a login item, as macOS reports it. The menu shows it and decides what a click does.
public enum LoginItemStatus: Sendable, Equatable {
    /// Not a login item.
    case notRegistered
    /// A login item that starts at the next login.
    case enabled
    /// Registered, but macOS waits for the user to allow it in System Settings > General > Login Items.
    case requiresApproval
    /// macOS cannot find the app to register.
    case notFound

    public init(_ status: SMAppService.Status) {
        switch status {
        case .notRegistered: self = .notRegistered
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        @unknown default: self = .notFound
        }
    }

    public enum Mark: Sendable, Equatable {
        case off, on, mixed
    }

    /// The menu item's checkmark: on only when Cue will really start at login, a dash while macOS waits for approval.
    public var mark: Mark {
        switch self {
        case .enabled: .on
        case .requiresApproval: .mixed
        case .notRegistered, .notFound: .off
        }
    }

    /// Whether choosing the menu item should register Cue; otherwise it removes the login item.
    public var registersOnToggle: Bool {
        switch self {
        case .notRegistered, .notFound: true
        case .enabled, .requiresApproval: false
        }
    }

    /// Whether the menu points the user to System Settings to allow the login item.
    public var needsApproval: Bool {
        self == .requiresApproval
    }
}
