import Foundation

/// Option + one layout-aware key. Escape is reserved for cancelling.
enum AppShortcut {
    static let defaults = [
        "com.apple.Safari": "s", "com.google.Chrome": "c",
        "org.mozilla.firefox": "f", "company.thebrowser.Browser": "a",
        "net.imput.helium": "h", "com.linear": "l"
    ]

    private static let specialKeys: [UInt16: String] = [
        49: "space", 36: "return", 76: "enter", 48: "tab", 51: "delete", 117: "forward-delete",
        123: "left", 124: "right", 125: "down", 126: "up",
        115: "home", 119: "end", 116: "page-up", 121: "page-down",
        122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6",
        98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
        105: "f13", 107: "f14", 113: "f15", 106: "f16", 64: "f17", 79: "f18", 80: "f19", 90: "f20"
    ]
    private static let symbols = [
        "space": "␣", "return": "↩", "enter": "⌤", "tab": "⇥", "delete": "⌫", "forward-delete": "⌦",
        "left": "←", "right": "→", "down": "↓", "up": "↑", "home": "↖", "end": "↘",
        "page-up": "⇞", "page-down": "⇟"
    ]

    static func normalizedKey(_ text: String) -> String? {
        let lower = text.lowercased()
        if specialKeys.values.contains(lower) { return lower }
        let allowed = CharacterSet.alphanumerics.union(.punctuationCharacters).union(.symbols)
        guard lower.count == 1, lower.unicodeScalars.allSatisfy({
            allowed.contains($0) && !(0xF700...0xF8FF).contains($0.value)
        }) else { return nil }
        return lower
    }

    static func key(keyCode: UInt16, characters: String?) -> String? {
        guard keyCode != 53 else { return nil }
        return specialKeys[keyCode] ?? characters.flatMap(normalizedKey)
    }

    static func displayKey(_ key: String) -> String {
        symbols[key] ?? key.uppercased()
    }

    static func validated(_ values: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        var used = Set<String>()
        for id in values.keys.sorted() {
            guard let value = values[id], let letter = normalizedKey(value), used.insert(letter).inserted else { continue }
            result[id] = letter
        }
        return result
    }
}
