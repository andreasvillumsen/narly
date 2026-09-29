import AppKit

public struct Destination: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let applicationURL: URL?
    public let appLink: AppLink?
    public var isWebBrowser: Bool { appLink == nil }

    public init(id: String, name: String, applicationURL: URL?, appLink: AppLink? = nil) {
        self.id = id
        self.name = name
        self.applicationURL = applicationURL
        self.appLink = appLink
    }
}

@MainActor
public enum DestinationCatalog {
    private static func installedURL(for id: String) -> URL? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    public static func supportedDestinations() -> [Destination] {
        let browsers = [("org.mozilla.firefox", "Firefox"), ("com.apple.Safari", "Safari"),
         ("com.google.Chrome", "Chrome"), ("company.thebrowser.Browser", "Arc"),
         ("net.imput.helium", "Helium"), ("app.zen-browser.zen", "Zen"),
         ("com.brave.Browser", "Brave"), ("com.microsoft.edgemac", "Microsoft Edge"),
         ("com.vivaldi.Vivaldi", "Vivaldi"), ("com.operasoftware.Opera", "Opera"),
         ("com.kagi.kagimacOS", "Orion"), ("com.duckduckgo.macos.browser", "DuckDuckGo")].map { id, name in
            Destination(id: id, name: name,
                    applicationURL: installedURL(for: id))
        }
        let apps: [(String, String, AppLink)] = [
            ("com.linear", "Linear", .linear), ("com.tinyspeck.slackmacgap", "Slack", .slack),
            ("com.figma.Desktop", "Figma", .figma),
            ("notion.id", "Notion", .notion), ("us.zoom.xos", "Zoom", .zoom),
            ("com.spotify.client", "Spotify", .spotify)
        ]
        // Prefer the current Teams client, but retain support for an installed classic client.
        let teamsID = ["com.microsoft.teams2", "com.microsoft.teams"].first {
            installedURL(for: $0) != nil
        } ?? "com.microsoft.teams2"
        let teams = Destination(id: teamsID, name: "Teams",
                            applicationURL: installedURL(for: teamsID), appLink: .teams)
        return browsers + [teams] + apps.map { id, name, appLink in
            Destination(id: id, name: name, applicationURL: installedURL(for: id), appLink: appLink)
        }
    }
}

@MainActor
public protocol DestinationOpening {
    /// Prepare a destination without launching an app. This phase can be cancelled.
    func resolve(_ url: URL, in destination: Destination) async throws -> URL
    /// Dispatch an already resolved URL to the selected app.
    func open(_ url: URL, in destination: Destination) async throws
}

public extension DestinationOpening {
    func resolve(_ url: URL, in destination: Destination) async throws -> URL { url }
}

public enum DestinationOpenError: Error { case unavailable, recursiveDestination }

@MainActor
public struct WorkspaceDestinationOpener: DestinationOpening {
    public init() {}

    public func resolve(_ url: URL, in destination: Destination) async throws -> URL {
        if let appLink = destination.appLink {
            return try await AppLinkResolver().resolve(url, for: appLink)
        }
        return url
    }

    public func open(_ url: URL, in destination: Destination) async throws {
        try Task.checkCancellation()
        guard !DestinationPolicy.isRecursive(destination.id)
        else { throw DestinationOpenError.recursiveDestination }
        guard let applicationURL = destination.applicationURL,
              FileManager.default.fileExists(atPath: applicationURL.path) else {
            throw DestinationOpenError.unavailable
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let application = try await NSWorkspace.shared.open([url], withApplicationAt: applicationURL,
                                                            configuration: configuration)
        // Launch Services can report delivery before the destination takes focus.
        // Keep the session in its dispatch phase until that activation has passed,
        // otherwise it can dismiss the next queued picker as an outside focus loss.
        await DestinationActivation.waitUntilReady {
            application.isActive || application.isTerminated
        }
    }
}
