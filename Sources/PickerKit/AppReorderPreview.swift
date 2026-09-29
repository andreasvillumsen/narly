import Foundation

/// Offsets keep the list's identities and persisted order unchanged until release.
struct AppReorderPreview: Equatable {
    static let rowHeight: CGFloat = 42
    let id: String
    let source: Int
    let destination: Int

    init(id: String, source: Int, count: Int, translation: CGFloat) {
        self.id = id
        self.source = source
        destination = min(max(source + Int((translation / Self.rowHeight).rounded()), 0), max(0, count - 1))
    }

    func offset(for index: Int) -> CGFloat {
        if source < destination, index > source, index <= destination { return -Self.rowHeight }
        if destination < source, index >= destination, index < source { return Self.rowHeight }
        return 0
    }
}
