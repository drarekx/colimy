#if DEBUG
import AppKit

/// Development helper: renders the main window to a PNG and quits.
@MainActor
enum Snapshot {
    static func run(path: String, arguments: [String], show: () -> Void) {
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        let nav = MainSelection.shared
        switch value("--section") {
        case "containers": nav.section = .containers
        case "colima": nav.section = .colima
        case "settings": nav.section = .settings
        default: nav.section = .stacks
        }
        show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if let name = value("--select") {
                if let container = DockerStore.shared.containers.first(where: { $0.name == name }) {
                    nav.select(.container(container.id), logs: value("--tab") != "details")
                    if value("--tab") == "details" { nav.tab = .details }
                } else if DockerStore.shared.stack(name) != nil {
                    nav.select(.stack(name), logs: true)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                guard let view = NSApp.windows.first(where: { $0.title == "Colimy" })?.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                exit(0)
            }
        }
    }
}
#endif
