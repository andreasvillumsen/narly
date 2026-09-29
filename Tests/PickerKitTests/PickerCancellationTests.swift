import AppKit
import Testing
@testable import PickerKit

/// Deliberately finishes after cancellation to exercise late-result protection.
@MainActor private final class SuspendedResolver: DestinationOpening {
    var resolutions: [CheckedContinuation<URL, Error>] = []
    var opened: [(URL, String)] = []
    var observedCancellation = false
    private var started: CheckedContinuation<Void, Never>?

    func resolve(_ url: URL, in destination: Destination) async throws -> URL {
        guard destination.appLink == .slack else { return url }
        defer { observedCancellation = observedCancellation || Task.isCancelled }
        return try await withCheckedThrowingContinuation { continuation in
            resolutions.append(continuation)
            started?.resume()
            started = nil
        }
    }

    func waitForResolution(_ count: Int) async {
        if resolutions.count >= count { return }
        await withCheckedContinuation { started = $0 }
    }

    func open(_ url: URL, in destination: Destination) async throws {
        opened.append((url, destination.id))
    }
}

@Suite @MainActor struct PickerCancellationTests {
    private let original = URL(string: "https://acme.slack.com/archives/C456/p1700000000123456")!
    private let resolved = URL(string: "slack://channel?team=T123&id=C456")!
    private var destinations: [Destination] {
        [Destination(id: "slack", name: "Slack", applicationURL: URL(fileURLWithPath: "/Slack.app"), appLink: .slack),
         Destination(id: "browser", name: "Browser", applicationURL: URL(fileURLWithPath: "/Browser.app"))]
    }

    @Test func escapeCancelsLookupAndLateSuccessCannotOpenAfterBrowserSelection() async throws {
        _ = NSApplication.shared
        let opener = SuspendedResolver()
        let session = PickerSession(destinations: destinations, opener: opener)
        let controller = PickerPanelController(session: session, diagnostics: Diagnostics(directory: nil))
        defer { controller.panel.close() }
        session.onShow = {}
        session.onHide = {}
        session.ready()
        session.receive([original])
        session.typeName("slack")
        let attempt = Task { await session.choose() }
        await opener.waitForResolution(1)
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: controller.panel.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53))
        controller.panel.sendEvent(escape)
        #expect(!session.isOpening)
        #expect(session.isPresented)
        #expect(session.current?.url == original)
        await session.choose(index: 1)
        opener.resolutions[0].resume(returning: resolved)
        await attempt.value
        #expect(opener.observedCancellation)
        #expect(opener.opened.count == 1)
        #expect(opener.opened.first?.0 == original)
        #expect(opener.opened.first?.1 == "browser")
        #expect(session.queue.pending.isEmpty)
        #expect(session.errorMessage == nil)
        #expect(!session.isPresented)
    }

    @Test func lateFailureCannotOverwriteRetriedLookup() async {
        let opener = SuspendedResolver()
        let session = PickerSession(destinations: destinations, opener: opener)
        session.ready()
        session.receive([original])
        var failureRefreshes = 0
        session.onOpenFailure = { failureRefreshes += 1 }
        let first = Task { await session.choose() }
        await opener.waitForResolution(1)
        session.cancelResolution()
        let second = Task { await session.choose() }
        await opener.waitForResolution(2)
        opener.resolutions[0].resume(throwing: AppLinkError.unsupportedLink)
        await first.value
        #expect(session.isResolving)
        #expect(session.isOpening)
        #expect(session.errorMessage == nil)
        #expect(failureRefreshes == 0)
        opener.resolutions[1].resume(returning: resolved)
        await second.value
        #expect(opener.opened.count == 1)
        #expect(opener.opened.first?.0 == resolved)
        #expect(!session.isOpening)
        #expect(session.queue.pending.isEmpty)
    }

    @Test func outsideDismissalCancelsLookupAndRestoresOriginalQueueForCopying() async {
        let opener = SuspendedResolver()
        let session = PickerSession(destinations: destinations, opener: opener)
        session.ready()
        session.receive([original, original])
        let attempt = Task { await session.choose() }
        await opener.waitForResolution(1)
        session.dismiss()
        #expect(!session.isPresented)
        #expect(session.queue.dismissed == [original, original])
        session.restore()
        var copied: String?
        session.copy { copied = $0; return true }
        opener.resolutions[0].resume(returning: resolved)
        await attempt.value
        #expect(copied == original.absoluteString)
        #expect(session.queue.pending.map(\.url) == [original])
        #expect(session.isPresented)
        #expect(opener.opened.isEmpty)
    }
}
