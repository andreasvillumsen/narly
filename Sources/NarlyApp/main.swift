import AppKit
import PickerKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private lazy var diagnostics: Diagnostics = {
        let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/\(AppInformation.name)", isDirectory: true)
        return Diagnostics(directory: directory)
    }()
    private lazy var preferences = DestinationPreferences(destinations: DestinationCatalog.supportedDestinations())
    private lazy var session = PickerSession(destinations: preferences.visibleDestinations,
                                             opener: WorkspaceDestinationOpener(),
                                             preferredBrowserID: preferences.preferredID, displayMode: preferences.pickerMode,
                                             customPickerSize: preferences.customPickerSize, layout: preferences.pickerLayout,
                                             appShortcuts: preferences.appShortcuts)
    private var settings: SettingsWindowController?
    private var isLoginLaunch = false
    private var controller: PickerPanelController?
    private var statusItem: NSStatusItem?
    private var observations: [NSObjectProtocol] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        isLoginLaunch = LaunchPresentation.isLoginLaunch(event: NSAppleEventManager.shared().currentAppleEvent)
        diagnostics.record("will-finish-launching")
        observe(NSApplication.didBecomeActiveNotification, center: .default, event: "app-active")
        observe(NSApplication.didResignActiveNotification, center: .default, event: "app-inactive")
        observe(NSWorkspace.activeSpaceDidChangeNotification, center: NSWorkspace.shared.notificationCenter,
                event: "space-changed")
        observe(NSWorkspace.didActivateApplicationNotification, center: NSWorkspace.shared.notificationCenter,
                event: "workspace-app-activated")
        observe(NSWorkspace.willSleepNotification, center: NSWorkspace.shared.notificationCenter, event: "will-sleep")
        observe(NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter, event: "did-wake")
        observations.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.diagnostics.record("screens-changed", panel: self.controller?.panel)
                self.controller?.repositionIfVisible()
            }
        })
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = PickerPanelController(session: session, diagnostics: diagnostics)
        session.trace = { [weak self] event, request in
            guard let self else { return }
            self.diagnostics.record(event, panel: self.controller?.panel, request: request)
        }
        preferences.onChange = { [weak self] in
            guard let self else { return }
            self.statusItem?.isVisible = self.preferences.showsMenuBarIcon
            self.session.layout = self.preferences.pickerLayout
            self.session.displayMode = self.preferences.pickerMode
            self.session.customPickerSize = self.preferences.customPickerSize
            self.session.appShortcuts = self.preferences.appShortcuts
            self.session.refreshDestinations(self.preferences.visibleDestinations,
                                         preferredBrowserID: self.preferences.preferredID)
            self.controller?.repositionIfVisible()
        }
        setupMenu()
        session.onOpenFailure = { [weak self] in self?.preferences.refreshInstalledApplications() }
        diagnostics.record("ready", panel: controller?.panel)
        session.ready()
        let isDefaultLaunch = (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? NSNumber)?.boolValue ?? false
        if LaunchPresentation.shouldShowSettings(isDefaultLaunch: isDefaultLaunch, hasPendingLinks: session.hasPendingPresentation,
                                                  isLoginLaunch: isLoginLaunch || LaunchPresentation.isLoginLaunch(event: NSAppleEventManager.shared().currentAppleEvent)) {
            showSettings()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let optionHeld = NSEvent.modifierFlags.contains(.option)
        preferences.refreshInstalledApplications()
        diagnostics.record("url-received", panel: controller?.panel)
        // A caller's intent (human click vs automatic action) is not guessed.
        // Explicitly targeted apps and non-HTTP schemes remain handled by macOS.
        session.appLinkBehaviors = preferences.appLinkBehaviors
        session.routingDestinations = preferences.destinations
        session.receive(urls, optionHeld: optionHeld)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        diagnostics.record("app-reopen", panel: controller?.panel)
        // Explicitly reopening the app provides a way back to Settings even
        // without a menu bar icon. Never displace a pending link picker.
        if LaunchPresentation.shouldShowSettingsOnReopen(
            event: NSAppleEventManager.shared().currentAppleEvent,
            hasPendingLinks: session.hasPendingPresentation
        ) {
            showSettings()
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.removeMouseMonitors()
        diagnostics.record("terminating", panel: controller?.panel)
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter, event: String) {
        observations.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.diagnostics.record(event, panel: self.controller?.panel, request: self.session.current?.id)
            }
        })
    }

    private func setupMenu() {
        let item = NSStatusBar.system.statusItem(withLength: AppInformation.isDevelopment ? NSStatusItem.variableLength : NSStatusItem.squareLength)
        let image = NarlyBrand.image(size: 22, template: true)
        item.button?.image = image
        item.button?.toolTip = AppInformation.name
        if AppInformation.isDevelopment { item.button?.title = " Dev" }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        add(L10n.text("Settings…"), #selector(showSettings), to: menu)
        menu.addItem(.separator())
        add(L10n.text("Reopen dismissed links"), #selector(restore), to: menu)
        menu.addItem(.separator())
        add(L10n.text("Quit Narly") + (AppInformation.isDevelopment ? " Dev" : ""), #selector(quit), to: menu)
        item.menu = menu
        item.isVisible = preferences.showsMenuBarIcon
        statusItem = item
    }

    private func add(_ title: String, _ action: Selector, to menu: NSMenu) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.first(where: { $0.action == #selector(restore) })?.isEnabled =
            !session.queue.dismissed.isEmpty && session.queue.pending.isEmpty && !session.isOpening
    }

    @objc private func restore() { session.restore() }
    @objc private func showSettings() {
        session.dismiss()
        if settings == nil { settings = SettingsWindowController(preferences: preferences) }
        settings?.present()
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
