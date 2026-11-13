import SwiftUI

/// Colima profiles (VMs): status, resources, start / stop / restart and the output of the last action.
struct ColimaPane: View {
    @ObservedObject private var store = DockerStore.shared
    @ObservedObject private var settings = Settings.shared

    private let columns = [GridItem(.adaptive(minimum: 380), spacing: 20, alignment: .top)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(tr("Colima")).font(.system(size: 20, weight: .semibold))
                Spacer()
                IconButton(symbol: "arrow.clockwise", label: tr("Actualizar"), kind: .secondary) {
                    store.refreshSoon(delay: 0)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            Rectangle().fill(Theme.line).frame(height: 1)

            if !store.missingTools.isEmpty {
                MissingToolsView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if store.profiles.isEmpty && store.loaded {
                            noProfiles
                        }
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(store.profiles) { profile in
                                ProfileCard(profile: profile, selected: profile.name == store.profile?.name)
                            }
                        }
                        if store.colimaAction != nil || !store.colimaOutput.isEmpty {
                            outputCard
                        }
                        Text(tr("Para crear otro perfil o cambiar CPU, memoria y disco, usa «colima start -p <nombre> --cpu 4 --memory 8» o «colima start --edit» en Terminal."))
                            .font(.system(size: 11)).foregroundStyle(Theme.text3)
                    }
                    .padding(24)
                    .frame(maxWidth: 1180, alignment: .leading)
                }
            }
        }
    }

    private var noProfiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Colima aún no tiene ningún perfil")).font(.system(size: 14, weight: .semibold))
            Text(tr("Arrancarlo crea el perfil «default» con 2 CPU, 2 GB de memoria y Docker."))
                .foregroundStyle(Theme.text2)
            Button {
                Task { await store.colima(.start, profile: "default") }
            } label: {
                Label(tr("Crear y arrancar"), systemImage: "play.fill")
            }
            .buttonStyle(.colimyPrimary)
            .disabled(store.colimaAction != nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .colimyCard()
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.colimaAction?.title ?? tr("Última operación")).font(.system(size: 14, weight: .semibold))
                if store.colimaAction != nil { ProgressView().controlSize(.small) }
                Spacer()
                if store.colimaAction == nil {
                    Button(tr("Ocultar")) { store.clearColimaOutput() }.buttonStyle(.colimyGhost)
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(store.colimaOutput.enumerated()), id: \.offset) { index, line in
                            Text(line).monospacedText(size: 11).foregroundStyle(Theme.text2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .textSelection(.enabled)
                    .padding(10)
                }
                .frame(height: 220)
                .background(Theme.editorBackground, in: RoundedRectangle(cornerRadius: Theme.radius))
                .onChange(of: store.colimaOutput.count) { _, count in
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
        .colimyCard()
    }
}

private struct ProfileCard: View {
    let profile: ColimaProfile
    let selected: Bool
    @ObservedObject private var store = DockerStore.shared
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                StatusDot(color: profile.isRunning ? Theme.ok : Theme.text3, size: 9)
                Text(profile.name).font(.system(size: 15, weight: .semibold))
                Badge(text: profile.isRunning ? tr("En marcha") : tr("Parado"),
                      color: profile.isRunning ? Theme.ok : Theme.text2)
                Spacer()
                if selected {
                    Badge(text: tr("En uso"), color: Theme.accentText)
                } else {
                    Button(tr("Usar este perfil")) { settings.colimaProfile = profile.name }
                        .buttonStyle(ColimyButtonStyle(kind: .secondary, height: 24))
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    stat(tr("CPU"), profile.cpus.map(String.init) ?? "–")
                    stat(tr("Memoria"), profile.memoryLabel)
                    stat(tr("Disco"), profile.diskLabel)
                }
                GridRow {
                    stat(tr("Arquitectura"), profile.arch ?? "–")
                    stat(tr("Motor"), profile.runtime ?? "–")
                    stat(tr("Dirección"), profile.address?.isEmpty == false ? profile.address! : "–")
                }
            }

            Rectangle().fill(Theme.line).frame(height: 1)
            NetworkSection(profile: profile, selected: selected)
            Rectangle().fill(Theme.line).frame(height: 1)

            HStack(spacing: 8) {
                if profile.isRunning {
                    Button { stop() } label: { Label(tr("Parar"), systemImage: "stop.fill") }
                        .buttonStyle(.colimySecondary)
                    Button { run(.restart) } label: { Label(tr("Reiniciar"), systemImage: "arrow.clockwise") }
                        .buttonStyle(.colimySecondary)
                } else {
                    Button { run(.start) } label: { Label(tr("Arrancar"), systemImage: "play.fill") }
                        .buttonStyle(.colimyPrimary)
                }
            }
            .disabled(store.colimaAction != nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .colimyCard()
        .overlay {
            if selected { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accentBorder) }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.text3)
            Text(value).monospacedDigit().lineLimit(1)
        }
    }

    private func run(_ action: ColimaAction) {
        Task { await store.colima(action, profile: profile.name) }
    }

    private func stop() {
        let running = selected ? store.runningCount : 0
        if running > 0, !confirm(tr("¿Parar Colima?"),
                                 tr("Se pararán los %d contenedores en marcha.", running),
                                 button: tr("Parar Colima")) { return }
        run(.stop)
    }
}

/// Network settings of a profile: own IP address and shared / bridged mode.
/// Applying them restarts the profile with `colima start --network-…`.
private struct NetworkSection: View {
    let profile: ColimaProfile
    let selected: Bool
    @ObservedObject private var store = DockerStore.shared

    @State private var saved = ColimaNetwork()
    @State private var draft = ColimaNetwork()
    @State private var vmType: String?
    @State private var editing = false
    @State private var interfaces: [HostInterface] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(tr("Red"))
                Spacer()
                if !editing {
                    Button(tr("Configurar")) { startEditing() }
                        .buttonStyle(ColimyButtonStyle(kind: .ghost, height: 24))
                        .disabled(store.colimaAction != nil)
                }
            }
            if editing {
                editor
            } else {
                Text(summary(saved))
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: load)
        .onChange(of: store.colimaAction) { _, action in
            if action == nil { load() }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            SegmentedControl(options: [(tr("Compartida"), ColimaNetwork.Mode.shared),
                                       (tr("Puente"), ColimaNetwork.Mode.bridged)],
                             selection: $draft.mode, expand: true)
            Text(draft.mode == .shared
                 ? tr("Los contenedores salen a tu red a través del Mac (NAT). Los demás dispositivos solo llegan a ellos por los puertos publicados.")
                 : tr("La VM recibe una IP de tu router, como un aparato más de la red: los dispositivos llegan a ella directamente y funcionan mDNS, multicast y descubrimiento."))
                .font(.system(size: 11)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)

            if draft.mode == .shared {
                SwitchRow(title: tr("Dirección IP propia"),
                          detail: tr("La VM recibe una IP a la que se llega desde el Mac (no desde otros dispositivos)."),
                          isOn: $draft.address)
            } else {
                HStack {
                    Text(tr("Interfaz")).foregroundStyle(Theme.text2)
                    Spacer()
                    Menu {
                        ForEach(interfaceOptions) { item in
                            Button("\(item.displayName) (\(item.name))") { draft.interface = item.name }
                        }
                    } label: {
                        Text(interfaceLabel(draft.interface))
                    }
                    .menuStyle(.borderlessButton)
                    .tint(Theme.text)
                    .fixedSize()
                }
                if Colima.needsSudoSetup(for: draft, vmType: vmType) {
                    Text(tr("La primera vez, Colima pide la contraseña de administrador para instalar su red en puente: se abrirá en Terminal."))
                        .font(.system(size: 11)).foregroundStyle(Theme.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button(profile.isRunning ? tr("Aplicar y reiniciar") : tr("Aplicar y arrancar")) { apply() }
                    .buttonStyle(.colimyPrimary)
                    .disabled(draft.normalized == saved.normalized || store.colimaAction != nil)
                Button(tr("Cancelar")) { editing = false; draft = saved }
                    .buttonStyle(.colimySecondary)
            }
        }
    }

    /// Host interfaces, plus the configured one if it isn't present right now.
    private var interfaceOptions: [HostInterface] {
        if interfaces.contains(where: { $0.name == draft.interface }) { return interfaces }
        return [HostInterface(name: draft.interface, displayName: draft.interface)] + interfaces
    }

    private func interfaceLabel(_ name: String) -> String {
        guard let item = interfaces.first(where: { $0.name == name }) else { return name }
        return "\(item.displayName) (\(item.name))"
    }

    private func summary(_ network: ColimaNetwork) -> String {
        let net = network.normalized
        if net.mode == .bridged { return tr("Puente con %@: la VM tiene una IP de tu red local.", interfaceLabel(net.interface)) }
        if net.address { return tr("Compartida, con IP propia accesible desde el Mac.") }
        return tr("Compartida (NAT): los contenedores salen a tu red a través del Mac.")
    }

    private func load() {
        let config = Colima.configuration(profile: profile.name)
        saved = config.network
        vmType = config.vmType
        if !editing { draft = saved }
    }

    private func startEditing() {
        load()
        interfaces = HostInterface.all()
        draft = saved
        editing = true
    }

    private func apply() {
        let network = draft.normalized
        if profile.isRunning {
            let running = selected ? store.runningCount : 0
            let message = running > 0
                ? tr("Colima se parará y volverá a arrancar con la nueva red. Se pararán los %d contenedores en marcha; los que tengan política de reinicio volverán a arrancar.", running)
                : tr("Colima se parará y volverá a arrancar con la nueva red.")
            guard confirm(tr("¿Reiniciar Colima?"), message, button: tr("Aplicar y reiniciar")) else { return }
        }
        editing = false
        if Colima.needsSudoSetup(for: network, vmType: vmType) {
            openInTerminal(network)
        } else {
            Task { await store.applyNetwork(network, profile: profile) }
        }
    }

    /// The first bridged start asks for the admin password, so it runs in a terminal.
    private func openInTerminal(_ network: ColimaNetwork) {
        guard let colima = ExternalTool.colima.url?.path else { return }
        do {
            try Colima.saveNetwork(network, profile: profile.name)
        } catch {
            store.reportError(tr("No se pudo aplicar la configuración de red"), error)
            return
        }
        let start = [colima, profile.isRunning ? "restart" : "start", "-p", profile.name]
        let script = start.map(TerminalLauncher.quote).joined(separator: " ")
            + "; echo; read -s -k " + TerminalLauncher.quote("?" + tr("Pulsa una tecla para cerrar."))
        TerminalLauncher.open(title: "colima \(profile.name)", host: nil, command: ["/bin/zsh", "-c", script])
        store.refreshSoon(delay: 5)
    }
}
