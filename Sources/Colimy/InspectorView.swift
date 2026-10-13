import AppKit
import SwiftUI

/// Right-hand panel: logs and details of the selected container or stack.
struct InspectorView: View {
    let selection: Selection
    @ObservedObject private var store = DockerStore.shared
    @ObservedObject private var nav = MainSelection.shared
    @StateObject private var logs = LogStream()

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 12)
            SegmentedControl(options: [(tr("Logs"), InspectorTab.logs), (tr("Detalles"), .details)],
                             selection: $nav.tab, expand: true)
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            Rectangle().fill(Theme.line).frame(height: 1)
            Group {
                switch nav.tab {
                case .logs: LogPane(stream: logs)
                case .details: details
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.sidebar)
        .onAppear(perform: follow)
        .onDisappear { logs.stop() }
        .onChange(of: restartKey) { _, _ in
            // The log stream ends when a container stops; pick it up again when it's back.
            if !logs.isRunning { logs.resume() }
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        switch selection {
        case .container(let id):
            if let container = store.container(id) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                StatusDot(color: container.stateColor)
                                Text(container.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                                    .textSelection(.enabled)
                            }
                            HStack(spacing: 6) {
                                Badge(text: container.stateTitle, color: container.stateColor)
                                if let stack = container.stackName {
                                    Button { nav.select(.stack(stack)) } label: { Badge(text: stack, color: Theme.accentText) }
                                        .buttonStyle(.plain)
                                        .help(tr("Ir al stack"))
                                }
                                Text(container.status).font(.system(size: 11)).foregroundStyle(Theme.text3).lineLimit(1)
                            }
                        }
                        Spacer()
                        closeButton
                    }
                    HStack {
                        PortChips(ports: container.publishedPorts, limit: 2)
                        Spacer(minLength: 8)
                        ContainerActions(container: container, showLogs: false).fixedSize()
                    }
                }
            }
        case .stack(let name):
            if let stack = store.stack(name) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                StatusDot(color: stack.statusColor)
                                Text(stack.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            }
                            Text(tr("%d/%d en marcha", stack.runningCount, stack.containers.count))
                                .font(.system(size: 11)).foregroundStyle(Theme.text3)
                        }
                        Spacer()
                        closeButton
                    }
                    HStack {
                        PortChips(ports: stack.publishedPorts, limit: 2)
                        Spacer(minLength: 8)
                        StackActions(stack: stack).fixedSize()
                    }
                }
            }
        }
    }

    private var closeButton: some View {
        IconButton(symbol: "xmark", label: tr("Cerrar"), kind: .ghost, size: 26) { nav.selection = nil }
    }

    // MARK: Details

    @ViewBuilder
    private var details: some View {
        switch selection {
        case .container(let id):
            if let container = store.container(id) { ContainerDetailsView(container: container) }
        case .stack(let name):
            if let stack = store.stack(name) { StackDetailsView(stack: stack) }
        }
    }

    // MARK: Logs

    private func follow() {
        switch selection {
        case .container(let id):
            if let container = store.container(id) { logs.follow(.container(container)) }
        case .stack(let name):
            if let stack = store.stack(name) { logs.follow(.stack(stack)) }
        }
    }

    /// Changes when the selection starts running again.
    private var restartKey: String {
        switch selection {
        case .container(let id): return store.container(id).map { "\($0.state)|\($0.status.prefix(8))" } ?? ""
        case .stack(let name): return store.stack(name).map { "\($0.runningCount)" } ?? ""
        }
    }
}

// MARK: - Logs

private struct LogPane: View {
    @ObservedObject var stream: LogStream
    @ObservedObject private var store = DockerStore.shared
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ColimyTextField(placeholder: tr("Filtrar"), text: $filter, icon: "line.3.horizontal.decrease")
                if stream.isRunning {
                    HStack(spacing: 5) {
                        StatusDot(color: Theme.ok, size: 6)
                        Text(tr("En directo")).font(.system(size: 11)).foregroundStyle(Theme.text2)
                    }
                    .fixedSize()
                } else {
                    IconButton(symbol: "arrow.triangle.2.circlepath", label: tr("Reconectar"), kind: .secondary) {
                        stream.resume()
                    }
                }
                IconButton(symbol: "doc.on.doc", label: tr("Copiar todo"), kind: .ghost) { copy(stream.text) }
                IconButton(symbol: "trash", label: tr("Vaciar"), kind: .ghost) { stream.clear() }
                IconButton(symbol: "rectangle.portrait.and.arrow.right", label: tr("Abrir en Terminal"), kind: .ghost) {
                    openInTerminal()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            if let error = stream.error {
                ErrorBanner(message: error)
            }
            ZStack {
                LogTextView(lines: stream.lines, generation: stream.generation, filter: filter)
                if stream.lines.isEmpty {
                    Text(stream.isRunning ? tr("Esperando registros…") : tr("Sin registros"))
                        .foregroundStyle(Theme.text3)
                }
            }
            .background(Theme.editorBackground)
        }
    }

    private func openInTerminal() {
        guard let host = store.dockerHost, let source = stream.source, let docker = ExternalTool.docker.url else { return }
        switch source {
        case .container(let container):
            TerminalLauncher.open(title: container.name, host: host,
                                  command: [docker.path, "logs", "-f", "--tail", "200", container.id])
        case .stack(let stack):
            TerminalLauncher.open(title: stack.name, host: host,
                                  command: [docker.path] + Docker.composeArguments(stack) + ["logs", "-f", "--tail", "200"])
        }
    }
}

// MARK: - Details

private struct ContainerDetailsView: View {
    let container: Container
    @ObservedObject private var store = DockerStore.shared
    @State private var detail: ContainerDetail?
    @State private var error: String?
    @State private var showEnv = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error {
                    Text(error).foregroundStyle(Theme.danger)
                }
                section(tr("General")) {
                    row(tr("Imagen"), container.image)
                    row(tr("ID"), String(container.id.prefix(12)))
                    if let stats = store.stats(for: container) {
                        row(tr("CPU"), stats.cpu)
                        row(tr("Memoria"), "\(stats.memory) (\(stats.memoryPercent))")
                    }
                    if let detail {
                        row(tr("Creado"), formatDate(detail.created))
                        if container.isRunning, let started = detail.state.startedAt {
                            row(tr("Iniciado"), formatDate(started))
                        } else if let finished = detail.state.finishedAt {
                            row(tr("Parado"), formatDate(finished) + (detail.state.exitCode.map { " · " + tr("código %d", $0) } ?? ""))
                        }
                        row(tr("Comando"), detail.commandLine)
                        if let dir = detail.config.workingDir, !dir.isEmpty { row(tr("Directorio"), dir) }
                        if let user = detail.config.user, !user.isEmpty { row(tr("Usuario"), user) }
                        if let policy = detail.restartPolicy, !policy.isEmpty { row(tr("Reinicio"), policy) }
                    }
                }
                if !container.ports.isEmpty {
                    section(tr("Puertos")) {
                        ForEach(container.publishedPorts, id: \.self) { port in
                            row("\(port.hostPort)", "→ \(port.containerPort)/\(port.proto)")
                        }
                        if container.publishedPorts.isEmpty {
                            Text(container.ports).monospacedText(size: 11).foregroundStyle(Theme.text2)
                        }
                    }
                }
                if let detail {
                    if !detail.networks.isEmpty {
                        section(tr("Redes")) {
                            ForEach(detail.networks, id: \.name) { network in
                                row(network.name, network.ip.isEmpty ? "–" : network.ip)
                            }
                        }
                    }
                    if let mounts = detail.mounts, !mounts.isEmpty {
                        section(tr("Montajes")) {
                            ForEach(mounts, id: \.self) { mount in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mount.destination ?? "").monospacedText(size: 11.5)
                                    Text("\(mount.type ?? "") · \(abbreviated(mount.source ?? ""))\(mount.readWrite == false ? " · ro" : "")")
                                        .font(.system(size: 11)).foregroundStyle(Theme.text3).lineLimit(2)
                                }
                                .textSelection(.enabled)
                            }
                        }
                    }
                    if let env = detail.config.env, !env.isEmpty {
                        section(tr("Variables de entorno")) {
                            if showEnv {
                                ForEach(env, id: \.self) { item in
                                    Text(item).monospacedText(size: 11).foregroundStyle(Theme.text2)
                                        .textSelection(.enabled).lineLimit(3)
                                }
                            } else {
                                Button(tr("Mostrar %d variables", env.count)) { showEnv = true }
                                    .buttonStyle(.colimySecondary)
                                Text(tr("Pueden contener contraseñas.")).font(.system(size: 11)).foregroundStyle(Theme.text3)
                            }
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: "\(container.id)|\(container.state)") { await load() }
    }

    private func load() async {
        guard let host = store.dockerHost else { return }
        do {
            detail = try await Docker.inspect(container.id, host: host)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct StackDetailsView: View {
    let stack: Stack

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section(tr("General")) {
                    row(tr("Proyecto"), stack.name)
                    if !stack.workingDir.isEmpty { row(tr("Carpeta"), abbreviated(stack.workingDir)) }
                    row(tr("Servicios"), "\(stack.containers.count)")
                }
                if !stack.configFiles.isEmpty {
                    section(tr("Archivos de Compose")) {
                        ForEach(stack.configFiles, id: \.self) { file in
                            HStack {
                                Text(abbreviated(file)).monospacedText(size: 11.5).lineLimit(1).truncationMode(.middle)
                                    .foregroundStyle(FileManager.default.fileExists(atPath: file) ? Theme.text : Theme.danger)
                                Spacer()
                                IconButton(symbol: "arrow.up.forward.app", label: tr("Abrir"), kind: .ghost, size: 24) {
                                    NSWorkspace.shared.open(URL(fileURLWithPath: file))
                                }
                            }
                        }
                        if !stack.hasFiles {
                            Text(tr("Faltan archivos: solo se puede arrancar, parar, reiniciar y bajar."))
                                .font(.system(size: 11)).foregroundStyle(Theme.warn)
                        }
                    }
                }
                section(tr("Servicios")) {
                    ForEach(stack.containers) { container in
                        HStack(spacing: 8) {
                            StatusDot(color: container.stateColor, size: 7)
                            Text(container.displayName).lineLimit(1)
                            Spacer()
                            PortChips(ports: container.publishedPorts, limit: 2)
                            Text(container.stateTitle).font(.system(size: 11)).foregroundStyle(Theme.text3)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { MainSelection.shared.select(.container(container.id)) }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Helpers

private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        SectionLabel(title)
        VStack(alignment: .leading, spacing: 8, content: content)
    }
}

private func row(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(label).foregroundStyle(Theme.text3).frame(width: 96, alignment: .leading).lineLimit(1)
        Text(value.isEmpty ? "–" : value).textSelection(.enabled).lineLimit(3)
        Spacer(minLength: 0)
    }
    .font(.system(size: 12))
}

private func formatDate(_ iso: String) -> String {
    // Docker uses nanoseconds, which ISO8601DateFormatter can't parse.
    let trimmed = iso.replacingOccurrences(of: "\\.[0-9]+", with: "", options: .regularExpression)
    guard let date = ISO8601DateFormatter().date(from: trimmed), date.timeIntervalSince1970 > 0 else { return "–" }
    let formatter = DateFormatter()
    formatter.locale = Localizer.shared.locale
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    let relative = RelativeDateTimeFormatter()
    relative.locale = Localizer.shared.locale
    return "\(formatter.string(from: date)) (\(relative.localizedString(for: date, relativeTo: Date())))"
}
