import AppKit
import Carbon
import Testing
@testable import PickerKit

@Suite @MainActor struct NextLinkShortcutTests {
    private var shortcut: NextLinkShortcut {
        .init(keyCode: 80, modifiers: NSEvent.ModifierFlags([.command, .control, .option, .shift]).rawValue, key: "f19")
    }

    @Test func persistenceAndConflictsPreservePreviousChoice() throws {
        let suite = "next-link-shortcut-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DestinationPreferences(destinations: [], defaults: defaults)
        #expect(preferences.nextLinkShortcut == nil)
        #expect(preferences.setNextLinkShortcut(shortcut))
        #expect(DestinationPreferences(destinations: [], defaults: defaults).nextLinkShortcut == shortcut)
        preferences.registerNextLinkShortcut = { _ in false }
        let next = NextLinkShortcut(keyCode: 79, modifiers: shortcut.modifiers, key: "f18")
        #expect(!preferences.setNextLinkShortcut(next))
        #expect(preferences.nextLinkShortcut == shortcut)
        #expect(preferences.nextLinkShortcutError != nil)
        #expect(DestinationPreferences(destinations: [], defaults: defaults).nextLinkShortcut == shortcut)
        preferences.registerNextLinkShortcut = { _ in true }
        #expect(preferences.setNextLinkShortcut(nil))
        #expect(preferences.nextLinkShortcutError == nil)
        #expect(DestinationPreferences(destinations: [], defaults: defaults).nextLinkShortcut == nil)
    }

    @Test func nativeRegistrationRejectsConflictsAndReleasesCombination() {
        let first = NextLinkHotKey()
        let second = NextLinkHotKey()
        defer { first.stop(); second.stop() }
        #expect(first.register(shortcut))
        #expect(first.register(shortcut))
        #expect(!second.register(shortcut))
        #expect(first.register(nil))
        #expect(second.register(shortcut))
        second.stop()
        #expect(first.register(shortcut))
    }

    @Test func nativeHotKeyEventCallsTheRegisteredAction() {
        let registration = NextLinkHotKey()
        defer { registration.stop() }
        var presses = 0
        registration.onPress = { presses += 1 }
        #expect(registration.register(shortcut))
        var event: EventRef?
        #expect(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event) == noErr)
        guard let event else { Issue.record("No native event"); return }
        defer { ReleaseEvent(event) }
        var id = EventHotKeyID(signature: 0x4E41524C, id: 1)
        #expect(SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  MemoryLayout<EventHotKeyID>.size, &id) == noErr)
        #expect(SendEventToEventTarget(event, GetApplicationEventTarget()) == noErr)
        #expect(presses == 1)
    }

    @Test func recordingSuspendsAndRestoresSavedShortcut() throws {
        let suite = "next-link-recording-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DestinationPreferences(destinations: [], defaults: defaults)
        preferences.setNextLinkShortcut(shortcut)
        var registrations: [NextLinkShortcut?] = []
        preferences.registerNextLinkShortcut = { registrations.append($0); return true }
        preferences.setNextLinkShortcutRecording(true)
        preferences.setNextLinkShortcutRecording(false)
        #expect(registrations == [nil, shortcut])
        #expect(preferences.nextLinkShortcut == shortcut)
    }

    @Test func requiresCommandOrControlAndRejectsEscape() {
        #expect(shortcut.isValid)
        #expect(shortcut.title == "⌃⌥⇧⌘F19")
        #expect(!NextLinkShortcut(keyCode: 0, modifiers: NSEvent.ModifierFlags.option.rawValue, key: "a").isValid)
        #expect(!NextLinkShortcut(keyCode: 53, modifiers: shortcut.modifiers, key: "a").isValid)
    }
}
