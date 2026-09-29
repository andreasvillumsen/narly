import Foundation
import Testing
@testable import PickerKit

@Suite @MainActor struct ManualApplicationTests {
    private func withPreferences(_ body: (DestinationPreferences, UserDefaults, URL) throws -> Void) throws {
        let suite = "narly-manual-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let preferences = DestinationPreferences(destinations: [Destination(id: "base", name: "Base", applicationURL: root)], defaults: defaults)
        try body(preferences, defaults, root)
    }

    private func application(in root: URL, name: String, id: String) throws -> URL {
        let url = root.appendingPathComponent("\(name).app")
        let contents = url.appendingPathComponent("Contents")
        let executable = contents.appendingPathComponent("MacOS/Fixture")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let plist = ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundleExecutable": "Fixture", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        return url
    }

    @Test func manualAppPersistsWithOrderVisibilityAndPreferredChoice() throws {
        try withPreferences { preferences, defaults, root in
            let id = "test.narly.\(UUID())"
            let app = try application(in: root, name: "Custom", id: id)
            try preferences.addApplication(at: app)
            preferences.reorder([id], before: "base")
            preferences.setPreferred(id)
            let restored = DestinationPreferences(destinations: preferences.destinations.filter { $0.id == "base" }, defaults: defaults)
            restored.rescan(restored.destinations.filter { $0.id == "base" })
            #expect(restored.orderedDestinations.map(\.id) == [id, "base"])
            #expect(restored.preferredID == id)
            #expect(restored.destinations.last?.applicationURL?.path == app.path)
            restored.setVisible(false, id: id)
            let hidden = DestinationPreferences(destinations: [], defaults: defaults)
            #expect(!hidden.isVisible(id))
            #expect(hidden.preferredID == nil)
        }
    }

    @Test func duplicateUpdatesPathWithoutChangingOrder() throws {
        try withPreferences { preferences, _, root in
            let id = "test.narly.\(UUID())"
            try preferences.addApplication(at: application(in: root, name: "First", id: id))
            try preferences.addApplication(at: application(in: root, name: "Second", id: "test.narly.\(UUID())"))
            let order = preferences.orderedDestinations.map(\.id)
            let replacement = try application(in: root, name: "Replacement", id: id)
            try preferences.addApplication(at: replacement)
            #expect(preferences.orderedDestinations.map(\.id) == order)
            #expect(preferences.destinations.first { $0.id == id }?.applicationURL?.path == replacement.path)
        }
    }

    @Test func knownNativeAppRetainsLinkFiltering() throws {
        try withPreferences { preferences, _, root in
            preferences.rescan([Destination(id: "com.linear", name: "Linear", applicationURL: nil, appLink: .linear)])
            try preferences.addApplication(at: application(in: root, name: "Linear", id: "com.linear"))
            #expect(preferences.destinations.count == 1)
            #expect(preferences.destinations.first?.appLink == .linear)
            #expect(preferences.destinations.first?.applicationURL != nil)
            #expect(!preferences.isManuallyAdded("com.linear"))
        }
    }

    @Test func bothNarlyIdentitiesAreRejectedBeforeDispatch() async {
        for id in ["app.narlymac", "app.narlymac.dev"] {
            let destination = Destination(id: id, name: "Narly", applicationURL: nil)
            do {
                try await WorkspaceDestinationOpener().open(URL(string: "https://example.com")!, in: destination)
                Issue.record("Narly must never dispatch a link to either of its own identities")
            } catch DestinationOpenError.recursiveDestination {
                // Identity is rejected before checking installation or contacting Launch Services.
            } catch {
                Issue.record("Expected recursiveDestination, received \(error)")
            }
        }
    }

    @Test func invalidAndRecursiveAppsDoNotChangePreferences() throws {
        try withPreferences { preferences, _, root in
            for id in ["app.narlymac", "app.narlymac.dev", "com.browserosaurus", "xyz.alexstrnik.Browserino"] {
                let app = try application(in: root, name: id, id: id)
                #expect(throws: ManualApplicationError.self) { try preferences.addApplication(at: app) }
            }
            #expect(throws: ManualApplicationError.self) { try preferences.addApplication(at: root) }
            #expect(throws: ManualApplicationError.self) { try preferences.addApplication(at: URL(string: "https://example.com/App.app")!) }
            #expect(preferences.destinations.map(\.id) == ["base"])
        }
    }

    @Test func missingAppCanBeReplacedAndRemovedWithoutDeletingBundle() throws {
        try withPreferences { preferences, defaults, root in
            let id = "test.narly.\(UUID())"
            let app = try application(in: root, name: "Original", id: id)
            try preferences.addApplication(at: app)
            try FileManager.default.removeItem(at: app)
            preferences.rescan(preferences.destinations.filter { $0.id == "base" })
            #expect(preferences.destinations.first { $0.id == id }?.applicationURL == nil)
            let replacement = try application(in: root, name: "Replacement", id: id)
            try preferences.addApplication(at: replacement)
            preferences.setPreferred(id)
            preferences.removeApplication(id)
            #expect(preferences.preferredID == nil)
            #expect(FileManager.default.fileExists(atPath: replacement.path))
            let restored = DestinationPreferences(destinations: [], defaults: defaults)
            #expect(restored.destinations.isEmpty)
        }
    }

    @Test func pointerAndKeyboardUseSameSelectionAndIgnoreUnavailableApps() throws {
        let session = PickerSession(destinations: [Destination(id: "a", name: "A", applicationURL: URL(fileURLWithPath: "/A.app")),
                                              Destination(id: "b", name: "B", applicationURL: nil),
                                              Destination(id: "c", name: "C", applicationURL: URL(fileURLWithPath: "/C.app"))], opener: WorkspaceDestinationOpener())
        session.receive([try #require(URL(string: "https://example.com/"))])
        session.highlight(index: 2)
        #expect(session.selectedIndex == 2)
        session.highlight(index: 1)
        session.highlight(index: 99)
        #expect(session.selectedIndex == 2)
        session.move(1)
        #expect(session.selectedIndex == 0)
    }
}
