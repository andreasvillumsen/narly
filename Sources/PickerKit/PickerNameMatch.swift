import Foundation

enum PickerNameMatch {
    private static let locale = Locale(identifier: "en_US_POSIX")
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// Ordered subsequence matching: omitted letters are allowed, but letters
    /// cannot be reordered or reused. Return original-name ranges for underlining.
    static func ranges(in name: String, query: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }
        var cursor = name.startIndex
        var matches: [Range<String.Index>] = []
        for character in query {
            guard cursor < name.endIndex,
                  let match = name.range(of: String(character), options: options,
                                         range: cursor..<name.endIndex, locale: locale) else { return [] }
            if let last = matches.last, last.upperBound == match.lowerBound {
                matches[matches.count - 1] = last.lowerBound..<match.upperBound
            } else {
                matches.append(match)
            }
            cursor = match.upperBound
        }
        return matches
    }

    static func isExact(_ name: String, query: String) -> Bool {
        name.compare(query, options: options, locale: locale) == .orderedSame
    }
}
