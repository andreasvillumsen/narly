import Foundation

/// Product defaults, not operating-system limits.
public enum LinkQueueLimits {
    public static let maximumPending = 10
    public static let maximumDismissed = 10
    public static let maximumURLBytes = 65_536
}

public struct LinkRejections: Equatable, Sendable {
    public let queueFull: Int
    public let oversized: Int
    public let unsupported: Int
    public var total: Int { Self.add(Self.add(queueFull, oversized), unsupported) }

    func merging(_ other: Self) -> Self {
        Self(queueFull: Self.add(queueFull, other.queueFull), oversized: Self.add(oversized, other.oversized),
             unsupported: Self.add(unsupported, other.unsupported))
    }

    private static func add(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }
}

public struct LinkAcceptance: Equatable, Sendable {
    public let accepted: Int
    public let rejected: LinkRejections
}

public struct PendingLink: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL

    public var displayName: String {
        url.isFileURL ? url.lastPathComponent : (url.host ?? url.absoluteString)
    }

    public init(url: URL) {
        id = UUID()
        self.url = url
    }
}

/// Each delivery has its own identity, including intentional repeated URLs.
public struct LinkQueue: Sendable {
    public private(set) var pending: [PendingLink] = []
    public private(set) var dismissed: [URL] = []

    public init() {}

    public static func accepts(_ url: URL) -> Bool {
        isWithinSizeLimit(url) && supports(url)
    }

    private static func isWithinSizeLimit(_ url: URL) -> Bool {
        url.absoluteString.utf8.prefix(LinkQueueLimits.maximumURLBytes + 1).count <= LinkQueueLimits.maximumURLBytes
    }

    private static func supports(_ url: URL) -> Bool {
        if url.isFileURL {
            // Match the local web documents declared in the app's Info.plist.
            guard url.host == nil || url.host == "" || url.host?.lowercased() == "localhost" else { return false }
            return ["html", "htm", "shtml", "xhtml", "xht"].contains(url.pathExtension.lowercased())
        }
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return false }
        return true
    }

    @discardableResult
    public mutating func enqueue(_ urls: [URL]) -> LinkAcceptance {
        var accepted = 0, full = 0, oversized = 0, unsupported = 0
        for (index, url) in urls.enumerated() {
            // Once full, classify the remainder as capacity rejections without inspecting them.
            guard pending.count < LinkQueueLimits.maximumPending else {
                full = urls.count - index
                break
            }
            guard Self.isWithinSizeLimit(url) else { oversized += 1; continue }
            guard Self.supports(url) else { unsupported += 1; continue }
            pending.append(PendingLink(url: url))
            accepted += 1
        }
        return LinkAcceptance(accepted: accepted,
                              rejected: LinkRejections(queueFull: full, oversized: oversized, unsupported: unsupported))
    }

    @discardableResult
    public mutating func complete(_ id: UUID) -> Bool {
        guard pending.first?.id == id else { return false }
        pending.removeFirst()
        return true
    }

    public mutating func dismiss() {
        guard !pending.isEmpty else { return }
        dismissed = pending.prefix(LinkQueueLimits.maximumDismissed).map(\.url)
        pending.removeAll()
    }

    @discardableResult
    public mutating func restore() -> Bool {
        guard pending.isEmpty, !dismissed.isEmpty else { return false }
        let urls = dismissed
        dismissed.removeAll()
        return enqueue(urls).accepted > 0
    }
}

public enum PickerCommand: Equatable, Sendable {
    case move(Int), choose, chooseIndex(Int), dismiss, copy
    case typeName(String), deleteNameCharacter, clearNameSearch
    case chooseShortcut(String)

    /// Virtual key codes are used only for non-character navigation keys.
    /// Number shortcuts follow the active keyboard layout.
    public static func decode(keyCode: UInt16, characters: String?, command: Bool,
                              shift: Bool, option: Bool, control: Bool, layout: PickerLayout = .list) -> Self? {
        if command {
            guard !option, !control else { return nil }
            if keyCode == 51 || keyCode == 117 { return .clearNameSearch }
            return characters?.lowercased() == "c" ? .copy : nil
        }
        if option {
            guard !control, !shift, let letter = AppShortcut.key(keyCode: keyCode, characters: characters) else { return nil }
            return .chooseShortcut(letter)
        }
        guard !control else { return nil }
        switch keyCode {
        case 53: return .dismiss
        case 36, 76: return .choose
        case 51, 117: return .deleteNameCharacter
        case 49: return .typeName(" ")
        case 123: return layout == .horizontal ? .move(-1) : nil
        case 124: return layout == .horizontal ? .move(1) : nil
        case 125: return .move(1)
        case 126: return .move(-1)
        case 48: return .move(shift ? -1 : 1)
        default:
            guard let characters, !characters.isEmpty else { return nil }
            if !shift, let number = Int(characters), (1...9).contains(number) {
                return .chooseIndex(number - 1)
            }
            guard characters.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(.nonBaseCharacters).union(.punctuationCharacters).contains($0) }) else { return nil }
            return .typeName(characters)
        }
    }
}
