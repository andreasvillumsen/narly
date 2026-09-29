import Foundation
import Testing
@testable import PickerKit

@Suite @MainActor struct AppReorderTests {
    @Test func dropBelowAdjacentRowMovesDownAndHiddenAppsParticipate() throws {
        let suite = "reorder-drop.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let apps = ["a", "b", "c"].map { Destination(id: $0, name: $0, applicationURL: URL(fileURLWithPath: "/\($0).app")) }
        let prefs = DestinationPreferences(destinations: apps, defaults: defaults)
        prefs.setVisible(false, id: "a")
        prefs.reorderApp("a", relativeTo: "b", after: true)
        #expect(prefs.orderedDestinations.map(\.id) == ["b", "a", "c"])
        prefs.reorderApp("a", relativeTo: "c", after: true)
        #expect(prefs.orderedDestinations.map(\.id) == ["b", "c", "a"])
        prefs.reorderApp("a", relativeTo: "b", after: false)
        #expect(prefs.orderedDestinations.map(\.id) == ["a", "b", "c"])
        prefs.reorderApp("b", relativeTo: "b", after: true)
        #expect(prefs.orderedDestinations.map(\.id) == ["a", "b", "c"])
        let restored = DestinationPreferences(destinations: apps, defaults: defaults)
        #expect(restored.orderedDestinations.map(\.id) == ["a", "b", "c"])
    }
}
