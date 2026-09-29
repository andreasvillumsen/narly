import AppKit
import SwiftUI
import Testing
@testable import PickerKit

@MainActor private struct LayoutFailingOpener: DestinationOpening {
    func open(_ url: URL, in destination: Destination) async throws { throw DestinationOpenError.unavailable }
}

@Suite(.serialized) @MainActor struct PickerLayoutTests {
    private var destinations: [Destination] {
        [Destination(id: "safari", name: "Safari", applicationURL: URL(fileURLWithPath: "/Safari.app")),
         Destination(id: "linear", name: "Linear", applicationURL: URL(fileURLWithPath: "/Linear.app"), appLink: .linear),
         Destination(id: "firefox", name: "Firefox", applicationURL: URL(fileURLWithPath: "/Firefox.app")),
         Destination(id: "missing", name: "Missing", applicationURL: nil)]
    }

    @Test func layoutPersistsIndependentlyOfListSize() throws {
        let suite = "narly-layout-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DestinationPreferences(destinations: destinations, defaults: defaults)
        #expect(preferences.pickerLayout == .list)
        let custom = PickerSize(width: 412, rows: 7)
        preferences.savePickerSize(custom)
        preferences.setPickerLayout(.horizontal)
        let restored = DestinationPreferences(destinations: destinations, defaults: defaults)
        #expect(restored.pickerLayout == .horizontal)
        #expect(restored.pickerMode == .custom)
        #expect(restored.customPickerSize == custom)
        restored.setPickerLayout(.list)
        #expect(restored.pickerSize == custom)
        defaults.set("future-layout", forKey: "narly.pickerLayout.v1")
        #expect(DestinationPreferences(destinations: destinations, defaults: defaults).pickerLayout == .list)
    }

    @Test func layoutSwitchPreservesPendingLinkQueryAndSelection() throws {
        let session = PickerSession(destinations: destinations, opener: WorkspaceDestinationOpener())
        session.ready()
        session.receive([try #require(URL(string: "https://example.com"))])
        let request = session.current?.id
        session.typeName("firefox")
        session.layout = .horizontal
        #expect(session.selectedIndex == 2)
        #expect(session.typedQuery == "firefox")
        #expect(session.current?.id == request)
        session.layout = .list
        #expect(session.selectedIndex == 2)
        #expect(session.typedQuery == "firefox")
        session.clearNameSearch()
        session.typeName("f")
        session.layout = .horizontal
        #expect(session.selectedIndex == -1)
        #expect(session.nameMatchCount == 2)
        #expect(session.searchScrollIndex == 0)
        session.typeName("zz")
        #expect(session.nameMatchCount == 0)
        #expect(session.searchScrollIndex == -1)
    }

    @Test(arguments: [(0, 280.0), (1, 280.0), (5, 280.0), (6, 320.0), (10, 528.0), (20, 1048.0)])
    func widthFitsEveryAppInOneRow(_ count: Int, _ width: Double) {
        #expect(HorizontalPickerMetrics.contentWidth(count: count) == CGFloat(width))
    }

    @Test(arguments: [0, 1, 5, 12, 20])
    func horizontalRowFitsEveryAppWithoutScrolling(_ count: Int) {
        _ = NSApplication.shared
        let apps = (0..<count).map {
            Destination(id: "\($0)", name: "Browser \($0)", applicationURL: nil)
        }
        let session = PickerSession(destinations: apps, opener: WorkspaceDestinationOpener(), layout: .horizontal)
        let host = NSHostingView(rootView: PickerView(session: session, contentChanged: {}, isPreview: true))
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width == session.contentWidth)
        #expect(host.fittingSize.height == (count == 0 ? 12 : 72))
        #expect(host.fittingSize.width >= HorizontalPickerMetrics.rowWidth(count: count) + 12)
        func containsScrollView(_ view: NSView) -> Bool {
            view is NSScrollView || view.subviews.contains(where: containsScrollView)
        }
        #expect(!containsScrollView(host))
    }

    private func event(_ key: UInt16, flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: repeatKey, keyCode: key))
    }

    @Test func nativeArrowNavigationSkipsUnavailableAppsAndKeepsOptionShortcuts() throws {
        _ = NSApplication.shared
        let session = PickerSession(destinations: destinations, opener: WorkspaceDestinationOpener(), layout: .horizontal)
        let controller = PickerPanelController(session: session, diagnostics: Diagnostics(directory: nil))
        defer { controller.panel.close() }
        session.onShow = {}
        session.ready()
        session.receive([try #require(URL(string: "https://example.com"))])
        controller.panel.sendEvent(try event(124))
        #expect(session.selectedIndex == 2)
        controller.panel.sendEvent(try event(124, repeatKey: true))
        #expect(session.selectedIndex == 0)
        controller.panel.sendEvent(try event(123))
        #expect(session.selectedIndex == 2)
        session.typeName("safari")
        controller.panel.sendEvent(try event(124))
        #expect(session.typedQuery.isEmpty)
        #expect(session.selectedIndex == 2)
        controller.panel.sendEvent(try event(48, flags: .shift))
        #expect(session.selectedIndex == 0)
        var received: PickerCommand?
        controller.panel.handleCommand = { received = $0 }
        controller.panel.sendEvent(try event(124, flags: .option))
        #expect(received == .chooseShortcut("right"))
        #expect(PickerPanel.command(for: try event(124), layout: .list) == nil)
        #expect(PickerPanel.command(for: try event(123, flags: .command), layout: .horizontal) == nil)
    }

    @Test(arguments: PickerLayout.allCases)
    func openingErrorKeepsLinkAndAnchorAvailable(_ layout: PickerLayout) async throws {
        _ = NSApplication.shared
        let screen = (frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                      visibleFrame: CGRect(x: 0, y: 24, width: 1440, height: 852))
        var pointer = CGPoint(x: 720, y: 700)
        let session = PickerSession(destinations: destinations, opener: LayoutFailingOpener(), layout: layout)
        let controller = PickerPanelController(session: session, diagnostics: Diagnostics(directory: nil),
                                               pointerLocation: { pointer })
        defer { controller.panel.close() }
        session.onShow = {}
        session.ready()
        session.receive([try #require(URL(string: "https://example.com"))])
        let request = session.current?.id
        controller.reposition(screens: [screen])
        let frame = controller.panel.frame
        pointer = CGPoint(x: 100, y: 100)
        await session.choose()
        controller.reposition(screens: [screen])
        #expect(session.errorMessage != nil)
        #expect(session.current?.id == request)
        #expect(session.isPresented)
        #expect(!session.isOpening)
        #expect(controller.panel.frame.midX == frame.midX)
        #expect(controller.panel.frame.maxY == frame.maxY)
        #expect(controller.panel.frame.height > frame.height)
    }

    @Test func horizontalPanelKeepsFullRowWidthAndAnchorAcrossLayoutAndQueueChanges() throws {
        _ = NSApplication.shared
        let screen = (frame: CGRect(x: 0, y: 0, width: 460, height: 900),
                      visibleFrame: CGRect(x: 0, y: 24, width: 460, height: 852))
        let anchor = CGPoint(x: 440, y: 700)
        var pointer = anchor
        let apps = (0..<15).map { Destination(id: "\($0)", name: "Browser \($0)", applicationURL: URL(fileURLWithPath: "/Browser.app")) }
        let session = PickerSession(destinations: apps, opener: WorkspaceDestinationOpener(), layout: .horizontal)
        let controller = PickerPanelController(session: session, diagnostics: Diagnostics(directory: nil), pointerLocation: { pointer })
        defer { controller.panel.close() }
        session.onShow = {}
        session.ready()
        session.receive([try #require(URL(string: "https://example.com"))])
        controller.reposition(screens: [screen])
        #expect(session.contentWidth == 788) // All 15 apps plus spacing and padding.
        #expect(controller.panel.frame.width == session.contentWidth + PickerPanelContent.inset * 2)
        let top = controller.panel.frame.maxY
        pointer = CGPoint(x: 100, y: 100)
        session.layout = .list
        controller.reposition(screens: [screen])
        #expect(controller.panel.frame.maxY == top)
        session.layout = .horizontal
        session.receive([try #require(URL(string: "https://example.com/second"))])
        controller.reposition(screens: [screen])
        #expect(controller.panel.frame.maxY == top)
        #expect(controller.panel.frame.width == session.contentWidth + PickerPanelContent.inset * 2)
        let content = try #require(controller.panel.contentView as? PickerHostingView<PickerPanelContent>)
        #expect(content.fittingSize.width == session.contentWidth + PickerPanelContent.inset * 2)
        let frameBeforeSearch = controller.panel.frame
        session.typeName(String(repeating: "a", count: 128))
        controller.reposition(screens: [screen])
        #expect(controller.panel.frame == frameBeforeSearch)
        #expect(content.fittingSize.width == session.contentWidth + PickerPanelContent.inset * 2)
        let searchCenter = CGPoint(x: frameBeforeSearch.width / 2, y: 32)
        #expect(controller.containsSurface(at: searchCenter))
        session.clearNameSearch()
        controller.reposition(screens: [screen])
        #expect(controller.panel.frame == frameBeforeSearch)
        #expect(!controller.containsSurface(at: searchCenter))
    }
}
