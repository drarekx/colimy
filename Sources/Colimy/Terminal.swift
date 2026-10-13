import AppKit

/// Opens commands (a shell inside a container, `docker compose logs -f`…) in the
/// user's terminal app, through a temporary `.command` script.
enum TerminalLauncher {
    static let scriptPrefix = "Colimy-"

    @MainActor
    static func openShell(in container: Container) {
        guard let host = DockerStore.shared.dockerHost, let docker = ExternalTool.docker.url else { return }
        let command = [docker.path, "exec", "-it", container.id] + Settings.shared.shell.command
        open(title: container.name, host: host, command: command)
    }

    /// Command line to paste in a terminal, for "Copy command".
    @MainActor
    static func shellCommand(for container: Container) -> String {
        (["docker", "exec", "-it", container.name] + Settings.shared.shell.command).map(quote).joined(separator: " ")
    }

    @MainActor
    static func open(title: String, host: String, command: [String], directory: String? = nil) {
        let script = """
        #!/bin/zsh
        printf '\\033]0;%s\\007' \(quote(title))
        export PATH=\(quote(ExternalTool.childPath))
        export DOCKER_HOST=\(quote(host))
        \(directory.map { "cd \(quote($0)) || true" } ?? "")
        clear
        exec \(command.map(quote).joined(separator: " "))
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(scriptPrefix)\(UUID().uuidString).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            NSLog("Colimy: couldn't write terminal script: \(error)")
            return
        }

        let app = Settings.shared.terminalApp
        let appURL = app.appURL ?? TerminalApp.terminal.appURL
        guard let appURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        if app == .ghostty && app.isInstalled {
            // Ghostty doesn't run .command files; pass the script as the command of a new window.
            configuration.arguments = ["-e", url.path]
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        } else {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
        }
    }

    /// Scripts are tiny but pile up; remove the ones from earlier runs.
    static func removeOldScripts() {
        let temp = FileManager.default.temporaryDirectory
        let items = (try? FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)) ?? []
        for item in items where item.lastPathComponent.hasPrefix(scriptPrefix) && item.pathExtension == "command" {
            try? FileManager.default.removeItem(at: item)
        }
    }

    /// Single-quotes for zsh.
    static func quote(_ text: String) -> String {
        if !text.isEmpty, text.allSatisfy({ $0.isLetter || $0.isNumber || "-_./:=@%+,".contains($0) }) { return text }
        return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
