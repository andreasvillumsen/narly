import AppKit
import SwiftUI
import Testing
@testable import PickerKit

private func sizedURL(_ bytes: Int, kind: String = "web") throws -> URL {
    let base = switch kind {
    case "unicode": "https://example.com/café/🦄?q=%2F&v="
    case "file": "file:///tmp/café-"
    default: "https://example.com/"
    }
    let prefix = try #require(URL(string: base)).absoluteString
    let suffix = kind == "file" ? ".html" : "#part"
    let padding = bytes - prefix.utf8.count - suffix.utf8.count
    let url = try #require(URL(string: prefix + String(repeating: "a", count: padding) + suffix))
    #expect(url.absoluteString.utf8.count == bytes)
    return url
}

@Suite struct QueueLimitTests {
    @Test(arguments: [9, 10, 11]) func capacityKeepsFIFOAndDistinctDuplicateIdentities(_ count: Int) throws {
        let url = try #require(URL(string: "https://example.com/?a=%2F#part"))
        var queue = LinkQueue()
        let result = queue.enqueue(Array(repeating: url, count: count))
        #expect(result.accepted == min(count, 10))
        #expect(result.rejected.queueFull == max(0, count - 10))
        #expect(queue.pending.map(\.url) == Array(repeating: url, count: min(count, 10)))
        #expect(Set(queue.pending.map(\.id)).count == min(count, 10))
    }

    @Test(arguments: [65_535, 65_536, 65_537], ["web", "unicode", "file"])
    func serializedUTF8ByteBoundaryIsSharedByAllURLKinds(_ bytes: Int, _ kind: String) throws {
        let url = try sizedURL(bytes, kind: kind)
        var queue = LinkQueue()
        let result = queue.enqueue([url])
        #expect(result.accepted == (bytes <= 65_536 ? 1 : 0))
        #expect(result.rejected.oversized == (bytes > 65_536 ? 1 : 0))
        #expect(LinkQueue.accepts(url) == (bytes <= 65_536))
        if let link = queue.pending.first { #expect(link.url.absoluteString == url.absoluteString) }
    }

    @Test func existingQueueWinsAndFullQueueClassifiesRemainderWithoutValidation() throws {
        var queue = LinkQueue()
        let original = try (0..<9).map { try #require(URL(string: "https://example.com/\($0)")) }
        queue.enqueue(original)
        let next = try #require(URL(string: "https://example.com/next"))
        let oversized = try sizedURL(65_537)
        let result = queue.enqueue([oversized, URL(string: "mailto:test@example.com")!, next, oversized, next])
        #expect(result.accepted == 1)
        #expect(result.rejected == LinkRejections(queueFull: 2, oversized: 1, unsupported: 1))
        #expect(queue.pending.map(\.url) == original + [next])
    }

    @Test func snapshotsAndRestorationStayBoundedAndDoNotOverwritePendingLinks() throws {
        var queue = LinkQueue()
        let first = try #require(URL(string: "https://example.com/first"))
        let second = try #require(URL(string: "https://example.com/second"))
        queue.enqueue(Array(repeating: first, count: 12))
        queue.dismiss()
        queue.enqueue(Array(repeating: second, count: 11))
        #expect(queue.pending.count == 10 && queue.dismissed.count == 10)
        let blockedRestore = queue.restore()
        #expect(!blockedRestore)
        #expect(queue.pending.allSatisfy { $0.url == second })
        while let link = queue.pending.first { queue.complete(link.id) }
        let restored = queue.restore()
        #expect(restored)
        #expect(queue.pending.map(\.url) == Array(repeating: first, count: 10))
        #expect(queue.dismissed.isEmpty)
        let repeatedRestore = queue.restore()
        #expect(!repeatedRestore)
        queue.dismiss()
        queue.dismiss()
        #expect(queue.dismissed.count == 10)
    }

    @Test func noticeCountersSaturateInsteadOfOverflowing() {
        let large = LinkRejections(queueFull: Int.max, oversized: 1, unsupported: 1)
        let result = large.merging(large)
        #expect(result.queueFull == Int.max && result.total == Int.max)
    }
}

@MainActor private final class QueueLimitOpener: DestinationOpening {
    var duringOpen: (() async -> Void)?
    var fails = false
    var opened: [URL] = []
    func open(_ url: URL, in destination: Destination) async throws {
        await duringOpen?()
        if fails { throw DestinationOpenError.unavailable }
        opened.append(url)
    }
}

@Suite @MainActor struct QueueLimitSessionTests {
    private var destination: Destination {
        Destination(id: "browser", name: "Browser", applicationURL: URL(fileURLWithPath: "/Browser.app"))
    }
    private func makeSession(_ opener: QueueLimitOpener = QueueLimitOpener()) -> PickerSession {
        PickerSession(destinations: [destination], opener: opener)
    }

    @Test func allOversizedColdDeliveryShowsOneNoticeWithoutOpeningSettings() throws {
        let session = makeSession()
        let url = try sizedURL(65_537)
        var shows = 0
        session.onShow = { shows += 1 }
        session.receive([url, url])
        #expect(session.current == nil && session.hasPendingPresentation)
        #expect(!session.isPresented && shows == 0)
        #expect(!LaunchPresentation.shouldShowSettings(isDefaultLaunch: true, hasPendingLinks: session.hasPendingPresentation))
        session.ready()
        #expect(session.isPresented && shows == 1)
        #expect(session.rejectionNotice?.oversized == 2)
        #expect(!session.canOpen(destination))
        session.receive([url])
        #expect(shows == 1 && session.rejectionNotice?.oversized == 3)
        #expect(session.rejectionMessage?.contains(url.absoluteString) == false)
        session.dismissRejectionNotice()
        #expect(!session.isPresented && !session.hasPendingPresentation)
    }

    @Test func repeatedBurstsCoalesceAndAcknowledgingNoticeKeepsQueueAndSelection() throws {
        let session = makeSession()
        let url = try #require(URL(string: "https://example.com/"))
        var shows = 0
        session.onShow = { shows += 1 }
        session.ready()
        session.receive(Array(repeating: url, count: 11))
        session.typeName("bro")
        let ids = session.queue.pending.map(\.id)
        for _ in 0..<100 { session.receive(Array(repeating: url, count: 30)) }
        #expect(session.queue.pending.map(\.id) == ids)
        #expect(session.typedQuery == "bro")
        #expect(session.rejectionNotice?.queueFull == 3001)
        #expect(shows == 1)
        session.dismissRejectionNotice()
        #expect(session.isPresented && session.queue.pending.map(\.id) == ids)
        #expect(session.rejectionNotice == nil)
        session.copy { $0 == url.absoluteString }
        session.receive([url])
        #expect(session.queue.pending.count == 10 && session.rejectionNotice == nil)
    }

    @Test(arguments: [false, true]) func inFlightLinkCountsUntilSuccessAndFailureKeepsIt(_ fails: Bool) async throws {
        let opener = QueueLimitOpener()
        opener.fails = fails
        let session = makeSession(opener)
        let url = try #require(URL(string: "https://example.com/"))
        session.ready()
        session.receive(Array(repeating: url, count: 10))
        let original = session.current?.id
        opener.duringOpen = {
            await Task.yield()
            session.receive([url, url])
            session.dismiss()
            session.restore()
            #expect(session.queue.pending.count == 10)
            #expect(session.current?.id == original)
        }
        await session.choose()
        #expect(session.queue.pending.count == (fails ? 10 : 9))
        #expect(session.rejectionNotice?.queueFull == 2)
        #expect(session.isPresented && !session.isOpening)
        if fails {
            #expect(session.current?.id == original)
            #expect(session.errorMessage != nil)
        } else { #expect(opener.opened == [url]) }
    }

    @Test func noticeSurvivesDrainingAndDismissRestoreNeverDuplicatesItOrLinks() throws {
        let session = makeSession()
        let url = try #require(URL(string: "https://example.com/"))
        session.ready()
        session.receive(Array(repeating: url, count: 11))
        for _ in 0..<10 { session.copy { _ in true } }
        #expect(session.current == nil && session.isPresented)
        #expect(session.rejectionNotice?.queueFull == 1)
        session.dismiss()
        #expect(!session.isPresented && session.rejectionNotice == nil)
        session.receive(Array(repeating: url, count: 11))
        session.dismiss()
        #expect(session.queue.dismissed.count == 10)
        session.restore()
        session.restore()
        #expect(session.queue.pending.count == 10 && session.queue.dismissed.isEmpty)
        #expect(session.rejectionNotice == nil)
    }

    @Test func rejectedInputDoesNotLeakIntoDiagnosticEvents() throws {
        let session = makeSession()
        var events: [String] = []
        session.trace = { event, _ in events.append(event) }
        session.receive([try sizedURL(65_537), URL(string: "mailto:synthetic@example.com")!])
        #expect(events == ["urls-rejected-full-0-oversized-1-unsupported-1"])
    }

    private func capture(_ controller: PickerPanelController, named name: String) async throws {
        guard let directory = ProcessInfo.processInfo.environment["NARLY_QUEUE_QA_OUTPUT"] else { return }
        // Allow the native run loop to lay out the observed SwiftUI change before QA capture.
        try await Task.sleep(for: .milliseconds(100))
        #expect(!NSScreen.screens.isEmpty, "Native screenshot QA requires access to macOS display information.")
        let view = try #require(controller.panel.contentView)
        #expect(abs(controller.panel.frame.height - view.fittingSize.height) < 1)
        #expect(abs(controller.panel.frame.width - view.fittingSize.width) < 1)
        print("Queue UI size \(name): frame=\(controller.panel.frame.size), fitting=\(view.fittingSize), host=\((view as? PickerSurfaceView)?.glass.contentView?.fittingSize ?? .zero)")
        view.layoutSubtreeIfNeeded()
        controller.panel.displayIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }

    @Test func nativeNoticeOnlyPanelAcceptsEscapeAndKeepsNonactivatingContract() async throws {
        _ = NSApplication.shared
        let session = makeSession()
        let controller = PickerPanelController(session: session, diagnostics: Diagnostics(directory: nil))
        defer { controller.removeMouseMonitors(); controller.panel.orderOut(nil) }
        session.ready()
        session.receive([try sizedURL(65_537)])
        #expect(session.isPresented && controller.panel.isVisible)
        #expect(controller.panel.styleMask.contains(.nonactivatingPanel))
        #expect(controller.panel.frame.height > 80 && controller.panel.frame.height < 500)
        try await capture(controller, named: "notice-only")
        session.dismissRejectionNotice()
        session.receive(Array(repeating: try #require(URL(string: "https://example.com/")), count: 11))
        #expect(session.queue.pending.count == 10 && controller.panel.isVisible)
        try await capture(controller, named: "notice-with-links")
        session.dismissRejectionNotice()
        #expect(session.queue.pending.count == 10 && session.isPresented && session.rejectionNotice == nil)
        try await capture(controller, named: "links-after-notice")
        controller.panel.handleCommand?(.dismiss)
        #expect(!session.isPresented && !controller.panel.isVisible)
        #expect(session.queue.dismissed.count == 10)
    }
}
