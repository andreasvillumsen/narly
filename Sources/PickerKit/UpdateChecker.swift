import Foundation

/// Release tags and bundle versions use major.minor.patch. Prereleases are not offered.
struct ReleaseVersion: Comparable, Sendable {
    let components: [Int]

    init?(_ text: String) {
        let version = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  part.count == 1 || part.first != "0", let number = Int(part) else { return nil }
            numbers.append(number)
        }
        components = numbers
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }

    var description: String { components.map(String.init).joined(separator: ".") }
}

struct AvailableUpdate: Equatable, Sendable {
    let version: String
    let releaseURL: URL
}

enum UpdateCheckResult: Equatable, Sendable {
    case upToDate, noPublicRelease, available(AvailableUpdate)
}

@MainActor
struct UpdateChecker {
    static let endpoint = URL(string: "https://api.github.com/repos/andreasvillumsen/narly/releases/latest")!
    private let load: (URLRequest) async throws -> (Data, URLResponse)

    init(load: @escaping (URLRequest) async throws -> (Data, URLResponse) = Self.loadRelease) {
        self.load = load
    }

    func check(currentVersion: String) async throws -> UpdateCheckResult {
        guard let current = ReleaseVersion(currentVersion) else { throw CheckError.invalidRelease }
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await load(request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw CheckError.invalidResponse }
        if response.statusCode == 404 { return .noPublicRelease }
        guard response.statusCode == 200 else { throw CheckError.invalidResponse }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease,
              let version = ReleaseVersion(release.tag_name),
              release.assets.contains(where: { $0.name.hasSuffix(".dmg") && $0.state == "uploaded" })
        else { throw CheckError.invalidRelease }
        guard version > current else { return .upToDate }
        // Construct the destination from a validated tag; never open a URL supplied by the response.
        let releaseURL = URL(string: "https://github.com/andreasvillumsen/narly/releases/tag/")!
            .appendingPathComponent(release.tag_name)
        return .available(AvailableUpdate(version: version.description, releaseURL: releaseURL))
    }

    private static func loadRelease(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 15
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        return try await session.data(for: request)
    }

    private struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let state: String
        }
    }

    private enum CheckError: Error { case invalidResponse, invalidRelease }
}
