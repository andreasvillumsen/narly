import Foundation
import Testing
@testable import PickerKit

@Suite struct LocalizationTests {
    private func table(_ language: String) throws -> [String: String] {
        let url = try #require(L10n.bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language))
        return try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
    }

    @Test func bothLanguagesHaveCompleteTranslationsAndMatchingPlaceholders() throws {
        let english = try table("en")
        let danish = try table("da")
        #expect(Set(english.keys) == Set(danish.keys))
        #expect(english.count >= 100)
        let placeholder = try NSRegularExpression(pattern: #"%(?:@|ld)"#)
        func arguments(_ text: String) -> [String] {
            placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range) }.sorted()
        }
        for (key, source) in english {
            let translated = try #require(danish[key])
            #expect(!translated.isEmpty)
            #expect(arguments(source) == arguments(translated))
        }
    }

    @Test(arguments: [(["da-DK", "en-GB"], "da"), (["en-GB", "da-DK"], "en"),
                      (["de-DE", "da-DK"], "da"), (["de-DE"], "en")])
    func macOSLanguagePreferenceOrderAndEnglishFallback(_ preferences: [String], _ expected: String) {
        #expect(Bundle.preferredLocalizations(from: ["en", "da"], forPreferences: preferences).first == expected)
        #expect(L10n.bundle.developmentLocalization == "en")
    }

    @Test func localizedDynamicLabelsKeepNamesAndCounts() throws {
        for (language, open, queued) in [("en", "Open in Helium", "10 links"), ("da", "Åbn i Helium", "10 links")] {
            let translations = try table(language)
            #expect(String(format: try #require(translations["Open in %@"]), "Helium") == open)
            #expect(String(format: try #require(translations["%ld links"]), 10) == queued)
            #expect(translations["Settings…"] == (language == "da" ? "Indstillinger…" : "Settings…"))
        }
    }
}
