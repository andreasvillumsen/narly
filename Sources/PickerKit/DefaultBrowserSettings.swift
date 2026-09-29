import AppKit
import Observation

@MainActor
public protocol DefaultBrowserHandling {
    func handlerID(for scheme: String) -> String?
    func setDefaultApplication(at url: URL, for scheme: String) async throws
}

@MainActor
public struct WorkspaceDefaultBrowserHandler: DefaultBrowserHandling {
    public init() {}

    public func handlerID(for scheme: String) -> String? {
        guard let url = URL(string: "\(scheme)://example.com"),
              let application = NSWorkspace.shared.urlForApplication(toOpen: url) else { return nil }
        return Bundle(url: application)?.bundleIdentifier
    }

    public func setDefaultApplication(at url: URL, for scheme: String) async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: url, toOpenURLsWithScheme: scheme)
    }
}

@MainActor @Observable
public final class DefaultBrowserSettings {
    public private(set) var isDefault = false
    public private(set) var isChanging = false
    public private(set) var message: String?
    public private(set) var hasPartialSelection = false
    @ObservationIgnored private let handler: any DefaultBrowserHandling
    @ObservationIgnored private let applicationURL: URL
    @ObservationIgnored private let bundleID: String

    public var isInstalled: Bool {
        let path = applicationURL.resolvingSymlinksInPath().path
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApplications + "/")
    }

    public init(handler: any DefaultBrowserHandling = WorkspaceDefaultBrowserHandler(),
                applicationURL: URL = Bundle.main.bundleURL,
                bundleID: String = Bundle.main.bundleIdentifier ?? "app.narlymac") {
        self.handler = handler
        self.applicationURL = applicationURL
        self.bundleID = bundleID
        refresh()
    }

    public func refresh() {
        let matches = ["http", "https"].map { handler.handlerID(for: $0) == bundleID }
        isDefault = matches.allSatisfy { $0 }
        hasPartialSelection = matches.contains(true) && !isDefault
    }

    /// Called only by the user's explicit settings button. macOS owns consent.
    public func makeDefault() async {
        guard !isChanging else { return }
        guard isInstalled else {
            message = L10n.text("Open Narly from the Applications folder to set it as your default browser.")
            return
        }
        isChanging = true
        message = nil
        defer { isChanging = false }
        do {
            for scheme in ["http", "https"] where handler.handlerID(for: scheme) != bundleID {
                try await handler.setDefaultApplication(at: applicationURL, for: scheme)
            }
            refresh()
            if !isDefault { message = L10n.text("Narly is set as the default for only some web links. Try again to finish setup.") }
        } catch {
            refresh()
            message = hasPartialSelection
                ? L10n.text("Narly is set as the default for only some web links. Try again to finish setup.")
                : L10n.text("Narly wasn’t set as your default browser. Try again to change it.")
        }
    }
}

public enum LaunchPresentation {
    public static func shouldShowSettingsOnReopen(event: NSAppleEventDescriptor?, hasPendingLinks: Bool) -> Bool {
        event?.eventClass == kCoreEventClass && event?.eventID == kAEReopenApplication && !hasPendingLinks
    }

    public static func isLoginLaunch(event: NSAppleEventDescriptor?) -> Bool {
        event?.eventID == kAEOpenApplication &&
        event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    /// Use AppKit's explicit launch reason, never timing or mouse heuristics.
    public static func shouldShowSettings(isDefaultLaunch: Bool, hasPendingLinks: Bool, isLoginLaunch: Bool = false) -> Bool {
        isDefaultLaunch && !hasPendingLinks && !isLoginLaunch
    }
}
