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
