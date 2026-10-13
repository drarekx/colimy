import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private let store = DockerStore.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        Localizer.shared.$choice
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.setupMainMenu() }
            .store(in: &cancellables)
        TerminalLauncher.removeOldScripts()
        setupStatusItem()
        store.start()
        Updater.shared.start()

        // Keep the menu bar icon in sync with the engine.
        store.$dockerHost.combineLatest(store.$colimaAction)
            .receive(on: RunLoop.main)
            .sink { [weak self] host, action in self?.updateStatusIcon(running: host != nil, busy: action != nil) }
            .store(in: &cancellables)

        #if DEBUG
        // Development: `Colimy --snapshot <png> [--section stacks|containers|colima|settings] [--select <container>]`
        // saves an image of the window (screen recording isn't needed for our own views).
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count {
            Snapshot.run(path: args[index + 1], arguments: args, show: showWindow)
            return
        }
        #endif

        // First launch: show the window so the app is discoverable.
        if !UserDefaults.standard.bool(forKey: "launchedBefore") {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            showWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    // MARK: - Main menu

    /// Accessory apps show no menu bar, but text fields still need an Edit menu
    /// for ⌘C / ⌘V / ⌘X / ⌘A / ⌘Z to reach them.
    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: tr("Cerrar ventana"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: tr("Salir de Colimy"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: tr("Edición"))
        edit.addItem(withTitle: tr("Deshacer"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: tr("Rehacer"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: tr("Cortar"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: tr("Copiar"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: tr("Pegar"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: tr("Seleccionar todo"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(withTitle: tr("Buscar"), action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
            .tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    // MARK: - Status bar menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon(running: false, busy: false)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func updateStatusIcon(running: Bool, busy: Bool) {
        let symbol = busy ? "shippingbox.and.arrow.backward" : (running ? "shippingbox.fill" : "shippingbox")
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Colimy")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = !running && !busy
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu == statusItem.menu else { return }
        store.refreshSoon(delay: 0)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu == statusItem.menu else { return }
        menu.removeAllItems()

        // Colima
        let profile = store.profile
        let header: String
        if let action = store.colimaAction {
            header = action.title
        } else if let profile {
            header = profile.isRunning ? tr("Colima en marcha (%@)", profile.name) : tr("Colima parado (%@)", profile.name)
        } else if !store.missingTools.isEmpty {
            header = tr("Falta instalar: %@", store.missingTools.map(\.rawValue).joined(separator: ", "))
        } else {
            header = tr("Colima no tiene ningún perfil")
        }
        let headerItem = menu.addItem(withTitle: header, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        headerItem.image = dot(store.isRunning ? .systemGreen : .tertiaryLabelColor)

        if store.missingTools.isEmpty && store.colimaAction == nil {
            if store.isRunning {
                add(menu, tr("Parar Colima"), symbol: "stop.fill") { [weak self] in self?.stopColima() }
                add(menu, tr("Reiniciar Colima"), symbol: "arrow.clockwise") { [weak self] in
                    Task { await self?.store.colima(.restart) }
                }
            } else {
                add(menu, tr("Arrancar Colima"), symbol: "play.fill") { [weak self] in
                    Task { await self?.store.colima(.start) }
                }
            }
        }

        // Stacks and loose containers
        if store.isRunning {
            menu.addItem(.separator())
            let stacks = store.stacks.filter { Settings.shared.showStopped || $0.runningCount > 0 }
            if stacks.isEmpty && store.standalone.isEmpty {
                menu.addItem(withTitle: tr("No hay contenedores"), action: nil, keyEquivalent: "").isEnabled = false
            }
            if !stacks.isEmpty {
                menu.addItem(withTitle: tr("Stacks"), action: nil, keyEquivalent: "").isEnabled = false
                for stack in stacks { menu.addItem(stackItem(stack)) }
            }
            let loose = store.standalone.filter { Settings.shared.showStopped || $0.isRunning }
            if !loose.isEmpty {
                menu.addItem(withTitle: tr("Contenedores sueltos"), action: nil, keyEquivalent: "").isEnabled = false
                for container in loose { menu.addItem(containerItem(container, title: container.name)) }
            }
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: tr("Abrir Colimy…"), action: #selector(showWindow), keyEquivalent: "o").target = self
        let login = menu.addItem(withTitle: tr("Abrir al iniciar sesión"), action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off

        menu.addItem(.separator())
        let updating = Updater.shared.state != .idle
        let update = menu.addItem(withTitle: updating ? tr("Actualizando…") : tr("Buscar actualizaciones…"),
                                  action: updating ? nil : #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        let coffee = menu.addItem(withTitle: tr("Invítame a un café…"), action: #selector(openBuyMeACoffee), keyEquivalent: "")
        coffee.target = self
        coffee.image = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: nil)
        let version = menu.addItem(withTitle: "Colimy \(Updater.currentVersion)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(withTitle: tr("Salir de Colimy"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func stackItem(_ stack: Stack) -> NSMenuItem {
        let item = NSMenuItem(title: "\(stack.name)  \(stack.runningCount)/\(stack.containers.count)", action: nil, keyEquivalent: "")
        item.image = dot(stack.status == .running ? .systemGreen : stack.status == .partial ? .systemOrange : .tertiaryLabelColor)
        let sub = NSMenu()
        if store.isBusy(stack) {
            sub.addItem(withTitle: tr("Trabajando…"), action: nil, keyEquivalent: "").isEnabled = false
        } else {
            if stack.status != .running {
                add(sub, tr("Arrancar"), symbol: "play.fill") { [weak self] in Task { await self?.store.perform(.up, on: stack) } }
            }
            if stack.status != .stopped {
                add(sub, tr("Parar"), symbol: "stop.fill") { [weak self] in Task { await self?.store.perform(.stop, on: stack) } }
                add(sub, tr("Reiniciar"), symbol: "arrow.clockwise") { [weak self] in Task { await self?.store.perform(.restart, on: stack) } }
            }
            add(sub, tr("Ver logs…"), symbol: "text.alignleft") { [weak self] in
                self?.showWindow()
                MainSelection.shared.select(.stack(stack.name), logs: true)
            }
            if !stack.workingDir.isEmpty {
                add(sub, tr("Mostrar en Finder"), symbol: "folder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: stack.workingDir)
                }
            }
        }
        sub.addItem(.separator())
        for container in stack.containers {
            sub.addItem(containerItem(container, title: container.displayName))
        }
        item.submenu = sub
        return item
    }

    private func containerItem(_ container: Container, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = dot(container.isRunning ? .systemGreen : container.isPaused ? .systemOrange : .tertiaryLabelColor)
        let sub = NSMenu()
        if store.isBusy(container) {
            sub.addItem(withTitle: tr("Trabajando…"), action: nil, keyEquivalent: "").isEnabled = false
        } else if container.isRunning {
            add(sub, tr("Abrir terminal"), symbol: "terminal") { TerminalLauncher.openShell(in: container) }
            for port in container.publishedPorts {
                if let url = port.url {
                    add(sub, tr("Abrir localhost:%@", port.hostPort), symbol: "safari") { NSWorkspace.shared.open(url) }
                }
            }
            sub.addItem(.separator())
            add(sub, tr("Parar"), symbol: "stop.fill") { [weak self] in Task { await self?.store.perform(.stop, on: [container]) } }
            add(sub, tr("Reiniciar"), symbol: "arrow.clockwise") { [weak self] in Task { await self?.store.perform(.restart, on: [container]) } }
        } else if container.isPaused {
            add(sub, tr("Reanudar"), symbol: "play.fill") { [weak self] in Task { await self?.store.perform(.unpause, on: [container]) } }
        } else {
            add(sub, tr("Arrancar"), symbol: "play.fill") { [weak self] in Task { await self?.store.perform(.start, on: [container]) } }
        }
        add(sub, tr("Ver logs…"), symbol: "text.alignleft") { [weak self] in
            self?.showWindow()
            MainSelection.shared.select(.container(container.id), logs: true)
        }
        item.submenu = sub
        return item
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, symbol: String, action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: action)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        menu.addItem(item)
        return item
    }

    private func dot(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }

    private func stopColima() {
        let running = store.runningCount
        if running > 0, !confirm(tr("¿Parar Colima?"),
                                 tr("Se pararán los %d contenedores en marcha.", running),
                                 button: tr("Parar Colima")) { return }
        Task { await store.colima(.stop) }
    }

    // MARK: - Window

    @objc func showWindow() {
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1320, height: 800),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.title = "Colimy"
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 980, height: 600)
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(red: 0x12 / 255, green: 0x12 / 255, blue: 0x14 / 255, alpha: 1)
            window.titlebarAppearsTransparent = true
            window.delegate = self
            let hosting = NSHostingController(rootView: MainView())
            hosting.sizingOptions = []
            window.contentViewController = hosting
            // Restore the last frame before enabling autosave, which would store the initial one.
            if !window.setFrameUsingName("ColimyMain") {
                window.setContentSize(NSSize(width: 1320, height: 800))
                window.center()
            }
            window.setFrameAutosaveName("ColimyMain")
            mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
        store.setActive(true)
    }

    func windowWillClose(_ notification: Notification) {
        store.setActive(false)
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        store.setActive(window.isVisible && window.occlusionState.contains(.visible))
    }

    @objc private func openBuyMeACoffee() {
        NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/drarek")!)
    }

    @objc private func checkForUpdates() {
        Task { await Updater.shared.check(userInitiated: true) }
    }

    @objc private func toggleLogin() { LoginItem.setEnabled(!LoginItem.isEnabled) }
}

/// Menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func run() { handler() }
}
