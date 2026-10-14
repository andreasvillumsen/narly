import AppKit
import SwiftUI

struct NextLinkShortcutRecorder: View {
    let preferences: DestinationPreferences
    @State private var isRecording = false
    @State private var error: String?

    var body: some View {
        HStack(spacing: 8) {
            Button(isRecording ? L10n.text("Press a key") : (preferences.nextLinkShortcut?.title ?? L10n.text("Set"))) {
                error = nil
                isRecording = true
            }
            .buttonStyle(.bordered)
            .help(L10n.text("Include Command or Control in your shortcut. Press Escape to cancel."))
            .accessibilityIdentifier("next-link-shortcut")
            .accessibilityLabel(L10n.text("Shortcut to show picker for next link"))
            .accessibilityValue(preferences.nextLinkShortcut?.title ?? L10n.text("None"))
            .background {
                if isRecording {
                    HotkeyCapture(onKey: record, onEnd: { isRecording = false })
                        .frame(width: 1, height: 1).accessibilityHidden(true)
                }
            }
            .contextMenu {
                if preferences.nextLinkShortcut != nil {
                    Button(L10n.text("Remove shortcut")) {
                        preferences.setNextLinkShortcut(nil)
                        isRecording = false
                    }
                    .accessibilityIdentifier("remove-next-link-shortcut")
                }
            }
        }
        .background { HotkeyErrorPopover(message: isRecording ? error : nil) }
        .onChange(of: isRecording) { _, recording in
            preferences.setNextLinkShortcutRecording(recording)
        }
        .onDisappear { preferences.setNextLinkShortcutRecording(false) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            isRecording = false
        }
    }

    private func record(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        if event.keyCode == 53 { isRecording = false; return }
        guard let shortcut = NextLinkShortcut.capture(event) else {
            error = L10n.text("Include Command or Control in your shortcut. Press Escape to cancel.")
            return
        }
        if preferences.setNextLinkShortcut(shortcut) { isRecording = false }
        else { error = preferences.nextLinkShortcutError }
    }
}
