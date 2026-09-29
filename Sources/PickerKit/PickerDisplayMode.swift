import Foundation

public enum PickerDisplayMode: String, CaseIterable, Sendable {
    case full, compact, custom

    public var rowLimit: Int { self == .compact ? PickerSize.compact.rows : PickerSize.standard.rows }
    var title: String {
        switch self {
        case .full: L10n.text("Standard")
        case .compact: L10n.text("Compact")
        case .custom: L10n.text("Custom")
        }
    }
    func height(for rowCount: Int) -> CGFloat { CGFloat(min(max(0, rowCount), rowLimit)) * 32 }
}

/// Stored dimensions describe the content, excluding the glass effect's margin.
/// Height is a row capacity so short lists never leave an empty panel behind.
public struct PickerSize: Codable, Equatable, Sendable {
    public static let widthRange: ClosedRange<CGFloat> = 200...520
    public static let rowRange = 5...12
    public static let standard = PickerSize(width: 280, rows: 10)
    public static let minimum = PickerSize(width: widthRange.lowerBound, rows: rowRange.lowerBound)
    public static let compact = minimum
    public let width: CGFloat
    public let rows: Int

    public init(width: CGFloat, rows: Int) {
        self.width = width.isFinite ? min(max(width, Self.widthRange.lowerBound), Self.widthRange.upperBound) : 280
        self.rows = min(max(rows, Self.rowRange.lowerBound), Self.rowRange.upperBound)
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(width: try values.decode(CGFloat.self, forKey: .width),
                  rows: try values.decode(Int.self, forKey: .rows))
    }

    func height(for rowCount: Int) -> CGFloat { CGFloat(min(max(0, rowCount), rows)) * 32 }

}
