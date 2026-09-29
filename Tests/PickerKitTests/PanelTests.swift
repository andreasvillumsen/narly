import AppKit
import SwiftUI
import Testing
@testable import PickerKit

/// These tests check native construction and event routing, not WindowServer/Spaces.
@Suite(.serialized) @MainActor struct PanelTests {
    @Test func resizingKeepsOpeningAnchorUntilTheNextPresentation() throws {
        _ = NSApplication.shared
        let screen = (frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                      visibleFrame: CGRect(x: 0, y: 24, width: 1440, height: 852))
        let anchor = CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 50)
        var pointer = anchor
        let destinations = (0..<8).map {
            Destination(id: "\($0)", name: "Browser \($0)", applicationURL: URL(fileURLWithPath: "/Browser.app"))
        }
        let session = PickerSession(destinations: destinations, opener: WorkspaceDestinationOpener(),
                                    displayMode: .custom, customPickerSize: PickerSize(width: 260, rows: 5))
        let controller = PickerPanelController(session: session, diagnostics: Diagnostics(directory: nil),
                                               pointerLocation: { pointer })
        defer { controller.panel.close() }
        session.onShow = {} // Exercise geometry without ordering a test window front.
        session.ready()
        let url = try #require(URL(string: "https://example.com"))
        session.receive([url])
        controller.reposition(screens: [screen])
        let original = controller.panel.frame
        pointer = CGPoint(x: anchor.x + 100, y: anchor.y - 100)
        session.customPickerSize = PickerSize(width: 300, rows: 6)
        controller.reposition(screens: [screen])
        #expect(controller.panel.frame.midX == original.midX)
        #expect(controller.panel.frame.maxY == original.maxY)
        #expect(controller.panel.frame.size != original.size)
        session.dismiss()
        session.receive([url])
        controller.reposition(screens: [screen])
        let expected = PickerPlacement.frame(pointer: pointer,
            size: try #require(controller.panel.contentView).fittingSize, visibleFrame: screen.visibleFrame)
        #expect(controller.panel.frame == expected)
    }

    @Test func realPanelHasIndependentKeyboardEligibility() {
        _ = NSApplication.shared
        let panel = PickerPanel()
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.canJoinAllApplications))
        #expect(!panel.isVisible)
    }

    @Test func panelRoutesFirstKeyboardEventWithoutGlobalMonitor() throws {
        _ = NSApplication.shared
        let panel = PickerPanel()
        var received: PickerCommand?
        panel.handleCommand = { received = $0 }
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                                                 modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                                                 context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                                                 isARepeat: false, keyCode: 36))
        panel.sendEvent(event)
        #expect(received == .choose)
    }

    @Test(arguments: [UInt16(51), UInt16(117)])
    func commandDeleteClearsSearchThroughNativePanelWithoutDismissing(_ deleteKey: UInt16) throws {
        _ = NSApplication.shared
        let destinations = ["Safari", "Firefox"].map {
            Destination(id: $0, name: $0, applicationURL: URL(fileURLWithPath: "/\($0).app"))
        }
        let session = PickerSession(destinations: destinations, opener: WorkspaceDestinationOpener())
        let controller = PickerPanelController(session: session, diagnostics: Diagnostics(directory: nil))
        defer { controller.panel.close() }
        // Exercise actual event routing without bringing a test window onscreen.
        session.onShow = {}
        session.ready()
        session.receive([try #require(URL(string: "https://example.com"))])
        let request = session.current?.id
        session.typeName("ffx")
        #expect(session.selectedIndex == 1)
        func sendDelete(_ flags: NSEvent.ModifierFlags) throws {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: flags, timestamp: 0, windowNumber: controller.panel.windowNumber,
                context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}",
                isARepeat: false, keyCode: deleteKey))
            controller.panel.sendEvent(event)
        }
        try sendDelete([])
        #expect(session.typedQuery == "ff")
        try sendDelete(.command)
        #expect(session.typedQuery.isEmpty)
        #expect(session.selectedIndex == 0)
        #expect(session.matchedNameRanges(for: destinations[1]).isEmpty)
        #expect(session.isPresented)
        #expect(session.current?.id == request)
        #expect(session.queue.dismissed.isEmpty)
        session.move(1)
        try sendDelete(.command)
        #expect(session.selectedIndex == 1) // An empty search is a no-op.
        session.typeName("safr")
        #expect(session.selectedIndex == 0)
    }

    @Test func swiftUIGlassContainsFocusableContentAndKeepsPanelNonactivating() throws {
        _ = NSApplication.shared
        let session = PickerSession(destinations: [], opener: WorkspaceDestinationOpener())
        let controller = PickerPanelController(session: session, diagnostics: Diagnostics(directory: nil))
        defer { controller.panel.close() }
        let content = try #require(controller.panel.contentView as? PickerHostingView<PickerPanelContent>)
        #expect(!controller.panel.hasShadow)
        #expect(content.fittingSize.width == session.pickerSize.width + 32)
        #expect(content.acceptsFirstResponder)
        #expect(content.needsPanelToBecomeKey)
        #expect(controller.panel.makeFirstResponder(content))
        #expect(controller.panel.firstResponder === content)
        #expect(controller.panel.styleMask.contains(.nonactivatingPanel))
        #expect(!controller.panel.isVisible)
    }

    @Test(arguments: [CGPoint(x: 720, y: 820), CGPoint(x: 720, y: 40)], [PickerLayout.list, .horizontal])
    func searchKeepsPanelStationaryAndTransparentSlotOnlyAcceptsVisiblePill(_ anchor: CGPoint, _ layout: PickerLayout) throws {
        _ = NSApplication.shared
        let session = PickerSession(destinations: [
            Destination(id: "safari", name: "Safari", applicationURL: URL(fileURLWithPath: "/Safari.app"))
        ], opener: WorkspaceDestinationOpener(), layout: layout)
        let controller = PickerPanelController(session: session, diagnostics: Diagnostics(directory: nil),
                                               pointerLocation: { anchor })
        defer { controller.panel.close() }
        session.onShow = {}
        session.ready()
        session.receive([try #require(URL(string: "https://example.com"))])
        let screen = (frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                      visibleFrame: CGRect(x: 0, y: 24, width: 1440, height: 852))
        controller.reposition(screens: [screen])
        let originalFrame = controller.panel.frame
        // Native window coordinates start at the bottom left.
        let pillCenter = CGPoint(x: originalFrame.width / 2, y: 32)
        #expect(!controller.containsSurface(at: pillCenter))
        #expect(controller.containsSurface(at: CGPoint(x: originalFrame.width / 2,
                                                       y: originalFrame.height - 40)))
        session.typeName("s")
        controller.reposition(screens: [screen])
        #expect(controller.panel.frame == originalFrame)
        #expect(controller.containsSurface(at: pillCenter))
        #expect(!controller.containsSurface(at: CGPoint(x: 17, y: 32)))
        session.typeName(String(repeating: "a", count: 127))
        controller.reposition(screens: [screen])
        #expect(controller.panel.frame == originalFrame)
        session.clearNameSearch()
        session.typeName("s")
        session.deleteNameCharacter()
        controller.reposition(screens: [screen])
        #expect(controller.panel.frame == originalFrame)
        #expect(!controller.containsSurface(at: pillCenter))
    }

    @Test(arguments: PickerLayout.allCases)
    func linkPillHasItsOwnHitTargetAndConstrainedWidth(_ layout: PickerLayout) throws {
        _ = NSApplication.shared
        let session = PickerSession(destinations: [
            Destination(id: "safari", name: "Safari", applicationURL: URL(fileURLWithPath: "/Safari.app"))
        ], opener: WorkspaceDestinationOpener(), layout: layout)
        let controller = PickerPanelController(session: session, diagnostics: Diagnostics(directory: nil),
                                               pointerLocation: { CGPoint(x: 400, y: 500) })
        defer { controller.panel.close() }
        session.onShow = {}
        session.ready()
        session.receive([try #require(URL(string: "https://example.com"))])
        let screen = (frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                      visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600))
        controller.reposition(screens: [screen])
        let original = controller.panel.frame
        let linkY = original.height - PickerPanelContent.inset - PickerPanelContent.linkHeight / 2
        #expect(controller.containsSurface(at: CGPoint(x: original.width / 2, y: linkY)))
        #expect(!controller.containsSurface(at: CGPoint(x: PickerPanelContent.inset + 1, y: linkY)))
        let gapY = original.height - PickerPanelContent.inset - PickerPanelContent.linkHeight - PickerPanelContent.searchSpacing / 2
        #expect(!controller.containsSurface(at: CGPoint(x: original.width / 2, y: gapY)))
        let longLink = try #require(URL(string: "https://" + String(repeating: "long-name.", count: 20) + "example.com"))
        session.receive([longLink])
        session.copy { _ in true } // Complete the first link without touching the clipboard.
        controller.reposition(screens: [screen])
        #expect(controller.panel.frame.size == original.size)
        #expect(controller.containsSurface(at: CGPoint(x: original.width / 2, y: linkY)))
        // Switching layouts keeps the copy target; transparent corners stay outside.
        session.layout = layout == .list ? .horizontal : .list
        controller.reposition(screens: [screen])
        let switched = controller.panel.frame
        let switchedLinkY = switched.height - PickerPanelContent.inset - PickerPanelContent.linkHeight / 2
        #expect(controller.containsSurface(at: CGPoint(x: switched.width / 2, y: switchedLinkY)))
        #expect(!controller.containsSurface(at: CGPoint(x: 2, y: controller.panel.frame.height - 2)))
    }

    @Test func glassTracksContentSizeWhenRowsOrErrorChangeHeight() {
        _ = NSApplication.shared
        let host = PickerHostingView(rootView: Color.clear.frame(width: 320, height: 196))
        let glass = PickerGlassView()
        glass.contentView = host
        #expect(glass.fittingSize == NSSize(width: 320, height: 196))
        host.rootView = Color.clear.frame(width: 320, height: 300)
        host.layoutSubtreeIfNeeded()
        #expect(glass.fittingSize == NSSize(width: 320, height: 300))
    }
}
