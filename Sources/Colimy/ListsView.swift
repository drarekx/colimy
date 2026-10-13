import AppKit
import SwiftUI

// MARK: - Stacks

struct StacksList: View {
    let search: String
    @ObservedObject private var store = DockerStore.shared
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        let stacks = store.stacks.filter(matches)
        let loose = store.standalone.filter { visible($0) && matches($0) }
        if stacks.isEmpty && loose.isEmpty {
            EmptyListView(text: search.isEmpty ? tr("No hay stacks") : tr("Nada coincide con «%@»", search))
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(stacks) { stack in
                        StackCard(stack: stack, containers: stack.containers.filter(visible))
                    }
                    if !loose.isEmpty {
                        LooseCard(containers: loose)
                    }
                }
                .padding(20)
            }
        }
    }

    private func visible(_ container: Container) -> Bool { settings.showStopped || container.isRunning }

    private func matches(_ stack: Stack) -> Bool {
        guard settings.showStopped || stack.runningCount > 0 else { return false }
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return stack.name.localizedCaseInsensitiveContains(query) || stack.containers.contains { matches($0) }
    }

    private func matches(_ container: Container) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [container.name, container.image, container.project].contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

private struct StackCard: View {
    let stack: Stack
    let containers: [Container]
    @ObservedObject private var store = DockerStore.shared
    @ObservedObject private var nav = MainSelection.shared
    @Environment(\.compactRows) private var compact

    private var expanded: Bool { nav.isExpanded(stack) }
    private var selected: Bool { nav.selection == .stack(stack.name) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded && !containers.isEmpty {
                Rectangle().fill(Theme.line).frame(height: 1)
                VStack(spacing: 0) {
                    ForEach(containers) { container in
                        ContainerRow(container: container, title: container.displayName)
                        if container.id != containers.last?.id {
                            Rectangle().fill(Theme.line.opacity(0.6)).frame(height: 1).padding(.leading, 44)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Theme.accentBorder : Theme.line)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                nav.setExpanded(stack, !expanded)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.text3)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 16, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded ? tr("Plegar") : tr("Desplegar"))

            StatusDot(color: stack.statusColor, size: 9)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(stack.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(tr("%d/%d en marcha", stack.runningCount, stack.containers.count))
                        .font(.system(size: 11)).foregroundStyle(Theme.text3).monospacedDigit()
                        .lineLimit(1).fixedSize()
                }
                if !stack.workingDir.isEmpty {
                    Text(abbreviated(stack.workingDir))
                        .font(.system(size: 11)).foregroundStyle(Theme.text3).lineLimit(1).truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            if !compact { PortChips(ports: stack.publishedPorts, limit: 3) }
            StackActions(stack: stack)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { nav.select(.stack(stack.name)) }
    }
}

/// Containers that don't belong to any Compose project.
private struct LooseCard: View {
    let containers: [Container]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox").foregroundStyle(Theme.text3).frame(width: 16)
                Text(tr("Contenedores sueltos")).font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            Rectangle().fill(Theme.line).frame(height: 1)
            VStack(spacing: 0) {
                ForEach(containers) { container in
                    ContainerRow(container: container, title: container.name)
                }
            }
            .padding(.vertical, 4)
        }
        .colimyCard(padding: 0)
    }
}

struct StackActions: View {
    let stack: Stack
    @ObservedObject private var store = DockerStore.shared
    @ObservedObject private var nav = MainSelection.shared

    var body: some View {
        HStack(spacing: 6) {
            if store.isBusy(stack) {
                ProgressView().controlSize(.small).frame(width: 32, height: 32)
            } else {
                if stack.status != .running {
                    IconButton(symbol: "play.fill", label: tr("Arrancar"), kind: .secondary) { run(.up) }
                }
                if stack.status != .stopped {
                    IconButton(symbol: "stop.fill", label: tr("Parar"), kind: .secondary) { run(.stop) }
                    IconButton(symbol: "arrow.clockwise", label: tr("Reiniciar"), kind: .secondary) { run(.restart) }
                }
            }
            IconButton(symbol: "text.alignleft", label: tr("Ver logs"), kind: .ghost) {
                nav.select(.stack(stack.name), logs: true)
            }
            Menu {
                if stack.hasFiles {
                    Button(tr("Recrear (up -d)")) { run(.up) }
                    Button(tr("Descargar imágenes (pull)")) { run(.pull) }
                }
                if !stack.workingDir.isEmpty {
                    Button(tr("Abrir terminal en la carpeta")) { openTerminalHere() }
                    Button(tr("Mostrar en Finder")) {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: stack.workingDir)
                    }
                    Button(tr("Copiar ruta")) { copy(stack.workingDir) }
                }
                Divider()
                Button(tr("Bajar (down)…"), role: .destructive) { down() }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(Theme.text2)
            .frame(width: 28)
            .disabled(store.isBusy(stack))
            .help(tr("Más acciones"))
        }
    }

    private func run(_ action: StackAction) {
        Task { await store.perform(action, on: stack) }
    }

    private func down() {
        guard confirm(tr("¿Bajar «%@»?", stack.name),
                      tr("Se pararán y eliminarán sus contenedores y redes. Los volúmenes y las imágenes se conservan."),
                      button: tr("Bajar")) else { return }
        run(.down)
    }

    private func openTerminalHere() {
        guard let host = store.dockerHost else { return }
        TerminalLauncher.open(title: stack.name, host: host, command: ["/bin/zsh", "-l"], directory: stack.workingDir)
    }
}

// MARK: - Containers

struct ContainersList: View {
    let search: String
    @ObservedObject private var store = DockerStore.shared
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespaces)
        let containers = store.containers
            .filter { settings.showStopped || $0.isRunning }
            .filter { query.isEmpty || [$0.name, $0.image, $0.project].contains { $0.localizedCaseInsensitiveContains(query) } }
            .sorted {
                if $0.isRunning != $1.isRunning { return $0.isRunning }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        if containers.isEmpty {
            EmptyListView(text: query.isEmpty ? tr("No hay contenedores") : tr("Nada coincide con «%@»", query))
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(containers) { container in
                        ContainerRow(container: container, title: container.name, showStack: true)
                        Rectangle().fill(Theme.line.opacity(0.6)).frame(height: 1).padding(.leading, 44)
                    }
                }
                .padding(.vertical, 6)
                .colimyCard(padding: 0)
                .padding(20)
            }
        }
    }
}

struct ContainerRow: View {
    let container: Container
    let title: String
    var showStack = false
    @ObservedObject private var store = DockerStore.shared
    @ObservedObject private var nav = MainSelection.shared
    @Environment(\.compactRows) private var compact
    @State private var hovering = false

    private var selected: Bool { nav.selection == .container(container.id) }

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(color: container.stateColor)
                .frame(width: 16)
                .padding(.leading, 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).fontWeight(.medium).lineLimit(1)
                    if showStack, let stack = container.stackName {
                        Badge(text: stack, color: Theme.accentText)
                    }
                    if let health = container.health {
                        Badge(text: healthTitle(health), color: container.stateColor)
                    }
                }
                Text(container.image)
                    .font(.system(size: 11)).foregroundStyle(Theme.text3).lineLimit(1).truncationMode(.middle)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            if !compact {
                PortChips(ports: container.publishedPorts, limit: 2)
                usage.frame(width: 110, alignment: .trailing)
                Text(container.isRunning ? shortStatus : container.stateTitle)
                    .font(.system(size: 11)).foregroundStyle(Theme.text3).lineLimit(1)
                    .frame(width: 92, alignment: .trailing)
            }
            ContainerActions(container: container, showLogs: !compact)
                .padding(.trailing, 10)
        }
        .frame(height: 50)
        .background(selected ? Theme.accentSoft.opacity(0.7) : hovering ? Color.white.opacity(0.03) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { nav.select(.container(container.id)) }
        .contextMenu { ContainerMenuItems(container: container) }
    }

    @ViewBuilder
    private var usage: some View {
        if container.isRunning, let stats = store.stats(for: container) {
            VStack(alignment: .trailing, spacing: 1) {
                Text("CPU \(stats.cpu)").font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.text2)
                Text(stats.memory).font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.text3)
            }
        }
    }

    /// "Up 33 hours (healthy)" → "33 hours".
    private var shortStatus: String {
        var text = container.status
        if let paren = text.firstIndex(of: "(") { text = String(text[..<paren]) }
        if text.hasPrefix("Up ") { text.removeFirst(3) }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private func healthTitle(_ health: Container.Health) -> String {
        switch health {
        case .healthy: return tr("sano")
        case .unhealthy: return tr("con fallos")
        case .starting: return tr("comprobando")
        }
    }
}

struct ContainerActions: View {
    let container: Container
    var showLogs = true
    @ObservedObject private var store = DockerStore.shared
    @ObservedObject private var nav = MainSelection.shared

    var body: some View {
        HStack(spacing: 6) {
            if store.isBusy(container) {
                ProgressView().controlSize(.small).frame(width: 32, height: 32)
            } else if container.isRunning {
                IconButton(symbol: "terminal", label: tr("Abrir terminal"), kind: .secondary) {
                    TerminalLauncher.openShell(in: container)
                }
                IconButton(symbol: "stop.fill", label: tr("Parar"), kind: .secondary) { run(.stop) }
                IconButton(symbol: "arrow.clockwise", label: tr("Reiniciar"), kind: .secondary) { run(.restart) }
            } else if container.isPaused {
                IconButton(symbol: "play.fill", label: tr("Reanudar"), kind: .secondary) { run(.unpause) }
            } else {
                IconButton(symbol: "play.fill", label: tr("Arrancar"), kind: .secondary) { run(.start) }
            }
            if showLogs {
                IconButton(symbol: "text.alignleft", label: tr("Ver logs"), kind: .ghost) {
                    nav.select(.container(container.id), logs: true)
                }
            }
            Menu {
                ContainerMenuItems(container: container)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(Theme.text2)
            .frame(width: 28)
            .disabled(store.isBusy(container))
            .help(tr("Más acciones"))
        }
    }

    private func run(_ action: ContainerAction) {
        Task { await store.perform(action, on: [container]) }
    }
}

/// Shared by the "…" menu and the context menu.
struct ContainerMenuItems: View {
    let container: Container
    @ObservedObject private var store = DockerStore.shared
    @ObservedObject private var nav = MainSelection.shared

    var body: some View {
        if container.isRunning {
            Button(tr("Abrir terminal")) { TerminalLauncher.openShell(in: container) }
            ForEach(container.publishedPorts.filter { $0.url != nil }, id: \.self) { port in
                Button(tr("Abrir localhost:%@", port.hostPort)) { NSWorkspace.shared.open(port.url!) }
            }
            Divider()
        }
        Button(tr("Ver logs")) { nav.select(.container(container.id), logs: true) }
        Button(tr("Detalles")) {
            nav.select(.container(container.id))
            nav.tab = .details
        }
        Divider()
        if container.isRunning {
            Button(tr("Parar")) { run(.stop) }
            Button(tr("Reiniciar")) { run(.restart) }
            Button(tr("Pausar")) { run(.pause) }
            Button(tr("Forzar parada (kill)")) { run(.kill) }
        } else if container.isPaused {
            Button(tr("Reanudar")) { run(.unpause) }
        } else {
            Button(tr("Arrancar")) { run(.start) }
        }
        Divider()
        Button(tr("Copiar nombre")) { copy(container.name) }
        Button(tr("Copiar ID")) { copy(container.id) }
        Button(tr("Copiar comando de terminal")) { copy(TerminalLauncher.shellCommand(for: container)) }
        Divider()
        Button(tr("Eliminar…"), role: .destructive) {
            guard confirm(tr("¿Eliminar «%@»?", container.name),
                          container.stackName == nil
                              ? tr("El contenedor se borrará. Sus volúmenes con nombre se conservan.")
                              : tr("El contenedor se borrará. Volverá a crearse la próxima vez que arranques el stack."),
                          button: tr("Eliminar")) else { return }
            run(.remove)
        }
    }

    private func run(_ action: ContainerAction) {
        Task { await store.perform(action, on: [container]) }
    }
}

// MARK: - Shared

/// Published ports as small links that open localhost in the browser.
struct PortChips: View {
    let ports: [PortMapping]
    var limit = 3

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ports.prefix(limit), id: \.self) { port in
                Button {
                    if let url = port.url { NSWorkspace.shared.open(url) }
                } label: {
                    HStack(spacing: 3) {
                        if port.url != nil { Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .bold)) }
                        Text(port.label).monospacedDigit()
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(port.url != nil ? Theme.accentText : Theme.text2)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(Theme.accentSoft.opacity(port.url != nil ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .disabled(port.url == nil)
                .help(port.url.map { $0.absoluteString } ?? "\(port.hostPort)→\(port.containerPort)/\(port.proto)")
            }
            if ports.count > limit {
                Text("+\(ports.count - limit)").font(.system(size: 11)).foregroundStyle(Theme.text3)
                    .help(ports.dropFirst(limit).map(\.label).joined(separator: ", "))
            }
        }
    }
}

struct EmptyListView: View {
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray").font(.system(size: 32, weight: .light)).foregroundStyle(Theme.text3)
            Text(text).foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// "/Users/me/projects/x" → "~/projects/x".
func abbreviated(_ path: String) -> String {
    (path as NSString).abbreviatingWithTildeInPath
}
