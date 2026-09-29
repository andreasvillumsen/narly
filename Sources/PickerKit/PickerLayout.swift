import Foundation

public enum PickerLayout: String, CaseIterable, Sendable {
    case list, horizontal

    var cornerRadius: CGFloat { self == .horizontal ? 18 : 12 }

    var title: String {
        switch self {
        case .list: L10n.text("List")
        case .horizontal: L10n.text("Horizontal")
        }
    }
}

/// Content dimensions exclude the transparent margin surrounding the glass.
enum HorizontalPickerMetrics {
    static let iconSize: CGFloat = 40
    static let selectionSize: CGFloat = 44
    static let itemWidth: CGFloat = 48
    static let spacing: CGFloat = 4
    static let itemHeight: CGFloat = 60
    static let padding: CGFloat = 12

    static func rowWidth(count: Int) -> CGFloat {
        CGFloat(max(0, count)) * itemWidth + CGFloat(max(0, count - 1)) * spacing
    }

    static func contentWidth(count: Int) -> CGFloat {
        max(280, rowWidth(count: count) + padding)
    }
}
