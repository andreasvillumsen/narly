import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    private let preferences: DestinationPreferences
    private var sizeEditor: PickerSizeWindowController?
    private let defaultBrowser = DefaultBrowserSettings()
    private let loginItem = LoginItemSettings()
    private let introduction = IntroductionState()
    private let navigation = SettingsNavigation()
    var selectedPane: SettingsPane { navigation.selection }
    public init(preferences: DestinationPreferences) {
        self.preferences = preferences
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = L10n.format("%@ Settings", AppInformation.name)
        window.contentMinSize = NSSize(width: 480, height: 460)
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .canJoinAllApplications]
        window.center()
        super.init(window: window)
        window.contentView = NSHostingView(rootView: SettingsView(preferences: preferences, defaultBrowser: defaultBrowser,
                                                                loginItem: loginItem, introduction: introduction, navigation: navigation,
                                                                addApplication: { [weak window] in
            guard let window else { return }
            Self.chooseApplication(in: window, preferences: preferences)
        }, customizeSize: { [weak self] in self?.customizeSize() }))
        let toolbar = NSToolbar(identifier: "narly.settings")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        toolbar.selectedItemIdentifier = navigation.selection.toolbarIdentifier
    }

    private func customizeSize() {
        if sizeEditor?.window?.isVisible != true {
            sizeEditor = PickerSizeWindowController(preferences: preferences)
        }
        sizeEditor?.present(relativeTo: window)
    }

    required init?(coder: NSCoder) { nil }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .space] + SettingsPane.allCases.map(\.toolbarIdentifier)
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, SettingsPane.general.toolbarIdentifier, .space, .space,
         SettingsPane.apps.toolbarIdentifier, .space, .space, SettingsPane.about.toolbarIdentifier, .flexibleSpace]
    }

    public func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map(\.toolbarIdentifier)
    }

    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                        willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let pane = SettingsPane.allCases.first(where: { $0.toolbarIdentifier == identifier }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = pane.title
        let button = SettingsToolbarButton(pane: pane)
        button.updateSelection(navigation.selection == pane)
        button.target = self
        button.action = #selector(selectToolbarPane(_:))
        item.view = button
        let menuItem = NSMenuItem(title: pane.title, action: #selector(selectToolbarPane(_:)), keyEquivalent: "")
        menuItem.identifier = .init(identifier.rawValue)
        menuItem.target = self
        item.menuFormRepresentation = menuItem
        return item
    }

    @objc private func selectToolbarPane(_ sender: Any) {
        let identifier: String?
        switch sender {
        case let button as SettingsToolbarButton: identifier = button.pane.toolbarIdentifier.rawValue
        case let menuItem as NSMenuItem: identifier = menuItem.identifier?.rawValue
        default: return
        }
        guard let pane = SettingsPane.allCases.first(where: { $0.toolbarIdentifier.rawValue == identifier }) else { return }
        selectPane(pane)
    }

    func selectPane(_ pane: SettingsPane) {
        window?.makeFirstResponder(nil)
        navigation.selection = pane
        window?.toolbar?.selectedItemIdentifier = pane.toolbarIdentifier
        for item in window?.toolbar?.items ?? [] {
            guard let button = item.view as? SettingsToolbarButton else { continue }
            button.updateSelection(button.pane == pane)
        }
    }

    private static func chooseApplication(in window: NSWindow, preferences: DestinationPreferences) {
        guard window.attachedSheet == nil else { return }
        let picker = NSOpenPanel()
        picker.title = L10n.text("Add app")
        picker.prompt = L10n.text("Add")
        picker.message = L10n.text("Choose an installed app that can open web links.")
        picker.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        picker.allowedContentTypes = [.applicationBundle]
        picker.canChooseFiles = true
        picker.canChooseDirectories = false
        picker.treatsFilePackagesAsDirectories = false
        picker.allowsMultipleSelection = false
        picker.beginSheetModal(for: window) { [weak window] response in
            guard response == .OK, let url = picker.url else { return }
            do {
                try preferences.addApplication(at: url)
            } catch {
                guard let window else { return }
                let alert = NSAlert()
                alert.messageText = L10n.text("Couldn’t add the app")
                alert.informativeText = error.localizedDescription
                alert.beginSheetModal(for: window)
            }
        }
    }

    public func present(showIntroduction: Bool = false) {
        preferences.refreshInstalledApplications()
        if showIntroduction { introduction.show() }
        if introduction.isVisible { selectPane(.general) }
        defaultBrowser.refresh()
        loginItem.refresh()
        guard let window else { return }
        // Capture the menu click's screen before activation can change focus/Space.
        let screens = NSScreen.screens
        if let index = PickerPlacement.screenIndex(pointer: NSEvent.mouseLocation, frames: screens.map(\.frame)) {
            let screen = screens[index]
            if !window.isVisible || !window.isOnActiveSpace || window.screen !== screen {
                window.setFrame(SettingsPlacement.frame(size: window.frame.size, visibleFrame: screen.visibleFrame), display: false)
            }
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        // Move/order the window on the invoking Space FIRST. Activating the app
        // before this lets macOS return to the Space that last owned Settings.
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum SettingsPlacement {
    static func frame(size: CGSize, visibleFrame: CGRect) -> CGRect {
        let width = min(size.width, visibleFrame.width)
        let height = min(size.height, visibleFrame.height)
        return CGRect(x: visibleFrame.midX - width / 2, y: visibleFrame.midY - height / 2,
                      width: width, height: height)
    }
}
