import Foundation

extension AppLink {
    /// Pure, local conversion. Short links, sign-in and unsupported routes stay in the browser.
    /// Called after the common HTTP(S), credentials and port checks in accepts(_:).
    func specializedURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else { return nil }
        var parts = url.path.split(separator: "/").map(String.init)
        switch self {
        case .notion:
            guard host == "notion.so" || host.hasSuffix(".notion.so") || host.hasSuffix(".notion.site"),
                  (1...2).contains(parts.count), let page = parts.last,
                  let range = page.range(of: #"(?:^|-)([a-fA-F0-9]{32}|[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})$"#,
                                         options: .regularExpression) else { return nil }
            let identifier = page[range].replacingOccurrences(of: "-", with: "")
            components.scheme = "notion"
            components.host = "www.notion.so"
            components.path = "/" + identifier
            return components.url
        case .zoom:
            guard host == "zoom.us" || host.hasSuffix(".zoom.us"), parts.count == 2,
                  parts[0] == "j", parts[1].range(of: #"^[0-9]{9,11}$"#, options: .regularExpression) != nil else { return nil }
            let parameters = (components.queryItems ?? []).filter { ["pwd", "tk"].contains($0.name) }
            guard Set(parameters.map(\.name)).count == parameters.count else { return nil }
            // Never forward action/start/host tokens from a web URL to the native client.
            components.scheme = "zoommtg"
            components.path = "/join"
            components.fragment = nil
            components.queryItems = [URLQueryItem(name: "action", value: "join"),
                                     URLQueryItem(name: "confno", value: parts[1])] + parameters
            return components.url
        case .teams:
            guard host == "teams.microsoft.com" else { return nil }
            let isDeepLink = parts.count >= 3 && parts[0] == "l"
                && ["meetup-join", "chat", "message", "channel", "team", "entity", "file", "call"].contains(parts[1])
            let isMeetingLink = parts.count == 2 && parts[0] == "meet"
                && parts[1].range(of: #"^[0-9]{10,16}$"#, options: .regularExpression) != nil
            guard isDeepLink || isMeetingLink else { return nil }
            // Microsoft documents scheme replacement, not prefixing an HTTPS URL.
            components.scheme = "msteams"
            return components.url
        case .spotify:
            guard host == "open.spotify.com" else { return nil }
            if let prefix = parts.first,
               prefix.range(of: #"^intl-[a-zA-Z]{2}(?:-[a-zA-Z]{2})?$"#, options: .regularExpression) != nil {
                parts.removeFirst()
            }
            guard parts.count == 2,
                  ["track", "album", "artist", "playlist", "show", "episode"].contains(parts[0]),
                  parts[1].range(of: #"^[a-zA-Z0-9]{22}$"#, options: .regularExpression) != nil else { return nil }
            // Resource navigation only: opening a link must not request autoplay.
            return URL(string: "spotify:\(parts[0]):\(parts[1])")
        default:
            return nil
        }
    }
}
