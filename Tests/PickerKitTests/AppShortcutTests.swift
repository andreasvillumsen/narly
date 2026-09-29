import AppKit
import Testing
@testable import PickerKit

@MainActor private final class ShortcutOpener: DestinationOpening {
    var opened: [String] = []
    func open(_ url: URL, in destination: Destination) async throws { opened.append(destination.id) }
}

@Suite @MainActor struct AppShortcutTests {
    private var destinations: [Destination] {
        [Destination(id: "com.apple.Safari", name: "Safari", applicationURL: URL(fileURLWithPath: "/Safari.app")),
         Destination(id: "org.mozilla.firefox", name: "Firefox", applicationURL: URL(fileURLWithPath: "/Firefox.app")),
         Destination(id: "com.linear", name: "Linear", applicationURL: URL(fileURLWithPath: "/Linear.app"), appLink: .linear),
         Destination(id: "missing", name: "Missing", applicationURL: nil)]
    }

    @Test func shortcutsPersistByIdentityAndRejectConflictsIncludingHiddenApps() throws {
        let suite = "narly-shortcuts-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Existing preferences must survive adding the separate shortcut preference.
        defaults.set(Data(#"{"order":["org.mozilla.firefox","com.apple.Safari"],"hidden":[],"preferred":"org.mozilla.firefox"}"#.utf8),
                     forKey: "narly.destinationPreferences.v1")
        let preferences = DestinationPreferences(destinations: destinations, defaults: defaults)
        #expect(preferences.appShortcuts["com.apple.Safari"] == "s")
        #expect(preferences.preferredID == "org.mozilla.firefox")
        #expect(preferences.setAppShortcut("B", for: "org.mozilla.firefox"))
        preferences.setVisible(false, id: "org.mozilla.firefox")
        #expect(!preferences.setAppShortcut("b", for: "com.apple.Safari"))
        #expect(!preferences.setAppShortcut("ss", for: "com.apple.Safari"))
        #expect(preferences.setAppShortcut("1", for: "com.apple.Safari"))
        #expect(preferences.setAppShortcut(nil, for: "com.apple.Safari"))
        preferences.reorder(["com.linear"], before: "com.apple.Safari")
        preferences.rescan(Array(destinations.reversed()))
        let restored = DestinationPreferences(destinations: destinations, defaults: defaults)
        #expect(restored.appShortcuts["org.mozilla.firefox"] == "b")
        #expect(restored.appShortcuts["com.apple.Safari"] == nil)
        #expect(restored.appShortcuts["com.linear"] == "l")
        #expect(restored.orderedDestinations.map(\.id) == preferences.orderedDestinations.map(\.id))
        #expect(!restored.isVisible("org.mozilla.firefox"))
    }

    @Test func directOpenOverridesSearchButRejectsUnavailableHiddenAndUnsupportedApps() async throws {
        let opener = ShortcutOpener()
        let shortcuts = AppShortcut.defaults.merging(["missing": "m"]) { _, new in new }
        let session = PickerSession(destinations: destinations, opener: opener, appShortcuts: shortcuts)
        session.ready()
        session.receive([try #require(URL(string: "https://example.com"))])
        session.typeName("firefox")
        await session.chooseShortcut("l")
        await session.chooseShortcut("m")
        await session.chooseShortcut("x")
        #expect(opener.opened.isEmpty)
        #expect(session.typedQuery == "firefox")
        session.refreshDestinations(Array(destinations.reversed()))
        await session.chooseShortcut("s")
        #expect(opener.opened == ["com.apple.Safari"])
        #expect(session.queue.pending.isEmpty)
        session.receive([try #require(URL(string: "https://linear.app/example/issue/EX-1"))])
        session.refreshDestinations(destinations.filter { $0.id != "org.mozilla.firefox" })
        await session.chooseShortcut("f")
        #expect(opener.opened.count == 1)
        await session.chooseShortcut("l")
        #expect(opener.opened == ["com.apple.Safari", "com.linear"])
    }

    @Test func hintsSwitchWithoutChangingSearchOrSelectionIncludingRowsBeyondNine() throws {
        let extras = (0..<10).map { Destination(id: "extra-\($0)", name: "Extra \($0)", applicationURL: URL(fileURLWithPath: "/Extra.app")) }
        let session = PickerSession(destinations: extras + destinations, opener: ShortcutOpener(), appShortcuts: AppShortcut.defaults)
        session.ready()
        session.receive([try #require(URL(string: "https://example.com"))])
        session.typeName("safari")
        let selection = session.selectedIndex
        #expect(session.shortcutHint(at: 0) == "1")
        #expect(session.shortcutHint(at: 10) == nil)
        session.showsAppShortcuts = true
        #expect(session.shortcutHint(at: 0) == nil)
        #expect(session.shortcutHint(at: 10) == "S")
        #expect(session.selectedIndex == selection)
        #expect(session.typedQuery == "safari")
        session.showsAppShortcuts = false
        #expect(session.shortcutHint(at: 0) == "1")
    }

    @Test func optionCommandsRemainSeparateFromSearchCopyAndModifiedCombinations() {
        func decode(_ letter: String, command: Bool = false, shift: Bool = false, option: Bool = true, control: Bool = false) -> PickerCommand? {
            PickerCommand.decode(keyCode: 1, characters: letter, command: command, shift: shift, option: option, control: control)
        }
        #expect(decode("s") == .chooseShortcut("s"))
        #expect(decode("S") == .chooseShortcut("s"))
        #expect(decode("s", option: false) == .typeName("s"))
        #expect(decode("c", command: true, option: false) == .copy)
        #expect(decode("s", command: true) == nil)
        #expect(decode("s", control: true) == nil)
        #expect(decode("s", shift: true) == nil)
        #expect(decode("1") == .chooseShortcut("1"))
    }
}

@Suite(.serialized) @MainActor struct NativeShortcutTests {
    @Test func nativeOptionTranslationModifierHintsAndRepeatSuppression() throws {
        _ = NSApplication.shared
        let panel = PickerPanel()
        defer { panel.close() }
        var commands: [PickerCommand] = []
        var optionHeld = false
        panel.handleCommand = { commands.append($0) }
        panel.modifiersChanged = { optionHeld = $0.contains(.option) }
        // Use the current layout's unmodified character, not an assumed US layout.
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .option, timestamp: 0, windowNumber: panel.windowNumber,
            context: nil, characters: "ß", charactersIgnoringModifiers: "ß", isARepeat: false, keyCode: 1))
        let letter = try #require(event.characters(byApplyingModifiers: []).flatMap(AppShortcut.normalizedKey))
        panel.sendEvent(event)
        #expect(commands == [.chooseShortcut(letter)])
        #expect(optionHeld)
        let repeatEvent = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .option, timestamp: 0, windowNumber: panel.windowNumber,
            context: nil, characters: "ß", charactersIgnoringModifiers: "ß", isARepeat: true, keyCode: 1))
        panel.sendEvent(repeatEvent)
        #expect(commands.count == 1)
        for flags: NSEvent.ModifierFlags in [[], .option, []] {
            let modifier = try #require(NSEvent.keyEvent(with: .flagsChanged, location: .zero,
                modifierFlags: flags, timestamp: 0, windowNumber: panel.windowNumber,
                context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58))
            panel.sendEvent(modifier)
            #expect(optionHeld == flags.contains(.option))
        }
    }
}
