import Foundation
import Testing
@testable import PickerKit

@MainActor private final class RoutingOpener: DestinationOpening {
    var calls: [(URL, String)] = []
    var failApp = false
    var failAll = false
    func open(_ url: URL, in destination: Destination) async throws {
        calls.append((url, destination.id))
        if failAll || (failApp && destination.appLink != nil) { throw DestinationOpenError.unavailable }
    }
}

@Suite @MainActor struct AppLinkRoutingTests {
    let url = URL(string: "https://linear.app/team/issue/TEST-1?x=a%2Fb#details")!
    let destination = Destination(id: "browser", name: "Browser", applicationURL: URL(fileURLWithPath: "/Browser.app"))
    let app = Destination(id: "linear", name: "Linear", applicationURL: URL(fileURLWithPath: "/Linear.app"), appLink: .linear)

    private func settle(_ session: PickerSession) async {
        for _ in 0..<1000 {
            if !session.isOpening { return }
            await Task.yield()
        }
        Issue.record("Automatic routing did not finish")
    }

    @Test func routingTruthTable() {
        #expect(AppLinkBehavior.ask.route(optionHeld: false) == .ask)
        #expect(AppLinkBehavior.ask.route(optionHeld: true) == .ask)
        #expect(AppLinkBehavior.app.route(optionHeld: false) == .app)
        #expect(AppLinkBehavior.app.route(optionHeld: true) == .ask)
        #expect(AppLinkBehavior.browser.route(optionHeld: false) == .browser)
        #expect(AppLinkBehavior.browser.route(optionHeld: true) == .ask)
    }

    @Test(arguments: [false, true]) func capturesOptionForColdLaunchAndEachQueuedLink(_ option: Bool) async {
        let opener = RoutingOpener()
        let session = PickerSession(destinations: [destination, app], opener: opener)
        session.appLinkBehaviors = ["linear": "app"]
        var shows = 0
        session.onShow = { shows += 1 }
        session.receive([url], optionHeld: option)
        session.receive([url], optionHeld: !option)
        #expect(opener.calls.isEmpty)
        session.ready()
        await settle(session)
        #expect(session.isPresented)
        #expect(opener.calls.map(\.1) == (option ? [] : ["linear"]))
        #expect(shows == 1)
        await session.choose(index: 0)
        await settle(session)
        #expect(opener.calls.map(\.1) == (option ? ["browser", "linear"] : ["linear", "browser"]))
        #expect(opener.calls.allSatisfy { $0.0 == url })
        #expect(session.queue.pending.isEmpty)
        #expect(shows == 1)
    }

    @Test(arguments: [false, true]) func unavailableOrFailingAppFallsBack(_ installed: Bool) async {
        let opener = RoutingOpener()
        opener.failApp = true
        let session = PickerSession(destinations: installed ? [destination, app] : [destination], opener: opener)
        session.appLinkBehaviors = ["linear": "app"]
        session.ready()
        session.receive([url])
        await settle(session)
        #expect(opener.calls.last?.1 == "browser")
        #expect(opener.calls.last?.0 == url)
        #expect(session.current == nil)
    }

    @Test func failedBrowserReturnsToPickerWithoutRetryLoop() async {
        let opener = RoutingOpener()
        opener.failAll = true
        let session = PickerSession(destinations: [destination, app], opener: opener)
        session.appLinkBehaviors = ["linear": "app"]
        session.ready()
        session.receive([url])
        await settle(session)
        #expect(opener.calls.count == 2)
        #expect(session.current?.url == url)
        #expect(session.isPresented)
        #expect(session.errorMessage != nil)
    }

    @Test func ordinaryLinksStillAsk() {
        let session = PickerSession(destinations: [destination, app], opener: RoutingOpener())
        session.appLinkBehaviors = ["linear": "app"]
        session.ready()
        session.receive([URL(string: "https://linear.app/docs")!], optionHeld: true)
        #expect(session.isPresented)
        #expect(!session.isOpening)
    }

    @Test func automaticLinkWaitsBehindManualLinkAndUsesPreferredBrowser() async {
        let opener = RoutingOpener()
        let preferred = Destination(id: "preferred", name: "Preferred", applicationURL: destination.applicationURL)
        let session = PickerSession(destinations: [destination, preferred, app], opener: opener, preferredBrowserID: preferred.id)
        session.appLinkBehaviors = ["linear": "browser"]
        session.ready()
        let ordinary = URL(string: "https://example.com")!
        session.receive([ordinary, url])
        #expect(session.isPresented)
        #expect(opener.calls.isEmpty)
        await session.choose()
        await settle(session)
        #expect(opener.calls.map(\.1) == ["preferred", "preferred"])
        #expect(opener.calls.map(\.0) == [ordinary, url])
        #expect(session.current == nil)
    }

    @Test func preferencesSurviveRestart() throws {
        let suite = "routing.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DestinationPreferences(destinations: [destination, app], defaults: defaults)
        #expect(preferences.appLinkBehaviors.isEmpty)
        preferences.setAppLinkBehavior(.app, for: .linear)
        let restored = DestinationPreferences(destinations: [destination, app], defaults: defaults)
        #expect(restored.appLinkBehaviors["linear"] == "app")
    }
}
