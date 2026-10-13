import AppKit
import ServiceManagement

/// Terminal apps a container shell can open in.
enum TerminalApp: String, CaseIterable, Identifiable {
    case terminal, iterm, ghostty
    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal: return "Terminal"
        case .iterm: return "iTerm"
        case .ghostty: return "Ghostty"
        }
    }

    var bundleID: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm: return "com.googlecode.iterm2"
        case .ghostty: return "com.mitchellh.ghostty"
        }
    }

    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    var isInstalled: Bool { appURL != nil }
}

/// Shell started inside a container.
enum ContainerShell: String, CaseIterable, Identifiable {
    case auto, bash, sh
    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return tr("Automático")
        case .bash: return "bash"
        case .sh: return "sh"
        }
    }

    /// Command run with `docker exec -it`.
    var command: [String] {
        switch self {
        case .auto: return ["sh", "-c", "if command -v bash >/dev/null 2>&1; then exec bash; else exec sh; fi"]
        case .bash: return ["bash"]
        case .sh: return ["sh"]
        }
    }
}

/// User preferences, persisted in UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    /// Colima profile whose Docker engine the app shows.
    @Published var colimaProfile: String { didSet { defaults.set(colimaProfile, forKey: "colimaProfile") } }
    /// Seconds between refreshes while the window is visible (events also trigger refreshes).
    @Published var refreshInterval: Int { didSet { defaults.set(refreshInterval, forKey: "refreshInterval") } }
    @Published var terminalApp: TerminalApp { didSet { defaults.set(terminalApp.rawValue, forKey: "terminalApp") } }
    @Published var shell: ContainerShell { didSet { defaults.set(shell.rawValue, forKey: "shell") } }
    /// Show stacks and containers that aren't running.
    @Published var showStopped: Bool { didSet { defaults.set(showStopped, forKey: "showStopped") } }
    /// Lines of history loaded when opening logs.
    @Published var logTail: Int { didSet { defaults.set(logTail, forKey: "logTail") } }

    private init() {
        defaults.register(defaults: [
            "colimaProfile": "default",
            "refreshInterval": 5,
            "showStopped": true,
            "logTail": 500,
        ])
        colimaProfile = defaults.string(forKey: "colimaProfile") ?? "default"
        refreshInterval = defaults.integer(forKey: "refreshInterval")
        terminalApp = defaults.string(forKey: "terminalApp").flatMap(TerminalApp.init(rawValue:)) ?? .terminal
        shell = defaults.string(forKey: "shell").flatMap(ContainerShell.init(rawValue:)) ?? .auto
        showStopped = defaults.bool(forKey: "showStopped")
        logTail = defaults.integer(forKey: "logTail")
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Colimy: login item change failed: \(error)")
        }
    }
}
