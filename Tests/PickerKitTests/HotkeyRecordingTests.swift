import AppKit
import Testing
@testable import PickerKit

@Suite(.serialized) @MainActor struct HotkeyRecordingTests {
    private func event(_ code: UInt16, flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: repeatKey, keyCode: code))
    }

    @Test(arguments: [UInt16(1), 18, 43, 49, 36, 48, 51, 123, 126, 122])
    func recordedKeyMatchesPickerWithFixedOption(_ code: UInt16) throws {
        let plain = try event(code)
        let option = try event(code, flags: .option)
        guard case .key(let key) = HotkeyRecording.action(for: plain) else {
            Issue.record("Expected a recordable key for key code \(code)")
            return
        }
        #expect(HotkeyRecording.action(for: option) == .key(key))
        #expect(PickerPanel.command(for: option) == .chooseShortcut(key))
        #expect(!AppShortcut.displayKey(key).isEmpty)
    }

    @Test func escapeCancelsAndOtherModifiersAreRejectedWithoutRecording() throws {
        #expect(HotkeyRecording.action(for: try event(53)) == .cancel)
        #expect(HotkeyRecording.action(for: try event(53, flags: .option)) == .cancel)
        #expect(HotkeyRecording.action(for: try event(1, repeatKey: true)) == .ignore)
        for flags: NSEvent.ModifierFlags in [.command, .control, .shift, [.option, .command]] {
            #expect(HotkeyRecording.action(for: try event(1, flags: flags)) == .invalid)
        }
    }

    @Test func keysBeyondLettersPersistAndCannotCollide() throws {
        let suite = "narly-recording-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let destinations = ["one", "two"].map { Destination(id: $0, name: $0, applicationURL: URL(fileURLWithPath: "/Test.app")) }
        for key in ["1", ",", "æ", "space", "left", "f12"] {
            let preferences = DestinationPreferences(destinations: destinations, defaults: defaults)
            #expect(preferences.setAppShortcut(key, for: "one"))
            #expect(!preferences.setAppShortcut(key, for: "two"))
            let restored = DestinationPreferences(destinations: destinations, defaults: defaults)
            #expect(restored.appShortcuts["one"] == key)
        }
        #expect(AppShortcut.normalizedKey("escape") == nil)
        #expect(AppShortcut.normalizedKey("\n") == nil)
        #expect(AppShortcut.normalizedKey("\u{F700}") == nil)
    }

    @Test func captureIsRestrictedToItsFirstResponderAndConsumesCommandEquivalents() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var actions: [HotkeyRecording.Action] = []
        let view = HotkeyCaptureView { actions.append(HotkeyRecording.action(for: $0)) }
        window.contentView = view
        #expect(window.makeFirstResponder(view))
        #expect(view.performKeyEquivalent(with: try event(1, flags: .command)))
        #expect(actions == [.invalid])
        view.keyDown(with: try event(53))
        #expect(actions.last == .cancel)
        #expect(window.makeFirstResponder(nil))
        #expect(!view.performKeyEquivalent(with: try event(1, flags: .command)))
        #expect(actions.count == 2)
    }

    @Test func captureTakesFocusWhenAttachedAndEndsWhenFocusLeaves() async {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var ended = false
        let view = HotkeyCaptureView(onKey: { _ in }, onEnd: { ended = true })
        window.contentView = view
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(window.firstResponder === view)
        #expect(!ended)
        #expect(window.makeFirstResponder(nil))
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(ended)
    }
}
