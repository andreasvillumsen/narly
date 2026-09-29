import Foundation
import Testing
@testable import PickerKit

@Suite struct AppLinkTests {
    @Test(arguments: [
        (AppLink.linear, "https://linear.app/acme/issue/WEB-123/title?q=a%2Fb#comment"),
        (.figma, "https://www.figma.com/design/ABC/Title?node-id=1%3A2#part"),
        (.figma, "https://figma.com/board/ABC/Board")
    ])
    func nativeAppsPreserveTheirWebURL(_ app: AppLink, _ text: String) throws {
        let url = try #require(URL(string: text))
        #expect(app.accepts(url))
        #expect(app.directURL(url)?.absoluteString == text)
    }

    @Test(arguments: [
        "https://linear.app.evil.test/acme/issue/WEB-1", "https://evil.test/linear.app/acme/issue/WEB-1",
        "https://figma.com.evil.test/design/ABC/Title", "https://figma.com@evil.test/design/ABC/Title",
        "https://linear.app/docs/get-the-app", "https://figma.com/community/file/ABC",
        "https://slack.com/pricing", "https://workspace.slack.com.evil.test/archives/C123",
        "file:///tmp/design.html", "https://figma.com:8888/design/ABC/Title"
    ])
    func unrelatedOrSpoofedLinksDoNotOfferApps(_ text: String) throws {
        let url = try #require(URL(string: text))
        #expect(![AppLink.linear, .figma, .slack].contains { $0.accepts(url) })
    }

    @Test func slackMessageKeepsWorkspaceChannelAndTimestamp() throws {
        let url = try #require(URL(string: "https://app.slack.com/client/T123/C456/1700000000.123456?thread_ts=1699999999.000123"))
        let deep = try #require(AppLink.slack.directURL(url))
        #expect(deep.absoluteString == "slack://channel?team=T123&id=C456&message=1700000000.123456&thread_ts=1699999999.000123")
    }

    @Test(arguments: [
        "https://acme.slack.com/archives/C456",
        "https://acme.slack.com/archives/C456/p1700000000123456",
        "https://acme.slack.com/archives/C456/p1700000000123456?team=T123",
        "https://acme.slack.com/archives/C456/p1700000000123456?thread_ts=1699999999.000123&cid=C456&extra=a%2Fb#reply"
    ])
    func slackPermalinksPreserveExactTargetWithoutWorkspaceLookup(_ text: String) async throws {
        let url = try #require(URL(string: text))
        #expect(AppLink.slack.accepts(url))
        #expect(AppLink.slack.directURL(url)?.absoluteString == text)
        #expect(try await AppLinkResolver().resolve(url, for: .slack).absoluteString == text)
    }

    @Test func slackNamesCannotBeMistakenForIDs() throws {
        let url = try #require(URL(string: "https://slack.com/app_redirect?team=acme&channel=general"))
        #expect(!AppLink.slack.accepts(url))
        #expect(AppLink.slack.directURL(url) == nil)
    }


}

@Suite @MainActor struct DestinationPreferenceTests {
    @Test func nativeAppsCannotReplaceTheLastGeneralBrowser() throws {
        let suite = "Narly.destination-tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let destination = Destination(id: "browser", name: "Browser", applicationURL: URL(fileURLWithPath: "/Applications/Browser.app"))
        let native = Destination(id: "figma", name: "Figma", applicationURL: URL(fileURLWithPath: "/Applications/Figma.app"), appLink: .figma)
        let prefs = DestinationPreferences(destinations: [destination, native], defaults: defaults)
        prefs.setVisible(false, id: destination.id)
        #expect(prefs.isVisible(destination.id))
        prefs.setPreferred(native.id)
        #expect(prefs.preferredID == nil)
        prefs.setVisible(false, id: native.id)
        #expect(!prefs.isVisible(native.id))
    }
}
