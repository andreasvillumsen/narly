import Foundation

public enum AppLink: String, Equatable, Sendable, CaseIterable {
    case linear, slack, figma, notion, zoom, teams, spotify

    public func accepts(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased()),
              url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased() else { return false }
        let parts = url.path.split(separator: "/").map(String.init)
        switch self {
        case .linear:
            // Marketing, authentication and documentation remain browser destinations.
            return host == "linear.app" && parts.count >= 2
                && !["docs", "blog", "changelog", "features", "integrations", "oauth", "auth", "login", "signup", "api"].contains(parts[0])
        case .figma:
            return ["figma.com", "www.figma.com"].contains(host) && parts.count >= 2
                && ["file", "design", "board", "proto", "slides", "deck", "make"].contains(parts[0])
        case .notion, .zoom, .teams, .spotify:
            return specializedURL(url) != nil
        case .slack:
            guard host == "slack.com" || host.hasSuffix(".slack.com") else { return false }
            if slackURL(url) != nil { return true }
            guard host != "slack.com", (2...3).contains(parts.count), parts[0] == "archives",
                  isID(parts[1], prefixes: "CGD") else { return false }
            return parts.count == 2 || parts[2].range(of: #"^p[0-9]{16}$"#, options: .regularExpression) != nil
        }
    }

    /// Browser choices always retain the original URL. Conversion happens only after an app is chosen.
    public func directURL(_ url: URL) -> URL? {
        guard accepts(url) else { return nil }
        switch self {
        case .linear, .figma: return url // Both installed desktop apps handle the original HTTPS open-url event.
        case .slack:
            // Slack handles workspace permalinks directly, including message/thread targets.
            if url.path.split(separator: "/").first == "archives" { return url }
            return slackURL(url)
        case .notion, .zoom, .teams, .spotify: return specializedURL(url)
        }
    }

    private func slackURL(_ url: URL) -> URL? {
        let parts = url.path.split(separator: "/").map(String.init)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ key: String) -> String? { query.first { $0.name == key }?.value }
        var team: String?
        var channel: String?
        var message: String?
        if parts.count >= 3, parts[0] == "client", parts.count <= 4 {
            team = parts[1]; channel = parts[2]
            if parts.count == 4 { message = parts[3] }
        } else if parts == ["app_redirect"] {
            team = value("team"); channel = value("channel")
        } else if parts.count >= 2, parts[0] == "archives", parts.count <= 3 {
            team = value("team"); channel = parts[1]
            if parts.count == 3 {
                let stamp = parts[2]
                guard stamp.first == "p", stamp.dropFirst().count == 16, stamp.dropFirst().allSatisfy(\.isNumber) else { return nil }
                message = String(stamp.dropFirst().prefix(10)) + "." + String(stamp.suffix(6))
            }
        }
        guard let team, isID(team, prefixes: "T"), let channel, isID(channel, prefixes: "CGD") else { return nil }
        if let message, message.range(of: #"^\d{10}\.\d{6}$"#, options: .regularExpression) == nil { return nil }
        var result = URLComponents()
        result.scheme = "slack"; result.host = "channel"
        result.queryItems = [URLQueryItem(name: "team", value: team), URLQueryItem(name: "id", value: channel)]
        if let message { result.queryItems?.append(URLQueryItem(name: "message", value: message)) }
        if let thread = value("thread_ts"), thread.range(of: #"^\d{10}\.\d{6}$"#, options: .regularExpression) != nil {
            result.queryItems?.append(URLQueryItem(name: "thread_ts", value: thread))
        }
        return result.url
    }

    private func isID(_ value: String, prefixes: String) -> Bool {
        guard let first = value.first, prefixes.contains(first), value.count > 1 else { return false }
        return value.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
    }
}

public enum AppLinkError: Error { case unsupportedLink }

/// Resolves supported app links locally, preserving Slack workspace permalinks unchanged.
public struct AppLinkResolver: Sendable {
    public init() {}

    public func resolve(_ url: URL, for app: AppLink) async throws -> URL {
        try Task.checkCancellation()
        guard let direct = app.directURL(url) else { throw AppLinkError.unsupportedLink }
        return direct
    }
}
