import AppKit
import SwiftUI

enum MainSection: Hashable {
    case stacks, containers, colima, settings
}

enum Selection: Hashable {
    case container(String)
    case stack(String)
}

enum InspectorTab: Hashable {
    case logs, details
}

/// Navigation state, shared so the menu bar can open a stack or container in the window.
@MainActor
final class MainSelection: ObservableObject {
    static let shared = MainSelection()

    @Published var section: MainSection = .stacks
    @Published var selection: Selection?
    @Published var tab: InspectorTab = .logs
    /// Stacks folded or unfolded by hand; by default only stacks with something running are unfolded.
    @Published var toggled: Set<String> = []

    func isExpanded(_ stack: Stack) -> Bool {
        (stack.status != .stopped) != toggled.contains(stack.name)
    }

    func setExpanded(_ stack: Stack, _ expanded: Bool) {
        if expanded == isExpanded(stack) { return }
        if toggled.contains(stack.name) { toggled.remove(stack.name) } else { toggled.insert(stack.name) }
    }

    func select(_ selection: Selection, logs: Bool = false) {
        self.selection = selection
        if logs { tab = .logs }
        switch selection {
        case .stack(let name):
            section = .stacks
            if let stack = DockerStore.shared.stack(name) { setExpanded(stack, true) }
        case .container:
            if section != .stacks && section != .containers { section = .containers }
        }
    }
}

/// Main window: sidebar, the selected section and, for stacks and containers, an inspector.
struct MainView: View {
    @ObservedObject private var localizer = Localizer.shared
    @ObservedObject private var nav = MainSelection.shared

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            Rectangle().fill(Theme.line).frame(width: 1)
            Group {
                switch nav.section {
                case .stacks, .containers: ListArea()
                case .colima: ColimaPane()
                case .settings: SettingsPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .id(localizer.language)
        .background(Theme.window)
        .foregroundStyle(Theme.text)
        .font(.system(size: 13))
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .frame(minWidth: 980, minHeight: 600)
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @ObservedObject private var nav = MainSelection.shared
    @ObservedObject private var store = DockerStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Theme.accentFill)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "shippingbox.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    }
                Text("Colimy").font(.system(size: 16, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.top, 18)

            VStack(spacing: 2) {
                navItem(tr("Stacks"), "square.stack.3d.up", .stacks,
                        count: store.isRunning ? "\(store.stacks.filter { $0.runningCount > 0 }.count)/\(store.stacks.count)" : nil)
                navItem(tr("Contenedores"), "shippingbox", .containers,
                        count: store.isRunning ? "\(store.runningCount)/\(store.containers.count)" : nil)
                navItem(tr("Colima"), "cpu", .colima, count: nil)
                navItem(tr("Ajustes"), "gearshape", .settings, count: nil)
            }

            Spacer()

            EngineCard()

            Text(tr("Versión %@", Updater.currentVersion))
                .font(.system(size: 11)).foregroundStyle(Theme.text3)
                .padding(.horizontal, 10)
        }
        .padding(.horizontal, 12)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(width: 230)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
    }

    private func navItem(_ title: String, _ symbol: String, _ target: MainSection, count: String?) -> some View {
        let selected = nav.section == target
        return Button { nav.section = target } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Theme.accentText : Theme.text2)
                    .frame(width: 18)
                Text(title).fontWeight(selected ? .medium : .regular)
                Spacer()
                if let count {
                    Text(count).font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(selected ? Color(hex: 0xA9B8DD) : Theme.text3)
                }
            }
            .foregroundStyle(selected ? .white : Color(hex: 0xC7C7CC))
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(selected ? Theme.navSelected : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Colima status and its start / stop button, at the bottom of the sidebar.
struct EngineCard: View {
    @ObservedObject private var store = DockerStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if store.colimaAction != nil {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 8, height: 8)
                } else {
                    StatusDot(color: store.isRunning ? Theme.ok : Theme.text3)
                }
                Text(title).fontWeight(.medium).lineLimit(1)
            }
            Text(detail)
                .font(.system(size: 11)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
            if store.missingTools.isEmpty {
                Button {
                    if store.isRunning { stopColima() } else { Task { await store.colima(.start) } }
                } label: {
                    Label(store.isRunning ? tr("Parar Colima") : tr("Arrancar Colima"),
                          systemImage: store.isRunning ? "stop.fill" : "play.fill")
                }
                .buttonStyle(ColimyButtonStyle(kind: store.isRunning ? .secondary : .primary, height: 30, fullWidth: true))
                .disabled(store.colimaAction != nil || !store.loaded)
            }
        }
        .padding(12)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line) }
    }

    private var title: String {
        if let action = store.colimaAction { return action.title }
        if !store.missingTools.isEmpty { return tr("Faltan herramientas") }
        if !store.loaded { return tr("Comprobando…") }
        return store.isRunning ? tr("Colima en marcha") : tr("Colima parado")
    }

    private var detail: String {
        if !store.missingTools.isEmpty {
            return tr("Instálalas con: brew install colima docker docker-compose")
        }
        let name = store.profile?.name ?? Settings.shared.colimaProfile
        if store.isRunning {
            return tr("Perfil «%@» · %d contenedores en marcha", name, store.runningCount)
        }
        return tr("Perfil «%@»", name)
    }

    private func stopColima() {
        let running = store.runningCount
        if running > 0, !confirm(tr("¿Parar Colima?"),
                                 tr("Se pararán los %d contenedores en marcha.", running),
                                 button: tr("Parar Colima")) { return }
        Task { await store.colima(.stop) }
    }
}

// MARK: - Stacks / containers area

/// Stacks or containers list with its toolbar, plus the inspector for the selection.
private struct ListArea: View {
    @ObservedObject private var nav = MainSelection.shared
    @ObservedObject private var store = DockerStore.shared
    @ObservedObject private var settings = Settings.shared
    @State private var search = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                toolbar
                Rectangle().fill(Theme.line).frame(height: 1)
                if let error = store.refreshError, store.isRunning {
                    ErrorBanner(message: error)
                }
                GeometryReader { proxy in
                    content
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .environment(\.compactRows, proxy.size.width < 860)
                }
            }
            if let selection = nav.selection, store.isRunning, exists(selection) {
                Rectangle().fill(Theme.line).frame(width: 1)
                InspectorView(selection: selection)
                    .frame(width: 460)
                    .id(selection)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(nav.section == .stacks ? tr("Stacks") : tr("Contenedores"))
                .font(.system(size: 20, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
            Spacer()
            SegmentedControl(options: [(tr("Todos"), true), (tr("En marcha"), false)],
                             selection: $settings.showStopped)
                .fixedSize()
            ColimyTextField(placeholder: tr("Buscar"), text: $search, icon: "magnifyingglass")
                .frame(minWidth: 120, maxWidth: 220)
            IconButton(symbol: "arrow.clockwise", label: tr("Actualizar"), kind: .secondary) {
                store.refreshSoon(delay: 0)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if !store.missingTools.isEmpty {
            MissingToolsView()
        } else if !store.loaded {
            ProgressView().controlSize(.small)
        } else if !store.isRunning {
            EngineStoppedView()
        } else if nav.section == .stacks {
            StacksList(search: search)
        } else {
            ContainersList(search: search)
        }
    }

    private func exists(_ selection: Selection) -> Bool {
        switch selection {
        case .container(let id): return store.container(id) != nil
        case .stack(let name): return store.stack(name) != nil
        }
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
            Text(message).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(2).textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(Theme.warn.opacity(0.08))
    }
}

/// Shown instead of the lists while Colima is stopped.
struct EngineStoppedView: View {
    @ObservedObject private var store = DockerStore.shared

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "shippingbox").font(.system(size: 40, weight: .light)).foregroundStyle(Theme.text3)
            if let action = store.colimaAction {
                Text(action.title).font(.system(size: 15, weight: .semibold))
                ProgressView().controlSize(.small)
                if let last = store.colimaOutput.last {
                    Text(last).monospacedText(size: 11).foregroundStyle(Theme.text3).lineLimit(1).frame(maxWidth: 520)
                }
            } else {
                Text(tr("Colima está parado")).font(.system(size: 15, weight: .semibold))
                Text(tr("Arráncalo para ver tus stacks y contenedores."))
                    .foregroundStyle(Theme.text2)
                Button {
                    Task { await store.colima(.start) }
                } label: {
                    Label(tr("Arrancar Colima"), systemImage: "play.fill")
                }
                .buttonStyle(.colimyPrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MissingToolsView: View {
    @ObservedObject private var store = DockerStore.shared

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wrench.and.screwdriver").font(.system(size: 36, weight: .light)).foregroundStyle(Theme.text3)
            Text(tr("Falta instalar: %@", store.missingTools.map(\.rawValue).joined(separator: ", ")))
                .font(.system(size: 15, weight: .semibold))
            Text(tr("Colimy usa Colima y el cliente de Docker. Instálalos con Homebrew:"))
                .foregroundStyle(Theme.text2)
            Text("brew install colima docker docker-compose")
                .monospacedText()
                .textSelection(.enabled)
                .padding(10)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.radius))
            Button(tr("Comprobar de nuevo")) { store.refreshSoon(delay: 0) }
                .buttonStyle(.colimySecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
