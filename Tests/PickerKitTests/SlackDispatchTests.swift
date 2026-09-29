import Foundation
import Testing
@testable import PickerKit

@MainActor private final class SlackDispatchSpy: DestinationOpening {
    var attempts: [(URL, String)] = []
    var fails = false

    func resolve(_ url: URL, in destination: Destination) async throws -> URL {
        guard let app = destination.appLink else { return url }
        return try await AppLinkResolver().resolve(url, for: app)
    }

    func open(_ url: URL, in destination: Destination) async throws {
        attempts.append((url, destination.id))
        if fails { throw CocoaError(.fileReadUnknown) }
    }
}

@Suite @MainActor struct SlackDispatchTests {
    @Test(arguments: [false, true])
    func originalPermalinkReachesSlackAndSurvivesFailedDispatch(_ fails: Bool) async throws {
        let original = try #require(URL(string: "https://acme.slack.com/archives/C456/p1700000000123456?thread_ts=1699999999.000123&extra=a%2Fb#reply"))
        let opener = SlackDispatchSpy()
        opener.fails = fails
        let session = PickerSession(destinations: [
            Destination(id: "slack", name: "Slack", applicationURL: URL(fileURLWithPath: "/Slack.app"), appLink: .slack),
            Destination(id: "browser", name: "Browser", applicationURL: URL(fileURLWithPath: "/Browser.app"))
        ], opener: opener)
        session.ready()
        session.receive([original])
        await session.choose(index: 0)
        #expect(opener.attempts.count == 1)
        #expect(opener.attempts.first?.0.absoluteString == original.absoluteString)
        #expect(opener.attempts.first?.1 == "slack")
        if fails {
            #expect(session.current?.url == original)
            #expect(session.isPresented)
            #expect(session.errorMessage != nil)
            opener.fails = false
            await session.choose(index: 1)
            #expect(opener.attempts.last?.0.absoluteString == original.absoluteString)
            #expect(opener.attempts.last?.1 == "browser")
        }
        #expect(session.current == nil)
    }
}
