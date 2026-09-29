import AppKit
import SwiftUI
import Testing
@testable import PickerKit

@Suite @MainActor struct PickerSizeTests {
    @Test func previewDraftDoesNotSaveAndIncludesEnoughRowsWithoutUnavailableNativeApps() throws {
        let suite = "narly-size-preview-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let destinations = [Destination(id: "safari", name: "Safari", applicationURL: nil),
                        Destination(id: "zoom", name: "Zoom", applicationURL: nil, appLink: .zoom)]
        let preferences = DestinationPreferences(destinations: destinations, defaults: defaults)
        preferences.setPickerMode(.compact)
        let preview = PickerSizeWindowController.previewSession(preferences: preferences)
        #expect(preview.pickerSize == .compact)
        #expect(preview.destinations.count == PickerSize.rowRange.upperBound)
        #expect(!preview.destinations.contains { $0.id == "zoom" })
        preview.customPickerSize = PickerSize(width: 500, rows: 12)
        #expect(preferences.pickerSize == .compact)
        #expect(DestinationPreferences(destinations: destinations, defaults: defaults).pickerSize == .compact)
        let reopened = PickerSizeWindowController.previewSession(preferences: preferences)
        #expect(reopened.pickerSize == .compact)
    }

    @Test func customSizePersistsAndPresetsKeepTheSavedCustomSize() throws {
        let suite = "narly-size-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Existing Compact installs use the preset, without overwriting custom dimensions.
        defaults.set("compact", forKey: "narly.pickerDisplayMode.v1")
        let preferences = DestinationPreferences(destinations: [], defaults: defaults)
        #expect(preferences.pickerSize == .compact)
        let custom = PickerSize(width: 410, rows: 7)
        preferences.savePickerSize(custom)
        let restored = DestinationPreferences(destinations: [], defaults: defaults)
        #expect(restored.pickerMode == .custom)
        #expect(restored.pickerSize == custom)
        restored.setPickerMode(.compact)
        #expect(restored.pickerSize == .compact)
        #expect(restored.customPickerSize == custom)
        restored.resetPickerSize()
        let reset = DestinationPreferences(destinations: [], defaults: defaults)
        #expect(reset.pickerMode == .full)
        #expect(reset.pickerSize == .standard)
        #expect(reset.customPickerSize == .standard)
    }

    @Test func invalidStoredDimensionsAreClampedAndCorruptDataFallsBack() throws {
        let decoded = try JSONDecoder().decode(PickerSize.self, from: Data(#"{"width":99999,"rows":-40}"#.utf8))
        #expect(decoded == PickerSize(width: 520, rows: 5))
        #expect(PickerSize(width: .nan, rows: 10) == .standard)
        let previousSize = try JSONDecoder().decode(PickerSize.self, from: Data(#"{"width":240,"rows":2}"#.utf8))
        #expect(previousSize.width == 240)
        #expect(previousSize.rows == 5)
        #expect(previousSize.height(for: 2) == 64)
        #expect(previousSize.height(for: 8) == 160)
        #expect(PickerSize.compact.width == 200)
        #expect(PickerSize.compact.rows == 5)
        let suite = "narly-size-corrupt-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("custom", forKey: "narly.pickerDisplayMode.v1")
        defaults.set(Data("bad data".utf8), forKey: "narly.customPickerSize.v1")
        #expect(DestinationPreferences(destinations: [], defaults: defaults).pickerSize == .standard)
    }

    @Test func nativeWindowSizingSnapsRowsAndNeverExceedsLimits() {
        let initial = PickerSize(width: 300, rows: 6)
        let layout = PickerSizeWindowLayout(surfaceChromeHeight: 98)
        let content = layout.contentSize(for: initial)
        #expect(layout.pickerSize(for: content) == initial)
        #expect(layout.pickerSize(for: CGSize(width: content.width + 41, height: content.height + 15)) == PickerSize(width: 341, rows: 6))
        #expect(layout.pickerSize(for: CGSize(width: content.width + 41, height: content.height + 17)) == PickerSize(width: 341, rows: 7))
        #expect(layout.pickerSize(for: .zero) == PickerSize(width: 200, rows: 5))
        #expect(layout.pickerSize(for: CGSize(width: 10000, height: 10000)) == PickerSize(width: 520, rows: 12))
        #expect(initial.height(for: 2) == 64)
        #expect(initial.height(for: 20) == 192)
        #expect(initial.height(for: 0) == 0)
    }

    @Test func nativeEditorResizesOnlyTheDraftAndSaveCommitsIt() throws {
        _ = NSApplication.shared
        let suite = "narly-native-size-window-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DestinationPreferences(destinations: [], defaults: defaults)
        preferences.setPickerMode(.compact)
        let editor = PickerSizeWindowController(preferences: preferences)
        let window = try #require(editor.window)
        defer { window.close() }
        #expect(window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.resizable))
        #expect(window.styleMask.contains(.closable))
        #expect(window.toolbar != nil)
        #expect(editor.session.pickerSize == .compact)
        let oldSize = try #require(window.contentView?.bounds.size)
        #expect(oldSize == window.contentMinSize)
        #expect(oldSize.width == 272)
        #expect(oldSize.height >= 5 * 32 + 112)
        window.setContentSize(NSSize(width: oldSize.width + 120, height: oldSize.height + 96))
        editor.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: window))
        #expect(editor.session.pickerSize == PickerSize(width: 320, rows: 8))
        #expect(preferences.pickerSize == .compact)
        editor.cancelEditing()
        #expect(preferences.pickerSize == .compact)

        let reopened = PickerSizeWindowController(preferences: preferences)
        defer { reopened.close() }
        #expect(reopened.session.pickerSize == .compact)
        reopened.resetSize()
        #expect(reopened.session.pickerSize == .standard)
        #expect(preferences.pickerSize == .compact)
        reopened.saveEditing()
        #expect(preferences.pickerMode == .custom)
        #expect(preferences.pickerSize == .standard)
    }

    @Test(arguments: [PickerDisplayMode.full, .compact])
    func nativeEditorKeepsAResizableRangeAfterLayout(_ mode: PickerDisplayMode) async throws {
        _ = NSApplication.shared
        let suite = "narly-native-size-range-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DestinationPreferences(destinations: [], defaults: defaults)
        preferences.setPickerMode(mode)
        let editor = PickerSizeWindowController(preferences: preferences)
        let window = try #require(editor.window)
        defer { editor.close() }
        window.contentView?.layoutSubtreeIfNeeded()
        await Task.yield()
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(window.contentMinSize.width < window.contentMaxSize.width)
        #expect(window.contentMinSize.height < window.contentMaxSize.height)
        #expect(window.contentResizeIncrements == NSSize(width: 1, height: 1))
        let smallDrag = NSSize(width: window.frame.width + 1, height: window.frame.height + 1)
        let accepted = window.delegate?.windowWillResize?(window, to: smallDrag) ?? smallDrag
        #expect(accepted == smallDrag)

        let original = try #require(window.contentView?.bounds.size)
        window.setContentSize(NSSize(width: original.width + 40, height: original.height + 17))
        let top = window.frame.maxY
        editor.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification, object: window))
        #expect(editor.session.pickerSize == PickerSize(width: preferences.pickerSize.width + 40,
                                                       rows: preferences.pickerSize.rows + 1))
        #expect(window.contentView?.bounds.height == original.height + 32)
        #expect(window.frame.maxY == top)
        #expect(preferences.pickerMode == mode)
    }

    @Test(arguments: [PickerDisplayMode.full, .compact])
    func nativeToolbarSetupDoesNotChangeTheInitialRowCount(_ mode: PickerDisplayMode) throws {
        _ = NSApplication.shared
        let suite = "narly-native-size-initial-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DestinationPreferences(destinations: [], defaults: defaults)
        preferences.setPickerMode(mode)
        let editor = PickerSizeWindowController(preferences: preferences)
        defer { editor.close() }
        #expect(editor.session.pickerSize == preferences.pickerSize)
    }

    @Test(arguments: [PickerDisplayMode.compact, .custom])
    func smallViewportKeepsAllKeyboardDestinationsAndPanelLocked(_ mode: PickerDisplayMode) throws {
        _ = NSApplication.shared
        let destinations = (0..<14).map { Destination(id: "\($0)", name: "Browser \($0)", applicationURL: URL(fileURLWithPath: "/\($0).app")) }
        let session = PickerSession(destinations: destinations, opener: WorkspaceDestinationOpener(), displayMode: mode,
                                    customPickerSize: PickerSize(width: 420, rows: 6))
        let controller = PickerPanelController(session: session, diagnostics: Diagnostics(directory: nil))
        defer { controller.panel.close() }
        session.onShow = {}
        session.ready()
        session.receive([try #require(URL(string: "https://example.com"))])
        session.move(13)
        #expect(session.selectedIndex == 13)
        #expect(session.destinations.count == 14)
        #expect(session.pickerSize.height(for: session.destinations.count) == (mode == .compact ? 160 : 192))
        #expect(!controller.panel.styleMask.contains(.resizable))
        #expect(!controller.panel.isMovable)
        let surface = try #require(controller.panel.contentView)
        #expect(surface.fittingSize.width == (mode == .compact ? 232 : 452))
    }
}
