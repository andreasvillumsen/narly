import AppKit

struct ManualApplication: Codable, Equatable {
    let id: String
    let name: String
    let path: String

    init(url: URL) throws {
        let url = url.resolvingSymlinksInPath().standardizedFileURL
        guard url.isFileURL, url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !id.isEmpty,
              bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
              let executable = bundle.executableURL, FileManager.default.isExecutableFile(atPath: executable.path)
        else { throw ManualApplicationError.invalidApplication }
        guard !DestinationPolicy.isRecursive(id) else { throw ManualApplicationError.browserChooser }
        self.id = id
        name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        path = url.path
    }

    @MainActor func resolvedURL() -> URL? {
        let savedURL = URL(fileURLWithPath: path)
        if (try? ManualApplication(url: savedURL).id) == id { return savedURL }
        // LaunchServices can find an app that has moved since it was added.
        if let relocated = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
           (try? ManualApplication(url: relocated).id) == id { return relocated }
        return nil
    }
}

public enum ManualApplicationError: LocalizedError {
    case invalidApplication, browserChooser

    public var errorDescription: String? {
        switch self {
        case .invalidApplication: L10n.text("Choose a valid Mac application (.app).")
        case .browserChooser: L10n.text("This app could send links back to Narly. Choose a browser or another app.")
        }
    }
}

enum DestinationPolicy {
    static func isRecursive(_ id: String) -> Bool {
        id == Bundle.main.bundleIdentifier || ["app.narlymac", "app.narlymac.dev", "com.browserosaurus", "xyz.alexstrnik.Browserino"].contains(id)
    }
}
