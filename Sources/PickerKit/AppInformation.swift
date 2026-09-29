import Foundation

public enum AppInformation {
    public static var name: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Narly" }
    public static var isDevelopment: Bool { Bundle.main.object(forInfoDictionaryKey: "NarlyBuildChannel") as? String == "dev" }
    public static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0" }
    public static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }
    public static var versionDescription: String { "\(isDevelopment ? "Narly Dev · " : "")Version \(version) (\(build))" }
    public static var feedbackDetails: String {
        "\(name) \(version) (\(build))\nmacOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }
}
