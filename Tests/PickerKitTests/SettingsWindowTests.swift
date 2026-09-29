import AppKit
import Testing
@testable import PickerKit

@Suite @MainActor struct SettingsWindowTests {
    @Test func nativeToolbarNavigatesAndIntroductionReturnsToGeneral() throws {
        _ = NSApplication.shared
        let suite = "Narly.settings-navigation-tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DestinationPreferences(destinations: [], defaults: defaults, catalogProvider: { [] })
        let controller = SettingsWindowController(preferences: preferences)
        let window = try #require(controller.window)
        defer { window.close() }
        let toolbar = try #require(window.toolbar)
        #expect(window.toolbarStyle == .preference)
        #expect(toolbar.displayMode == .iconOnly)
        #expect(toolbar.selectedItemIdentifier == SettingsPane.general.toolbarIdentifier)
        #expect(controller.toolbarSelectableItemIdentifiers(toolbar) == SettingsPane.allCases.map(\.toolbarIdentifier))
        #expect(!toolbar.items.contains(where: { $0.itemIdentifier.rawValue == "narly.rescan" }))
        for pane in [SettingsPane.apps, .about, .general] {
            let item = try #require(toolbar.items.first { $0.itemIdentifier == pane.toolbarIdentifier })
            let button = try #require(item.view as? SettingsToolbarButton)
            button.performClick(nil)
            #expect(controller.selectedPane == pane)
            #expect(button.state == .on)
            controller.selectPane(.general)
            let menuItem = try #require(item.menuFormRepresentation)
            let action = try #require(menuItem.action)
            #expect(NSApp.sendAction(action, to: menuItem.target, from: menuItem))
            #expect(controller.selectedPane == pane)
            #expect(toolbar.selectedItemIdentifier == pane.toolbarIdentifier)
        }
        controller.selectPane(.apps)
        window.close()
        #expect(controller.selectedPane == .apps)
        controller.window = nil
        controller.present(showIntroduction: true)
        #expect(controller.selectedPane == .general)
    }

    @Test func presentingSettingsRefreshesInstallationsWithoutChangingChoices() throws {
        _ = NSApplication.shared
        let suite = "Narly.catalog-refresh-tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        func destination(_ id: String, installed: Bool) -> Destination {
            Destination(id: id, name: id, applicationURL: installed ? URL(fileURLWithPath: "/\(id).app") : nil)
        }
        let original = [destination("a", installed: true), destination("b", installed: true),
                        destination("c", installed: false), destination("hidden", installed: true)]
        var catalog = original
        let preferences = DestinationPreferences(destinations: original, defaults: defaults, catalogProvider: { catalog })
        preferences.move("b", by: -1)
        preferences.setPreferred("b")
        preferences.setVisible(false, id: "hidden")
        preferences.setAppShortcut("x", for: "b")
        let controller = SettingsWindowController(preferences: preferences)
        let window = try #require(controller.window)
        defer { window.close() }
        controller.window = nil // Run the presentation refresh without showing UI.
        catalog = [destination("a", installed: true), destination("b", installed: false),
                   destination("c", installed: true), destination("hidden", installed: true)]
        controller.present()
        #expect(preferences.visibleDestinations.map(\.id) == ["a", "c"])
        #expect(preferences.preferredID == "b")
        #expect(preferences.appShortcuts["b"] == "x")
        #expect(!preferences.isVisible("hidden"))
        catalog = original
        controller.present()
        #expect(preferences.visibleDestinations.map(\.id) == ["b", "a"])
    }

    @Test func settingsMoveToInvokingSpaceAndCanJoinAnotherAppsFullscreen() throws {
        _ = NSApplication.shared
        let suite = "Narly.settings-window-tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = SettingsWindowController(preferences: DestinationPreferences(destinations: [], defaults: defaults))
        let window = try #require(controller.window)
        defer { window.close() }
        #expect(window.collectionBehavior.contains(.moveToActiveSpace))
        #expect(window.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(window.collectionBehavior.contains(.canJoinAllApplications))
        #expect(!window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(!window.isVisible)
    }

    @Test(arguments: [CGRect(x: -1920, y: -200, width: 1920, height: 1080),
                      CGRect(x: 0, y: 24, width: 1440, height: 876),
                      CGRect(x: 1920, y: 50, width: 500, height: 500)])
    func centersWithinTheInvokingScreensUsableArea(_ visibleFrame: CGRect) {
        let frame = SettingsPlacement.frame(size: CGSize(width: 540, height: 660), visibleFrame: visibleFrame)
        #expect(visibleFrame.contains(frame))
        #expect(frame.midX == visibleFrame.midX)
        #expect(frame.midY == visibleFrame.midY)
    }
}
