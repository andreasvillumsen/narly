import AppKit
import SwiftUI

struct HotkeyRecorder: View {
    let destination: Destination
    let preferences: DestinationPreferences
    @State private var isRecording = false
    @State private var error: String?

    private var shortcut: String? { preferences.appShortcuts[destination.id] }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button {
                guard !isRecording else { return }
                error = nil
                isRecording = true
            } label: {
                Text(isRecording ? "⌥ …" : (shortcut.map { "⌥" + AppShortcut.displayKey($0) } ?? L10n.text("Set")))
                    .font(.caption)
                    .foregroundStyle(shortcut == nil && !isRecording ? .secondary : .primary)
                    .fixedSize()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n.text("Press a key. ⌥ is added automatically. Press Escape to cancel."))
            .accessibilityLabel(L10n.format("Set shortcut for %@", destination.name))
            .accessibilityValue(isRecording ? L10n.text("Press a key") : (shortcut.map { "⌥" + AppShortcut.displayKey($0) } ?? L10n.text("None")))
            .accessibilityIdentifier("shortcut-\(destination.id)")
            .background {
                if isRecording {
                    HotkeyCapture(onKey: record, onEnd: { isRecording = false })
                        .frame(width: 1, height: 1)
                        .accessibilityHidden(true)
                }
            }
            .contextMenu {
                if shortcut != nil {
                    Button(L10n.text("Remove shortcut")) {
                        preferences.setAppShortcut(nil, for: destination.id)
                        isRecording = false
                    }
                }
            }
            if isRecording, let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(width: 160, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("hotkey-error")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            isRecording = false
        }
    }

    private func record(_ event: NSEvent) {
        switch HotkeyRecording.action(for: event) {
        case .ignore: break
        case .cancel: isRecording = false
        case .invalid:
            error = L10n.text("Press a key without holding Command, Control or Shift. ⌥ is added automatically.")
        case .key(let key):
            if preferences.setAppShortcut(key, for: destination.id) {
                isRecording = false
            } else {
                let owner = preferences.shortcutOwner(for: key)
                let name = preferences.destinations.first { $0.id == owner }?.name ?? L10n.text("another app")
                error = L10n.format("Already used by %@. Choose another key.", name)
            }
        }
    }
}

enum HotkeyRecording {
    enum Action: Equatable { case ignore, cancel, invalid, key(String) }

    static func action(for event: NSEvent) -> Action {
        guard event.type == .keyDown, !event.isARepeat else { return .ignore }
        if event.keyCode == 53 { return .cancel }
        guard event.modifierFlags.intersection([.command, .control, .shift]).isEmpty,
              let key = AppShortcut.key(keyCode: event.keyCode,
                                        characters: event.characters(byApplyingModifiers: [])) else { return .invalid }
        return .key(key)
    }
}

/// Capture only while this row owns first responder; no keyboard monitors.
private struct HotkeyCapture: NSViewRepresentable {
    let onKey: (NSEvent) -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> HotkeyCaptureView { HotkeyCaptureView(onKey: onKey, onEnd: onEnd) }
    func updateNSView(_ view: HotkeyCaptureView, context: Context) {
        view.onKey = onKey
        view.onEnd = onEnd
    }
}

final class HotkeyCaptureView: NSView {
    var onKey: (NSEvent) -> Void
    var onEnd: () -> Void
    override var acceptsFirstResponder: Bool { true }

    init(onKey: @escaping (NSEvent) -> Void, onEnd: @escaping () -> Void = {}) {
        self.onKey = onKey
        self.onEnd = onEnd
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Wait until SwiftUI has attached the recording field.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            let end = onEnd
            DispatchQueue.main.async { end() }
        }
        return resigned
    }

    override func keyDown(with event: NSEvent) { onKey(event) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        onKey(event)
        return true
    }
}
