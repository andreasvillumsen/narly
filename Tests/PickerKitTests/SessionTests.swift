import Foundation
import Testing
@testable import PickerKit

@MainActor
private final class OpenerSpy: DestinationOpening {
    enum Failure: Error { case unavailable }
    var calls: [(URL, Destination)] = []
    var fails = false
    var duringResolve: (() async throws -> Void)?
    func resolve(_ url: URL, in destination: Destination) async throws -> URL {
        try await duringResolve?()
        return url
    }
    var duringOpen: (() async -> Void)?
    func open(_ url: URL, in destination: Destination) async throws {
        calls.append((url, destination))
        await duringOpen?()
        if fails { throw Failure.unavailable }
    }
}

@Suite @MainActor struct SessionTests {
    @Test func delayedDestinationActivationCannotDismissTheNextQueuedLink() async throws {
        let opener = OpenerSpy()
        let session = PickerSession(destinations: destinations, opener: opener)
        let first = try link("first")
        let next = try link("next")
        session.ready()
        session.receive([first, next])
        var activationTurns = 0
        opener.duringOpen = {
            await DestinationActivation.waitUntilReady(isReady: { activationTurns == 3 }, pause: {
                activationTurns += 1
                // Simulate WindowServer taking key focus after URL delivery.
                session.dismiss()
                #expect(session.isOpening)
                #expect(!session.isPresented)
                #expect(session.queue.pending.map(\.url) == [first, next])
            })
        }
        await session.choose()
        #expect(activationTurns == 3)
        #expect(session.isPresented)
        #expect(session.queue.pending.map(\.url) == [next])
        // A genuine outside click after activation still dismisses normally.
        session.dismiss()
        #expect(!session.isPresented)
        session.restore()
        opener.duringOpen = nil
        await session.choose()
        #expect(opener.calls.map { $0.0 } == [first, next])
    }

    @Test func failedOpenRefreshesCatalogAndPreservesLinkForFallback() async throws {
        let suite = "Narly.failed-open-refresh.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fallback = destinations[1]
        let preferences = DestinationPreferences(destinations: destinations, defaults: defaults, catalogProvider: { [fallback] })
        let opener = OpenerSpy()
        opener.fails = true
        let session = PickerSession(destinations: preferences.visibleDestinations, opener: opener)
        preferences.onChange = { session.refreshDestinations(preferences.visibleDestinations, preferredBrowserID: preferences.preferredID) }
        session.onOpenFailure = { preferences.refreshInstalledApplications() }
        session.ready()
        let url = try link("original")
        session.receive([url])
        await session.choose()
        #expect(session.current?.url == url)
        #expect(session.destinations.map(\.id) == [fallback.id])
        #expect(session.isPresented)
        #expect(session.errorMessage != nil)
        opener.fails = false
        await session.choose()
        #expect(opener.calls.last?.0 == url)
        #expect(opener.calls.last?.1.id == fallback.id)
        #expect(session.queue.pending.isEmpty)
    }

    private var destinations: [Destination] {
        [Destination(id: "test.firefox", name: "Firefox", applicationURL: URL(fileURLWithPath: "/Applications/Firefox.app")),
         Destination(id: "test.safari", name: "Safari", applicationURL: URL(fileURLWithPath: "/Applications/Safari.app"))]
    }
    private func link(_ suffix: String = "") throws -> URL {
        try #require(URL(string: "https://example.com/\(suffix)"))
    }

    @Test func coldDeliveryWaitsForUIReadiness() throws {
        let session = PickerSession(destinations: destinations, opener: OpenerSpy())
        var shows = 0
        session.onShow = { shows += 1 }
        session.receive([try link("first"), try link("second")])
        #expect(shows == 0)
        #expect(!session.isPresented)
        session.ready()
        #expect(shows == 1)
        #expect(session.queue.pending.count == 2)
        #expect(session.current?.url == (try link("first")))
    }

    @Test(arguments: [
        "https://example.com/encoded?q=x%2Fy&token=synthetic-test-value#fragment",
        "https://example.com/oauth/authorize?redirect_uri=narly-test%3A%2F%2Fcallback&state=synthetic%2Bstate&code_challenge=synthetic-test#return",
        "file:///tmp/My%20page.html#chapter",
        "file:///tmp/My%20page.xhtml#chapter"
    ])
    func choosingPreservesURLAndUsesSelectedDestination(_ text: String) async throws {
        let opener = OpenerSpy()
        let session = PickerSession(destinations: destinations, opener: opener)
        let url = try #require(URL(string: text))
        session.ready()
        session.receive([url])
        session.move(1)
        await session.choose()
        #expect(opener.calls.count == 1)
        #expect(opener.calls.first?.0.absoluteString == url.absoluteString)
        #expect(opener.calls.first?.1.id == "test.safari")
        #expect(session.queue.pending.isEmpty)
        #expect(!session.isPresented)
    }

    @Test func failedOpenRetainsLinkAndAllowsDifferentDestination() async throws {
        let opener = OpenerSpy()
        opener.fails = true
        let session = PickerSession(destinations: destinations, opener: opener)
        session.ready()
        session.receive([try link()])
        let id = session.current?.id
        await session.choose()
        #expect(session.current?.id == id)
        #expect(session.isPresented)
        #expect(session.errorMessage != nil)
        opener.fails = false
        await session.choose(index: 1)
        #expect(session.queue.pending.isEmpty)
        #expect(opener.calls.map { $0.1.id } == ["test.firefox", "test.safari"])
    }

    @Test func arrivalAndDuplicateSelectionDuringOpenDoNotDropOrDoubleOpen() async throws {
        let opener = OpenerSpy()
        let session = PickerSession(destinations: destinations, opener: opener)
        let first = try link("first")
        let next = try link("next")
        session.ready()
        session.receive([first])
        opener.duringOpen = {
            session.receive([next, next])
            session.dismiss() // a blur during programmatic hide must not cancel the queue
            await session.choose(index: 1)
        }
        await session.choose()
        opener.duringOpen = nil
        #expect(opener.calls.count == 1)
        #expect(session.queue.pending.map(\.url) == [next, next])
        #expect(session.isPresented)
        await session.choose()
        await session.choose()
        #expect(opener.calls.map { $0.0 } == [first, next, next])
    }

    @Test func incomingLinkDoesNotResetKeyboardSelectionOrReshowWindow() throws {
        let session = PickerSession(destinations: destinations, opener: OpenerSpy())
        var shows = 0
        session.onShow = { shows += 1 }
        session.ready()
        session.receive([try link("1")])
        session.move(1)
        session.receive([try link("2")])
        #expect(session.selectedIndex == 1)
        #expect(shows == 1)
    }

    @Test func escapeCancelsQueueAndRestoreDoesNotOpenBrowser() throws {
        let opener = OpenerSpy()
        let session = PickerSession(destinations: destinations, opener: opener)
        session.ready()
        session.receive([try link("1"), try link("2")])
        session.dismiss()
        #expect(!session.isPresented)
        #expect(session.queue.pending.isEmpty)
        session.restore()
        #expect(session.queue.pending.count == 2)
        #expect(session.isPresented)
        #expect(opener.calls.isEmpty)
    }

    @Test func copySuccessClosesAndCopyFailurePreservesLink() throws {
        let session = PickerSession(destinations: destinations, opener: OpenerSpy())
        let url = try link("?q=exact%20value")
        session.ready()
        session.receive([url])
        session.copy { _ in false }
        #expect(session.isPresented)
        #expect(session.current?.url == url)
        var written: String?
        session.copy { written = $0; return true }
        #expect(written == url.absoluteString)
        #expect(!session.isPresented)
        #expect(session.queue.pending.isEmpty)
    }

    @Test func unavailableBrowserCannotBeSelectedAndEmptyCatalogDoesNotCrash() async throws {
        let opener = OpenerSpy()
        let missing = Destination(id: "test.missing", name: "Missing", applicationURL: nil)
        let session = PickerSession(destinations: [missing, destinations[1]], opener: opener)
        session.ready()
        session.receive([try link()])
        #expect(session.selectedIndex == 1)
        session.move(1)
        #expect(session.selectedIndex == 1)
        await session.choose(index: 0)
        #expect(opener.calls.isEmpty)
        session.refreshDestinations([])
        session.move(-1)
        await session.choose()
        #expect(session.current != nil)
    }

    @Test func preferredBrowserAppliesToEveryLinkAndFallsBackWhenUnavailable() async throws {
        let opener = OpenerSpy()
        let session = PickerSession(destinations: destinations, opener: opener, preferredBrowserID: "test.safari")
        session.ready()
        session.receive([try link("1"), try link("2")])
        #expect(session.selectedIndex == 1)
        await session.choose(index: 0)
        #expect(session.selectedIndex == 1)
        session.refreshDestinations([destinations[0], Destination(id: "test.safari", name: "Safari", applicationURL: nil)],
                                preferredBrowserID: "test.safari")
        #expect(session.selectedIndex == 0)
        await session.choose()
        #expect(opener.calls.map { $0.1.id } == ["test.firefox", "test.firefox"])
    }

    @Test func reorderPreservesSelectedIdentityAndPendingLinks() throws {
        let session = PickerSession(destinations: destinations, opener: OpenerSpy())
        session.ready()
        session.receive([try link("1"), try link("2")])
        let pending = session.queue.pending.map(\.id)
        session.move(1)
        session.refreshDestinations(Array(destinations.reversed()), preferredBrowserID: "test.firefox")
        #expect(session.selectedIndex == 0)
        #expect(session.destinations[session.selectedIndex].id == "test.safari")
        #expect(session.queue.pending.map(\.id) == pending)
        #expect(session.isPresented)
    }

    @Test func settingsChangedDuringOpeningDoNotRedirectCapturedDestination() async throws {
        let opener = OpenerSpy()
        let session = PickerSession(destinations: destinations, opener: opener)
        session.ready()
        session.receive([try link("1"), try link("2")])
        opener.duringOpen = {
            session.refreshDestinations(Array(self.destinations.reversed()), preferredBrowserID: "test.safari")
        }
        await session.choose()
        #expect(opener.calls.first?.1.id == "test.firefox")
        #expect(session.queue.pending.count == 1)
        #expect(session.destinations[session.selectedIndex].id == "test.safari")
        opener.duringOpen = nil
        await session.choose()
        #expect(opener.calls.map { $0.1.id } == ["test.firefox", "test.safari"])
    }
}

@Suite @MainActor struct DestinationSessionTests {
    @Test func slackDispatchHidesPanelBeforeFocusLossAndPreservesNextLink() async throws {
        let opener = OpenerSpy()
        let slack = Destination(id: "slack", name: "Slack", applicationURL: URL(fileURLWithPath: "/Slack.app"), appLink: .slack)
        let session = PickerSession(destinations: [slack], opener: opener)
        let url = try #require(URL(string: "https://acme.slack.com/archives/C456/p1700000000123456"))
        session.ready()
        session.receive([url, url])
        opener.duringOpen = {
            #expect(session.isOpening)
            #expect(!session.isResolving)
            #expect(!session.isPresented)
            session.cancelResolution()
            session.dismiss() // App activation must not dismiss the next queued link.
            #expect(session.queue.pending.count == 2)
        }
        await session.choose()
        #expect(opener.calls.count == 1)
        #expect(session.queue.pending.map(\.url) == [url])
        #expect(session.isPresented)
    }

    @Test func slackResolutionKeepsProgressVisibleAndFailureRetainsOriginalLink() async throws {
        let opener = OpenerSpy()
        opener.fails = true
        let slack = Destination(id: "slack", name: "Slack", applicationURL: URL(fileURLWithPath: "/Applications/Slack.app"), appLink: .slack)
        let session = PickerSession(destinations: [slack], opener: opener)
        let url = try #require(URL(string: "https://acme.slack.com/archives/C456/p1700000000123456"))
        session.ready()
        session.receive([url])
        opener.duringResolve = {
            #expect(session.isOpening)
            #expect(session.isResolving)
            #expect(session.isPresented)
            #expect(session.current?.url == url)
            throw AppLinkError.unsupportedLink
        }
        await session.choose()
        #expect(session.isPresented)
        #expect(!session.isOpening)
        #expect(session.current?.url == url)
        #expect(session.errorMessage != nil)
    }

    private var destinations: [Destination] {
        [Destination(id: "browser", name: "Browser", applicationURL: URL(fileURLWithPath: "/Applications/Browser.app")),
         Destination(id: "figma", name: "Figma", applicationURL: URL(fileURLWithPath: "/Applications/Figma.app"), appLink: .figma),
         Destination(id: "linear", name: "Linear", applicationURL: URL(fileURLWithPath: "/Applications/Linear.app"), appLink: .linear)]
    }

    @Test func destinationsStayVisibleButOnlyMatchingAppsCanOpen() async throws {
        let opener = OpenerSpy()
        let session = PickerSession(destinations: destinations, opener: opener)
        session.ready()
        session.receive([try #require(URL(string: "https://figma.com/design/ABC/Title")),
                         try #require(URL(string: "https://linear.app/acme/issue/WEB-1")),
                         try #require(URL(string: "https://example.com"))])
        #expect(session.destinations.map(\.id) == ["browser", "figma", "linear"])
        #expect(session.destinations.filter { session.canOpen($0) }.map(\.id) == ["browser", "figma"])
        await session.choose(index: 1)
        #expect(opener.calls.first?.1.id == "figma")
        #expect(session.destinations.map(\.id) == ["browser", "figma", "linear"])
        #expect(session.destinations.filter { session.canOpen($0) }.map(\.id) == ["browser", "linear"])
        #expect(session.selectedIndex == 0)
        await session.choose(index: 1) // unsupported Figma selection must do nothing
        #expect(opener.calls.count == 1)
        session.move(1)
        #expect(session.selectedIndex == 2) // keyboard skips unsupported Figma
        await session.choose()
        #expect(session.destinations.map(\.id) == ["browser", "figma", "linear"])
        #expect(session.destinations.filter { session.canOpen($0) }.map(\.id) == ["browser"])
        #expect(session.selectedIndex == 0)
    }

    @Test func unavailableNativeAppDoesNotAppearAndRescanKeepsSelectionValid() throws {
        let session = PickerSession(destinations: destinations, opener: OpenerSpy())
        session.ready()
        session.receive([try #require(URL(string: "https://figma.com/design/ABC/Title"))])
        session.move(1)
        session.refreshDestinations([destinations[0], Destination(id: "figma", name: "Figma", applicationURL: nil, appLink: .figma)])
        #expect(session.destinations.map(\.id) == ["browser"])
        #expect(session.selectedIndex == 0)
    }
}
