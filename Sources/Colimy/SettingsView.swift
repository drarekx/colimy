import SwiftUI

struct SettingsPane: View {
    @ObservedObject private var localizer = Localizer.shared
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var store = DockerStore.shared
    @ObservedObject private var updater = Updater.shared
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var autoUpdate = Updater.shared.autoCheck

    private let columns = [GridItem(.adaptive(minimum: 420), spacing: 20, alignment: .top)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(tr("Ajustes")).font(.system(size: 20, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            Rectangle().fill(Theme.line).frame(height: 1)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    generalCard
                    languageCard
                    terminalCard
                    logsCard
                    updatesCard
                    toolsCard
                }
                .padding(24)
                .frame(maxWidth: 1180)
            }
        }
    }

    private var generalCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tr("General")).font(.system(size: 14, weight: .semibold)).padding(.bottom, 8)
            SwitchRow(title: tr("Abrir al iniciar sesión"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, value in LoginItem.setEnabled(value) }
            divider
            SwitchRow(title: tr("Mostrar stacks y contenedores parados"), isOn: $settings.showStopped)
            divider
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Actualizar la lista cada"))
                SegmentedControl(options: [2, 5, 10, 30].map { ("\($0) s", $0) },
                                 selection: $settings.refreshInterval, expand: true)
                Text(tr("Con la ventana abierta. Los cambios de los contenedores se ven al momento igualmente."))
                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
            }
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .colimyCard()
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Idioma")).font(.system(size: 14, weight: .semibold))
            SegmentedControl(options: AppLanguage.allCases.map { ($0.nativeName, $0) },
                             selection: $localizer.choice, expand: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .colimyCard()
    }

    private var terminalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Terminal")).font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Abrir las terminales en"))
                SegmentedControl(options: TerminalApp.allCases.filter { $0.isInstalled || $0 == settings.terminalApp }
                                    .map { ($0.title, $0) },
                                 selection: $settings.terminalApp, expand: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Shell dentro del contenedor"))
                SegmentedControl(options: ContainerShell.allCases.map { ($0.title, $0) },
                                 selection: $settings.shell, expand: true)
                Text(tr("Automático usa bash si el contenedor lo tiene y, si no, sh."))
                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .colimyCard()
    }

    private var logsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Logs")).font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Líneas anteriores al abrir"))
                SegmentedControl(options: [100, 500, 2000].map { ("\($0)", $0) },
                                 selection: $settings.logTail, expand: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .colimyCard()
    }

    private var updatesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tr("Actualizaciones")).font(.system(size: 14, weight: .semibold)).padding(.bottom, 8)
            SwitchRow(title: tr("Buscar actualizaciones automáticamente"), isOn: $autoUpdate)
                .onChange(of: autoUpdate) { _, value in updater.autoCheck = value }
            divider
            HStack {
                Text(tr("Versión ") + Updater.currentVersion).foregroundStyle(Theme.text2)
                Spacer()
                Button(updater.state == .idle ? tr("Buscar ahora") : tr("Actualizando…")) {
                    Task { await updater.check(userInitiated: true) }
                }
                .buttonStyle(.colimySecondary)
                .disabled(updater.state != .idle)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .colimyCard()
    }

    private var toolsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Herramientas")).font(.system(size: 14, weight: .semibold))
            ForEach(ExternalTool.allCases, id: \.self) { tool in
                HStack {
                    Text(tool.rawValue).monospacedText()
                    Spacer()
                    if let url = tool.url {
                        Text(url.path).font(.system(size: 11)).foregroundStyle(Theme.text3)
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok)
                    } else {
                        Text(tr("No instalado")).foregroundStyle(Theme.warn)
                    }
                }
            }
            Text(tr("Instálalas con: brew install colima docker docker-compose"))
                .font(.system(size: 11)).foregroundStyle(Theme.text3).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .colimyCard()
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(height: 1)
    }
}
