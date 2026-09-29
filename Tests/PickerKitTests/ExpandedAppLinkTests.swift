import Foundation
import Testing
@testable import PickerKit

@Suite struct ExpandedAppLinkTests {
    @Test(arguments: [
        (AppLink.notion, "https://www.notion.so/acme/Project-0123456789abcdef0123456789abcdef?v=view%2Fid#block",
         "notion://www.notion.so/0123456789abcdef0123456789abcdef?v=view%2Fid#block"),
        (.notion, "https://acme.notion.site/01234567-89ab-cdef-0123-456789abcdef?pvs=4",
         "notion://www.notion.so/0123456789abcdef0123456789abcdef?pvs=4"),
        (.zoom, "https://us02web.zoom.us/j/12345678901?pwd=synthetic%2Bpass%2Fword&tk=synthetic-token&action=start&confno=999999999",
         "zoommtg://us02web.zoom.us/join?action=join&confno=12345678901&pwd=synthetic%2Bpass/word&tk=synthetic-token"),
        (.teams, "https://teams.microsoft.com/l/meetup-join/19%3Ameeting_test%40thread.v2/0?context=%7B%22Tid%22%3A%22test%22%7D",
         "msteams://teams.microsoft.com/l/meetup-join/19%3Ameeting_test%40thread.v2/0?context=%7B%22Tid%22%3A%22test%22%7D"),
        (.teams, "https://teams.microsoft.com/l/message/19%3Athread/123?tenantId=synthetic&parentMessageId=456#reply",
         "msteams://teams.microsoft.com/l/message/19%3Athread/123?tenantId=synthetic&parentMessageId=456#reply"),
        (.teams, "https://teams.microsoft.com/meet/000000000000000?p=synthetic%2Bpass",
         "msteams://teams.microsoft.com/meet/000000000000000?p=synthetic%2Bpass"),
        (.spotify, "https://open.spotify.com/intl-da/album/0123456789ABCDEFGHIJKL?si=tracking",
         "spotify:album:0123456789ABCDEFGHIJKL"),
        (.spotify, "https://open.spotify.com/playlist/0123456789ABCDEFGHIJKL",
         "spotify:playlist:0123456789ABCDEFGHIJKL")
    ])
    func convertsOnlyWhenSelected(_ app: AppLink, _ input: String, _ expected: String) async throws {
        let original = try #require(URL(string: input))
        #expect(app.accepts(original))
        let resolved = try await AppLinkResolver().resolve(original, for: app)
        // URLComponents may canonicalize reserved query characters; compare their decoded values.
        let expectedURL = try #require(URL(string: expected))
        let actual = try #require(URLComponents(url: resolved, resolvingAgainstBaseURL: false))
        let wanted = try #require(URLComponents(url: expectedURL, resolvingAgainstBaseURL: false))
        #expect(actual.scheme == wanted.scheme)
        #expect(actual.host == wanted.host)
        #expect(actual.percentEncodedPath == wanted.percentEncodedPath)
        #expect(actual.queryItems == wanted.queryItems)
        #expect(actual.fragment == wanted.fragment)
        #expect(original.absoluteString == input)
    }

    @Test(arguments: [
        "https://notion.so.evil.test/0123456789abcdef0123456789abcdef",
        "https://www.notion.so/login", "https://www.notion.so/help/intro",
        "https://example.com/0123456789abcdef0123456789abcdef",
        "https://acme.notion.site/custom-page-slug", "https://www.notion.so/invalid-id",
        "https://zoom.us.evil.test/j/12345678901", "https://zoom.us@evil.test/j/12345678901",
        "https://zoom.us/j/abc", "https://zoom.us/j/123", "https://zoom.us/my/personal",
        "https://zoom.us/signin", "https://zoom.us/j/12345678901?pwd=one&pwd=two",
        "https://teams.microsoft.com.evil.test/l/chat/0/0", "https://teams.microsoft.com/v2/",
        "https://teams.microsoft.com/l/", "https://teams.live.com/unsupported",
        "https://teams.microsoft.com/meet/invalid", "https://teams.microsoft.com/meet/123/extra",
        "https://open.spotify.com.evil.test/track/0123456789ABCDEFGHIJKL",
        "https://open.spotify.com/track/invalid", "https://open.spotify.com/login",
        "https://spotify.link/short", "file:///tmp/music.html",
        "https://open.spotify.com:443/track/0123456789ABCDEFGHIJKL",
        "https://user:password@open.spotify.com/track/0123456789ABCDEFGHIJKL"
    ])
    func unsupportedAndSpoofedLinksStayInTheBrowser(_ input: String) throws {
        let url = try #require(URL(string: input))
        for app in [AppLink.notion, .zoom, .teams, .spotify] {
            #expect(!app.accepts(url))
            #expect(app.directURL(url) == nil)
        }
    }
}

@Suite @MainActor struct SettingsDestinationGroupsTests {
    @Test func groupsFollowVisibilityInstallationAndSurviveRescan() throws {
        let suite = "narly-group-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let catalog = [
            Destination(id: "browser", name: "Browser", applicationURL: URL(fileURLWithPath: "/Browser.app")),
            Destination(id: "notion", name: "Notion", applicationURL: URL(fileURLWithPath: "/Notion.app"), appLink: .notion),
            Destination(id: "zoom", name: "Zoom", applicationURL: nil, appLink: .zoom),
            Destination(id: "spotify", name: "Spotify", applicationURL: URL(fileURLWithPath: "/Spotify.app"), appLink: .spotify)
        ]
        let preferences = DestinationPreferences(destinations: catalog, defaults: defaults)
        preferences.setVisible(false, id: "notion")
        #expect(preferences.activeSettingsDestinations.map(\.id) == ["browser", "spotify"])
        #expect(preferences.hiddenSettingsDestinations.map(\.id) == ["notion", "zoom"])
        #expect(preferences.visibleDestinations.map(\.id) == ["browser", "spotify"])
        preferences.moveActive("spotify", by: -1)
        #expect(preferences.activeSettingsDestinations.map(\.id) == ["spotify", "browser"])
        preferences.setVisible(true, id: "notion")
        #expect(preferences.activeSettingsDestinations.map(\.id) == ["spotify", "browser", "notion"])
        preferences.setVisible(false, id: "notion")
        preferences.reorder(["spotify"], before: nil)
        #expect(preferences.activeSettingsDestinations.map(\.id) == ["browser", "spotify"])
        let restored = DestinationPreferences(destinations: catalog, defaults: defaults)
        #expect(restored.activeSettingsDestinations == preferences.activeSettingsDestinations)
        #expect(restored.hiddenSettingsDestinations.map(\.id) == ["notion", "zoom"])
        restored.rescan(catalog.map { $0.id == "zoom" ? Destination(id: "zoom", name: "Zoom", applicationURL: URL(fileURLWithPath: "/Zoom.app"), appLink: .zoom) : $0 })
        #expect(restored.hiddenSettingsDestinations.map(\.id) == ["notion"])
        #expect(restored.activeSettingsDestinations.map(\.id) == ["browser", "zoom", "spotify"])
        // Uninstalling hides automatically; reinstalling restores only automatically hidden apps.
        restored.rescan(catalog.map { Destination(id: $0.id, name: $0.name,
            applicationURL: $0.id == "spotify" ? nil : $0.applicationURL, appLink: $0.appLink) })
        #expect(restored.hiddenSettingsDestinations.map(\.id) == ["notion", "zoom", "spotify"])
        #expect(restored.visibleDestinations.map(\.id) == ["browser"])
        restored.rescan(catalog)
        #expect(restored.visibleDestinations.map(\.id) == ["browser", "spotify"])
        #expect(restored.hiddenSettingsDestinations.map(\.id) == ["notion", "zoom"])
        restored.setVisible(false, id: "browser")
        #expect(restored.isVisible("browser")) // Specialized apps cannot replace the last general destination.
    }
}
