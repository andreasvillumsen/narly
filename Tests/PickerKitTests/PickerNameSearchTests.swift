import Foundation
import Testing
@testable import PickerKit

@MainActor private final class NameSearchOpener: DestinationOpening {
    var opened: [String] = []
    var fails = false
    func open(_ url: URL, in destination: Destination) async throws {
        if fails { throw DestinationOpenError.unavailable }
        opened.append(destination.id)
    }
}

@Suite @MainActor struct PickerNameSearchTests {
    private func session(_ names: [String], opener: NameSearchOpener = NameSearchOpener()) throws -> PickerSession {
        let destinations = names.enumerated().map { Destination(id: "\($0.offset)", name: $0.element, applicationURL: URL(fileURLWithPath: "/\($0.offset).app")) }
        let session = PickerSession(destinations: destinations, opener: opener, displayMode: .compact)
        session.ready()
        session.receive([try #require(URL(string: "https://example.com"))])
        return session
    }

    @Test func prefixesUnderlineIncrementallyAndAnExactNameWins() async throws {
        let opener = NameSearchOpener()
        let session = try session(["Safari", "Firefox", "Firefox Developer Edition"], opener: opener)
        session.typeName("f")
        #expect(session.selectedIndex == -1)
        #expect(session.searchScrollIndex == 0) // “f” also matches the middle of Safari.
        let range = try #require(session.matchedNameRanges(for: session.destinations[1]).first)
        #expect(String(session.destinations[1].name[range]) == "F")
        session.typeName("i")
        let longer = try #require(session.matchedNameRanges(for: session.destinations[1]).first)
        #expect(String(session.destinations[1].name[longer]) == "Fi")
        await session.choose()
        #expect(opener.opened.isEmpty)
        session.typeName("refox")
        #expect(session.selectedIndex == 1)
        await session.choose()
        #expect(opener.opened == ["1"])
        #expect(session.typedQuery.isEmpty)
    }

    @Test func typoBlocksReturnAndBackspaceRecovers() async throws {
        let opener = NameSearchOpener()
        let session = try session(["Safari", "Chrome"], opener: opener)
        session.typeName("CH")
        #expect(session.selectedIndex == 1)
        session.typeName("z")
        #expect(session.selectedIndex == -1)
        await session.choose()
        #expect(opener.opened.isEmpty)
        #expect(session.current != nil)
        session.deleteNameCharacter()
        #expect(session.typedQuery == "CH")
        #expect(session.selectedIndex == 1)
        session.clearNameSearch()
        #expect(session.selectedIndex == 0)
        #expect(session.isPresented)
    }

    @Test func unavailableAppsDoNotMatchAndRefreshRechecksSearch() throws {
        let session = try session(["Safari", "Linear"])
        let native = Destination(id: "1", name: "Linear", applicationURL: URL(fileURLWithPath: "/Linear.app"), appLink: .linear)
        session.refreshDestinations([session.destinations[0], native])
        session.typeName("linear")
        #expect(session.selectedIndex == -1)
        #expect(session.matchedNameRanges(for: native).isEmpty)
        session.clearNameSearch()
        session.typeName("s")
        #expect(session.selectedIndex == 0)
        session.refreshDestinations([native])
        #expect(session.selectedIndex == -1)
    }

    @Test func nextLinkResetsQueryButAdditionalQueuedLinksDoNot() async throws {
        let opener = NameSearchOpener()
        let session = try session(["Safari", "Chrome"], opener: opener)
        session.typeName("ch")
        session.receive([try #require(URL(string: "https://example.com/next"))])
        #expect(session.typedQuery == "ch")
        await session.choose()
        #expect(session.typedQuery.isEmpty)
        #expect(session.selectedIndex == 0)
        #expect(session.current?.url.path == "/next")
        session.typeName("sa")
        session.dismiss()
        session.restore()
        #expect(session.typedQuery.isEmpty)
    }

    @Test func typingSelectsBeyondCompactViewportAndManualNavigationClearsIt() throws {
        let session = try session(["A", "B", "C", "D", "Helium"])
        session.typeName("hel")
        #expect(session.selectedIndex == 4)
        #expect(session.searchScrollIndex == 4)
        session.move(-1)
        #expect(session.typedQuery.isEmpty)
        #expect(session.selectedIndex == 3)
        session.typeName("no-match")
        session.move(1)
        #expect(session.selectedIndex == 0)
        session.typeName("hel")
        session.highlight(index: 2)
        #expect(session.typedQuery.isEmpty)
        #expect(session.selectedIndex == 2)
    }

    @Test func unicodePrefixRangeUsesOriginalNameIndices() throws {
        let name = "Éclair Browser"
        let range = try #require(PickerNameMatch.ranges(in: name, query: "ec").first)
        #expect(String(name[range]) == "Éc")
        #expect(!PickerNameMatch.ranges(in: name, query: "browser").isEmpty)
    }

    @Test func printableKeysAreLocalCommandsAndModifiersKeepTheirMeaning() {
        #expect(PickerCommand.decode(keyCode: 3, characters: "f", command: false, shift: false, option: false, control: false) == .typeName("f"))
        #expect(PickerCommand.decode(keyCode: 3, characters: "F", command: false, shift: true, option: false, control: false) == .typeName("F"))
        #expect(PickerCommand.decode(keyCode: 51, characters: nil, command: false, shift: false, option: false, control: false) == .deleteNameCharacter)
        #expect(PickerCommand.decode(keyCode: 51, characters: nil, command: true, shift: false, option: false, control: false) == .clearNameSearch)
        #expect(PickerCommand.decode(keyCode: 51, characters: nil, command: true, shift: false, option: true, control: false) == nil)
        #expect(PickerCommand.decode(keyCode: 51, characters: nil, command: true, shift: false, option: false, control: true) == nil)
        #expect(PickerCommand.decode(keyCode: 8, characters: "c", command: true, shift: false, option: false, control: false) == .copy)
        #expect(PickerCommand.decode(keyCode: 3, characters: "f", command: false, shift: false, option: false, control: true) == nil)
    }

    @Test(arguments: [("Safari", "sfari"), ("Safari", "safr"), ("Safari", "sfr"),
                      ("Firefox", "ffx"), ("Chrome", "chrm"),
                      ("Helium", "hlm"), ("Arc", "arc"), ("Linear", "lnr"),
                      ("Slack", "slk"), ("Figma", "fgma"), ("Notion", "ntn"),
                      ("Zoom", "zm"), ("Teams", "tms"), ("Spotify", "sptfy")])
    func abbreviationsUnderlineOnlyTheTypedLetters(_ name: String, _ query: String) throws {
        let matches = PickerNameMatch.ranges(in: name, query: query)
        let underlined = matches.map { String(name[$0]) }.joined()
        #expect(underlined.lowercased() == query)
        let session = try session(["Other", name])
        session.typeName(query)
        #expect(session.selectedIndex == 1)
    }

    @Test func omittedLettersAreNotUnderlinedAndRepeatedLettersCannotBeReused() {
        let name = "Safari"
        #expect(PickerNameMatch.ranges(in: name, query: "sfari").map { String(name[$0]) } == ["S", "fari"])
        #expect(PickerNameMatch.ranges(in: name, query: "sffari").isEmpty)
        #expect(PickerNameMatch.ranges(in: name, query: "srafi").isEmpty)
        #expect(PickerNameMatch.ranges(in: name, query: "sfxri").isEmpty)
    }

    @Test func sharedSuffixCannotMistakenlyCountAsAnExactMatch() async throws {
        let opener = NameSearchOpener()
        let session = try session(["Safari", "Super Safari"], opener: opener)
        session.typeName("sfari")
        #expect(session.selectedIndex == -1)
        await session.choose()
        #expect(opener.opened.isEmpty)
        session.clearNameSearch()
        session.typeName("Safari")
        #expect(session.selectedIndex == 0)
        await session.choose()
        #expect(opener.opened == ["0"])
    }
}
