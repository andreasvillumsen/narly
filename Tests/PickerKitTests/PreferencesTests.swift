import Foundation
import Testing
@testable import PickerKit

@Suite @MainActor struct PreferencesTests {
    @Test func menuBarVisibilityPersistsWithoutChangingBrowserChoices() throws {
        let suite = "narly-menu-bar-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DestinationPreferences(destinations: destinations, defaults: defaults)
        #expect(preferences.showsMenuBarIcon)
        preferences.move("b", by: -1)
        preferences.setPreferred("b")
        preferences.setPickerMode(.compact)
        var changes = 0
        preferences.onChange = { changes += 1 }
        preferences.setShowsMenuBarIcon(false)
        preferences.setShowsMenuBarIcon(false)
        #expect(changes == 1)
        let restored = DestinationPreferences(destinations: destinations, defaults: defaults)
        #expect(!restored.showsMenuBarIcon)
        #expect(restored.visibleDestinations.map(\.id) == ["b", "a"])
        #expect(restored.preferredID == "b")
        #expect(restored.pickerMode == .compact)
        restored.setShowsMenuBarIcon(true)
        #expect(DestinationPreferences(destinations: destinations, defaults: defaults).showsMenuBarIcon)
    }

    private var destinations: [Destination] {
        [Destination(id: "a", name: "A", applicationURL: URL(fileURLWithPath: "/A.app")),
         Destination(id: "b", name: "B", applicationURL: URL(fileURLWithPath: "/B.app")),
         Destination(id: "c", name: "C", applicationURL: nil)]
    }

    @Test func choicesSurviveRestartAndRescan() throws {
        let suite = "narly-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DestinationPreferences(destinations: destinations, defaults: defaults)
        preferences.move("b", by: -1)
        preferences.setVisible(false, id: "c")
        preferences.setPreferred("b")
        let restored = DestinationPreferences(destinations: destinations, defaults: defaults)
        #expect(restored.visibleDestinations.map(\.id) == ["b", "a"])
        #expect(restored.preferredID == "b")
        restored.rescan(Array(destinations.reversed()))
        #expect(restored.visibleDestinations.map(\.id) == ["b", "a"])
        #expect(restored.preferredID == "b")
    }

    @Test func cannotHideLastInstalledBrowserAndHiddenPreferredIsCleared() throws {
        let suite = "narly-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DestinationPreferences(destinations: destinations, defaults: defaults)
        preferences.setPreferred("b")
        preferences.setVisible(false, id: "b")
        #expect(preferences.preferredID == nil)
        preferences.setVisible(false, id: "a")
        #expect(preferences.availableBrowsers.map(\.id) == ["a"])
        preferences.setPreferred("c")
        #expect(preferences.preferredID == nil)
    }

    @Test func corruptPreferencesFallBackToUsableDefaults() throws {
        let suite = "narly-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("broken".utf8), forKey: "narly.destinationPreferences.v1")
        let preferences = DestinationPreferences(destinations: destinations, defaults: defaults)
        #expect(preferences.visibleDestinations.map(\.id) == ["a", "b"])
        #expect(preferences.preferredID == nil)
    }
}

@Suite @MainActor struct DragReorderTests {
    private var destinations: [Destination] {
        ["a", "b", "c", "d"].map { Destination(id: $0, name: $0, applicationURL: URL(fileURLWithPath: "/\($0).app")) }
    }

    @Test func settingsMovesIncludeHiddenAppsAndSkipMissingInstallations() throws {
        let suite = "narly-settings-move-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let catalog = destinations + [Destination(id: "missing", name: "Missing", applicationURL: nil)]
        let preferences = DestinationPreferences(destinations: catalog, defaults: defaults)
        preferences.setVisible(false, id: "b")
        preferences.setPreferred("c")
        preferences.setAppShortcut("x", for: "b")
        preferences.moveSettingsApplication("b", by: 1)
        #expect(preferences.installedSettingsDestinations.map(\.id) == ["a", "c", "b", "d"])
        preferences.moveSettingsApplication("b", by: -1)
        #expect(preferences.installedSettingsDestinations.map(\.id) == ["a", "b", "c", "d"])
        preferences.moveSettingsApplication("d", by: 1)
        preferences.moveSettingsApplication("missing", by: -1)
        #expect(preferences.orderedDestinations.map(\.id) == ["a", "b", "c", "d", "missing"])
        let restored = DestinationPreferences(destinations: catalog, defaults: defaults)
        #expect(restored.installedSettingsDestinations.map(\.id) == ["a", "b", "c", "d"])
        #expect(!restored.isVisible("b"))
        #expect(restored.appShortcuts["b"] == "x")
        #expect(restored.preferredID == "c")
    }

    @Test func movesUpDownAndToEndAndPersistsFlags() throws {
        let suite = "narly-drag-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DestinationPreferences(destinations: destinations, defaults: defaults)
        preferences.setVisible(false, id: "b")
        preferences.setPreferred("c")
        preferences.reorder(["d"], before: "a")
        #expect(preferences.orderedDestinations.map(\.id) == ["d", "a", "b", "c"])
        preferences.reorder(["d"], before: "c")
        #expect(preferences.orderedDestinations.map(\.id) == ["a", "b", "d", "c"])
        preferences.reorder(["a"], before: nil)
        #expect(preferences.orderedDestinations.map(\.id) == ["b", "d", "c", "a"])
        let restored = DestinationPreferences(destinations: destinations.reversed(), defaults: defaults)
        #expect(restored.visibleDestinations.map(\.id) == ["d", "c", "a"])
        #expect(restored.preferredID == "c")
    }

    @Test func invalidAndUnchangedDropsDoNotPublishChanges() throws {
        let suite = "narly-drag-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DestinationPreferences(destinations: destinations, defaults: defaults)
        var changes = 0
        preferences.onChange = { changes += 1 }
        preferences.reorder([], before: "a")
        preferences.reorder(["unknown"], before: "a")
        preferences.reorder(["a"], before: "unknown")
        preferences.reorder(["a"], before: "a")
        preferences.reorder(["a"], before: "b")
        #expect(changes == 0)
        #expect(preferences.orderedDestinations.map(\.id) == ["a", "b", "c", "d"])
    }

    @Test func groupedDropPreservesRelativeOrderAndDrivesPickerOrder() throws {
        let suite = "narly-drag-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DestinationPreferences(destinations: destinations, defaults: defaults)
        preferences.reorder(["d", "b", "b"], before: "a")
        let session = PickerSession(destinations: preferences.visibleDestinations, opener: WorkspaceDestinationOpener())
        session.receive([try #require(URL(string: "https://example.com"))])
        #expect(session.destinations.map(\.id) == ["b", "d", "a", "c"])
        #expect(session.destinations[session.selectedIndex].id == "b")
    }
}
