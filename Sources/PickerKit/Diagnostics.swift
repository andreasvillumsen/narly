import AppKit
import OSLog

/// Deliberately excludes URLs, hosts, window titles, event payloads and error text.
public struct DiagnosticRecord: Codable, Sendable {
    public let timestamp: Date
    public let uptime: TimeInterval
    public let event: String
    public let build: String
    public let request: UUID?
    public let pid: Int32
    public let appActive: Bool
    public let key: Bool
    public let visible: Bool
    public let onActiveSpace: Bool
    public let frame: [Double]?
    public let screenCount: Int
    public let separateSpaces: Bool
    public let activationPolicy: Int
}

@MainActor
public final class Diagnostics {
    public let directory: URL?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.narlymac", category: "window-events")
    private let encoder: JSONEncoder

    public init(directory: URL?) {
        self.directory = directory
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.ISO8601Format(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        encoder.outputFormatting = [.sortedKeys]
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    public func record(_ event: String, panel: NSPanel? = nil, request: UUID? = nil) {
        let frame = panel.map { [Double($0.frame.minX), Double($0.frame.minY), Double($0.frame.width), Double($0.frame.height)] }
        let record = DiagnosticRecord(timestamp: Date(), uptime: ProcessInfo.processInfo.systemUptime,
                                      event: event, build: Bundle.main.object(forInfoDictionaryKey: "NarlyBuildID") as? String ?? "test",
                                      request: request, pid: ProcessInfo.processInfo.processIdentifier,
                                      appActive: NSApp?.isActive ?? false, key: panel?.isKeyWindow ?? false,
                                      visible: panel?.isVisible ?? false, onActiveSpace: panel?.isOnActiveSpace ?? false,
                                      frame: frame, screenCount: NSScreen.screens.count,
                                      separateSpaces: NSScreen.screensHaveSeparateSpaces,
                                      activationPolicy: NSApp?.activationPolicy().rawValue ?? -1)
        guard var data = try? encoder.encode(record) else { return }
        if let text = String(data: data, encoding: .utf8) { logger.notice("\(text, privacy: .public)") }
        data.append(0x0A)
        guard let directory else { return }
        let file = directory.appendingPathComponent("window-events.jsonl")
        do {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size > 524_288 {
                let old = directory.appendingPathComponent("window-events.previous.jsonl")
                if FileManager.default.fileExists(atPath: old.path) { try FileManager.default.removeItem(at: old) }
                try FileManager.default.moveItem(at: file, to: old)
            }
            if !FileManager.default.fileExists(atPath: file.path) {
                FileManager.default.createFile(atPath: file.path, contents: nil,
                                               attributes: [.posixPermissions: 0o600])
            }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            logger.error("Diagnostic file unavailable; use Console for this subsystem.")
        }
    }
}
