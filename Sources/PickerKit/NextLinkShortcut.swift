import AppKit
import Carbon

public struct NextLinkShortcut: Codable, Equatable, Sendable {
    public let keyCode: UInt16
    public let modifiers: UInt
    public let key: String

    var flags: NSEvent.ModifierFlags { .init(rawValue: modifiers) }
    public var title: String {
        (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
        + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
        + AppShortcut.displayKey(key)
    }

    var isValid: Bool {
        keyCode < 128 && keyCode != 53 && AppShortcut.normalizedKey(key) != nil
        && !flags.intersection([.command, .control]).isEmpty
        && flags == flags.intersection([.command, .control, .option, .shift])
    }

    static func capture(_ event: NSEvent) -> Self? {
        guard !event.isARepeat,
              let key = AppShortcut.key(keyCode: event.keyCode, characters: event.characters(byApplyingModifiers: [])) else { return nil }
        let shortcut = Self(keyCode: event.keyCode,
                            modifiers: event.modifierFlags.intersection([.command, .control, .option, .shift]).rawValue,
                            key: key)
        return shortcut.isValid ? shortcut : nil
    }

    var carbonModifiers: UInt32 {
        (flags.contains(.command) ? UInt32(cmdKey) : 0)
        | (flags.contains(.control) ? UInt32(controlKey) : 0)
        | (flags.contains(.option) ? UInt32(optionKey) : 0)
        | (flags.contains(.shift) ? UInt32(shiftKey) : 0)
    }
}

/// Registers one explicit combination; never observes arbitrary keyboard input.
@MainActor public final class NextLinkHotKey {
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var shortcut: NextLinkShortcut?
    public var onPress: (() -> Void)?

    public init() {}

    isolated deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    @discardableResult public func register(_ shortcut: NextLinkShortcut?) -> Bool {
        if shortcut == self.shortcut { return true }
        guard let shortcut else {
            if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = nil
            self.shortcut = nil
            return true
        }
        guard shortcut.isValid else { return false }
        if handler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                      id.signature == 0x4E41524C, id.id == 1 else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated {
                    Unmanaged<NextLinkHotKey>.fromOpaque(context).takeUnretainedValue().onPress?()
                }
                return noErr
            }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { return false }
        }
        var next: EventHotKeyRef?
        guard RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers,
                                  EventHotKeyID(signature: 0x4E41524C, id: 1), GetApplicationEventTarget(), 0, &next) == noErr else { return false }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = next
        self.shortcut = shortcut
        return true
    }

    public func stop() {
        register(nil)
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
