import AppKit
import Combine

enum ContainerAction: String {
    case start, stop, restart, pause, unpause, kill, remove

    var arguments: [String] {
        switch self {
        case .remove: return ["rm", "-f"]
        default: return [rawValue]
        }
    }
}

enum StackAction: String {
    case up, start, stop, restart, down, pull

    var arguments: [String] {
        switch self {
        case .up: return ["up", "-d"]
        case .pull: return ["pull"]
        default: return [rawValue]
        }
    }
}

/// State of Colima and its Docker engine. Refreshes on a timer and on
/// `docker events`, and runs every action the UI and the menu offer.
@MainActor
final class DockerStore: ObservableObject {
    static let shared = DockerStore()

    @Published private(set) var profiles: [ColimaProfile] = []
    @Published private(set) var containers: [Container] = [] { didSet { rebuildStacks() } }
    @Published private(set) var stacks: [Stack] = []
    @Published private(set) var stats: [String: ContainerStats] = [:]
    /// `DOCKER_HOST` of the selected profile while it runs.
    @Published private(set) var dockerHost: String?
    @Published private(set) var loaded = false
    @Published private(set) var missingTools: [ExternalTool] = ExternalTool.missing
    /// Last refresh failure, shown in the window instead of an alert.
    @Published private(set) var refreshError: String?
    @Published private(set) var colimaAction: ColimaAction?
    @Published private(set) var colimaOutput: [String] = []
    /// Container IDs and `stack:<name>` keys with an action running.
    @Published private(set) var busy: Set<String> = []

    private let settings = Settings.shared
    private var timer: Timer?
    private var eventsTask: Task<Void, Never>?
    private var statsTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshAgain = false
    private var pendingRefresh: DispatchWorkItem?
    private var hostProfile: String?
    /// Profile the running Colima action applies to.
    private var actionProfile: String?
    private var cancellables = Set<AnyCancellable>()
    /// The window is on screen: refresh often and sample stats.
    private var active = false

    var profile: ColimaProfile? {
        profiles.first { $0.name == settings.colimaProfile } ?? profiles.first
    }

    var isRunning: Bool { dockerHost != nil }
    var runningCount: Int { containers.filter(\.isRunning).count }
    var standalone: [Container] { containers.filter { $0.stackName == nil } }

    func container(_ id: String) -> Container? { containers.first { $0.id == id } }
    func stack(_ name: String) -> Stack? { stacks.first { $0.name == name } }

    func start() {
        settings.$colimaProfile.dropFirst().removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.setHost(nil, profile: nil)
                    self?.containers = []
                    await self?.refresh()
                }
            }
            .store(in: &cancellables)
        settings.$refreshInterval.dropFirst().removeDuplicates()
            .sink { [weak self] _ in Task { @MainActor in self?.scheduleTimer() } }
            .store(in: &cancellables)
        scheduleTimer()
        refreshSoon(delay: 0)
    }

    /// The main window became visible or hidden.
    func setActive(_ active: Bool) {
        guard active != self.active else { return }
        self.active = active
        scheduleTimer()
        updateStatsLoop()
        if active { refreshSoon(delay: 0) }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        // Hidden: only keep the menu bar icon roughly in sync.
        let interval = active ? TimeInterval(max(2, settings.refreshInterval)) : 30
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSoon(delay: 0) }
        }
    }

    /// Coalesces bursts (e.g. a stack's events) into one refresh.
    func refreshSoon(delay: TimeInterval = 0.4) {
        pendingRefresh?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.startRefresh() }
        }
        pendingRefresh = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func startRefresh() {
        guard refreshTask == nil else { refreshAgain = true; return }
        refreshTask = Task { [weak self] in
            await self?.refresh()
            guard let self else { return }
            self.refreshTask = nil
            if self.refreshAgain {
                self.refreshAgain = false
                self.startRefresh()
            }
        }
    }

    func refresh() async {
        missingTools = ExternalTool.missing
        guard missingTools.isEmpty else {
            loaded = true
            return
        }
        do {
            profiles = try await Colima.profiles()
            // While the selected profile is stopping or restarting, its socket is going away.
            let goingDown = colimaAction != nil && colimaAction != .start && actionProfile == profile?.name
            guard let profile, profile.isRunning, !goingDown else {
                setHost(nil, profile: nil)
                containers = []
                stats = [:]
                refreshError = nil
                loaded = true
                return
            }
            if dockerHost == nil || hostProfile != profile.name {
                setHost(await Colima.dockerSocket(profile: profile.name), profile: profile.name)
            }
            guard let host = dockerHost else { return }
            let list = try await Docker.containers(host: host)
            if list != containers { containers = list }
            refreshError = nil
        } catch {
            refreshError = error.localizedDescription
        }
        loaded = true
    }

    private func setHost(_ host: String?, profile: String?) {
        guard host != dockerHost else { return }
        dockerHost = host
        hostProfile = profile
        eventsTask?.cancel()
        eventsTask = nil
        if let host { watchEvents(host: host) }
        updateStatsLoop()
    }

    private func rebuildStacks() {
        let grouped = Dictionary(grouping: containers.filter { $0.stackName != nil }, by: { $0.project })
        stacks = grouped
            .map { Stack(name: $0.key, containers: $0.value.sorted { $0.displayName < $1.displayName }) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Events and stats

    /// Container lifecycle events trigger a refresh, so the lists follow changes made elsewhere too.
    private func watchEvents(host: String) {
        let events = ["create", "start", "restart", "stop", "die", "destroy", "pause", "unpause", "rename", "health_status"]
        let args = ["events", "--format", "{{.Status}}", "--filter", "type=container"]
            + events.flatMap { ["--filter", "event=\($0)"] }
        eventsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await ToolProcess.run(.docker, args, environment: Docker.environment(host: host)) { _ in
                    Task { @MainActor in self?.refreshSoon() }
                }
                // The stream ends when the VM stops; retry while this host is current.
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func updateStatsLoop() {
        statsTask?.cancel()
        statsTask = nil
        guard active, let host = dockerHost else {
            stats = [:]
            return
        }
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                if let sample = try? await Docker.stats(host: host), !Task.isCancelled {
                    self?.stats = sample
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stats(for container: Container) -> ContainerStats? {
        stats[String(container.id.prefix(12))]
    }

    // MARK: - Actions

    func perform(_ action: ContainerAction, on targets: [Container]) async {
        guard let host = dockerHost, !targets.isEmpty else { return }
        let ids = targets.map(\.id)
        busy.formUnion(ids)
        defer { busy.subtract(ids) }
        do {
            _ = try await ToolProcess.lines(.docker, action.arguments + ids, environment: Docker.environment(host: host))
        } catch {
            report(tr("No se pudo completar la acción"), error)
        }
        await refresh()
    }

    func perform(_ action: StackAction, on stack: Stack) async {
        guard let host = dockerHost else { return }
        // `up` needs the compose files; without them, start the existing containers.
        let action = action == .up && !stack.hasFiles ? .start : action
        let key = "stack:\(stack.name)"
        busy.insert(key)
        busy.formUnion(stack.containers.map(\.id))
        defer {
            busy.remove(key)
            busy.subtract(stack.containers.map(\.id))
        }
        do {
            _ = try await ToolProcess.lines(.docker, Docker.composeArguments(stack) + action.arguments,
                                            environment: Docker.environment(host: host))
        } catch {
            report(tr("No se pudo completar la acción en «%@»", stack.name), error)
        }
        await refresh()
    }

    func isBusy(_ stack: Stack) -> Bool { busy.contains("stack:\(stack.name)") }
    func isBusy(_ container: Container) -> Bool { busy.contains(container.id) }

    func colima(_ action: ColimaAction, profile name: String? = nil) async {
        guard colimaAction == nil else { return }
        let name = name ?? profile?.name ?? settings.colimaProfile
        colimaAction = action
        actionProfile = name
        colimaOutput = []
        if action != .start && name == hostProfile {
            setHost(nil, profile: nil)
            containers = []
        }
        do {
            try await Colima.run(action, profile: name) { line in
                let text = stripANSI(line)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.colimaOutput.append(text)
                    if self.colimaOutput.count > 400 { self.colimaOutput.removeFirst(100) }
                }
            }
        } catch {
            report(action.failure, error)
        }
        colimaAction = nil
        actionProfile = nil
        await refresh()
    }

    func clearColimaOutput() { colimaOutput = [] }

    private func report(_ title: String, _ error: Error) {
        if case ToolError.cancelled = error { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = stripANSI(error.localizedDescription)
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

private extension ColimaAction {
    var failure: String {
        switch self {
        case .start: return tr("No se pudo arrancar Colima")
        case .stop: return tr("No se pudo parar Colima")
        case .restart: return tr("No se pudo reiniciar Colima")
        }
    }
}

/// Asks before something that can't be undone. Returns `true` to go ahead.
@MainActor
func confirm(_ title: String, _ message: String, button: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: button)
    alert.addButton(withTitle: tr("Cancelar"))
    alert.buttons.first?.hasDestructiveAction = true
    NSApp.activate(ignoringOtherApps: true)
    return alert.runModal() == .alertFirstButtonReturn
}
