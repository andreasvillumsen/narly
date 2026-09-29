import AppKit
import Testing
@testable import PickerKit

@Suite @MainActor struct PickerSearchPresentationTests {
    @Test(arguments: [UInt16(51), UInt16(117)], [PickerLayout.list, .horizontal])
    func commandDeleteStartsNativeRemovalAndRetainsOutgoingText(_ deleteKey: UInt16, _ layout: PickerLayout) throws {
        _ = NSApplication.shared
        let session = PickerSession(destinations: [
            Destination(id: "safari", name: "Safari", applicationURL: URL(fileURLWithPath: "/Safari.app"))
        ], opener: WorkspaceDestinationOpener(), layout: layout)
        let controller = PickerPanelController(session: session, diagnostics: Diagnostics(directory: nil))
        defer { controller.panel.close() }
        session.onShow = {}
        session.ready()
        session.receive([try #require(URL(string: "https://example.com"))])
        session.typeName("asdasd")
        var presentation = PickerSearchPresentation()
        presentation.update(query: session.typedQuery)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .command, timestamp: 0, windowNumber: controller.panel.windowNumber,
            context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}",
            isARepeat: false, keyCode: deleteKey))
        controller.panel.sendEvent(event)
        #expect(session.typedQuery.isEmpty)
        #expect(session.isPresented)

        presentation.update(query: session.typedQuery)
        // Structural removal must begin in the animated update, not completion.
        #expect(!presentation.isMounted)
        #expect(!presentation.isVisible)
        #expect(presentation.query == "asdasd")
        presentation.finishHiding(revision: presentation.revision)
        #expect(!presentation.isMounted)
        #expect(presentation.query.isEmpty)
    }

    @Test func oldCompletionCannotRemoveANewSearchOrCutShortItsNextExit() {
        var presentation = PickerSearchPresentation()
        presentation.update(query: "s")
        presentation.update(query: "")
        let oldExit = presentation.revision
        presentation.update(query: "chrome")
        presentation.finishHiding(revision: oldExit)
        #expect(presentation.isMounted)
        #expect(presentation.isVisible)
        #expect(presentation.query == "chrome")

        presentation.update(query: "")
        presentation.finishHiding(revision: oldExit)
        #expect(!presentation.isMounted)
        #expect(presentation.query == "chrome")
        presentation.finishHiding(revision: presentation.revision)
        #expect(!presentation.isMounted)
    }
}
