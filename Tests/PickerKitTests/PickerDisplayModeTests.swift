import AppKit
import SwiftUI
import Testing
@testable import PickerKit

@Suite @MainActor struct PickerDisplayModeTests {
    @Test func modePersistsWithoutChangingAppsAndInvalidValuesFallBack() throws {
        let suite = "narly-mode-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let destinations = [Destination(id: "a", name: "A", applicationURL: URL(fileURLWithPath: "/A.app")),
                        Destination(id: "b", name: "B", applicationURL: URL(fileURLWithPath: "/B.app"))]
        let preferences = DestinationPreferences(destinations: destinations, defaults: defaults)
        #expect(preferences.pickerMode == .full)
        preferences.move("b", by: -1)
        preferences.setPreferred("b")
        preferences.setPickerMode(.compact)
        let restored = DestinationPreferences(destinations: destinations, defaults: defaults)
        #expect(restored.pickerMode == .compact)
        #expect(restored.visibleDestinations.map(\.id) == ["b", "a"])
        #expect(restored.preferredID == "b")
        defaults.set("unknown-mode", forKey: "narly.pickerDisplayMode.v1")
        let fallback = DestinationPreferences(destinations: destinations, defaults: defaults)
        #expect(fallback.pickerMode == .full)
        #expect(fallback.preferredID == "b")
    }

    @Test func compactLimitsOnlyTheViewportNotKeyboardDestinations() throws {
        let destinations = (0..<12).map { Destination(id: "\($0)", name: "Browser \($0)", applicationURL: URL(fileURLWithPath: "/\($0).app")) }
        let session = PickerSession(destinations: destinations, opener: WorkspaceDestinationOpener(), displayMode: .compact)
        session.receive([try #require(URL(string: "https://example.com"))])
        session.move(11)
        #expect(session.selectedIndex == 11)
        #expect(session.destinations.count == 12)
        #expect(session.pickerSize == PickerSize(width: PickerSize.widthRange.lowerBound, rows: PickerSize.rowRange.lowerBound))
        #expect(session.displayMode.height(for: session.destinations.count) == 160)
        session.displayMode = .full
        #expect(session.displayMode.height(for: session.destinations.count) == 320)
        #expect(session.selectedIndex == 11)
        #expect(PickerDisplayMode.compact.height(for: 2) == 64)
        #expect(PickerDisplayMode.full.height(for: 0) == 0)
    }

    @Test func nativeOverlayKeepsFullWidthAndRevealsKeyboardSelection() {
        _ = NSApplication.shared
        let scroll = PickerNativeScrollView(content: Color.clear)
        let viewportWidth = PickerSize.compact.width - 12
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: viewportWidth, height: PickerSize.compact.height(for: 12)),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = scroll
        scroll.rowCount = 12
        scroll.selection = PickerScrollSelection(index: 11, request: UUID(), mode: .compact, count: 12)
        scroll.revealSelectionOnLayout = true
        scroll.needsLayout = true
        scroll.layoutSubtreeIfNeeded()
        #expect(scroll.host.isFlipped)
        #expect(scroll.scrollerStyle == .overlay)
        #expect(scroll.verticalScroller?.controlSize == .small)
        #expect(scroll.contentSize.width == viewportWidth)
        #expect(scroll.documentVisibleRect.contains(NSRect(x: 0, y: 352, width: viewportWidth, height: 32)))
        scroll.selection = PickerScrollSelection(index: 0, request: UUID(), mode: .compact, count: 12)
        scroll.revealSelectionOnLayout = true
        scroll.needsLayout = true
        scroll.layoutSubtreeIfNeeded()
        #expect(scroll.documentVisibleRect.minY == 0)
    }
}
