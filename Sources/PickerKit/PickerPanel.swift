import AppKit
import SwiftUI

@MainActor
public final class PickerPanel: NSPanel {
    public var pickerLayout: () -> PickerLayout = { .list }
    public var handleCommand: ((PickerCommand) -> Void)?
    public var modifiersChanged: ((NSEvent.ModifierFlags) -> Void)?
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "Narly"
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications]
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isRestorable = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        // Liquid Glass supplies its own rounded shadow. A second window shadow
        // uses the rectangular backing surface and leaves dark corner wedges.
        hasShadow = false
        animationBehavior = .none
        setAccessibilityIdentifier("narly-picker-panel")
    }

    public override func sendEvent(_ event: NSEvent) {
        if event.type == .flagsChanged || event.type == .keyDown {
            modifiersChanged?(event.modifierFlags)
        }
        if event.type == .keyDown, let command = Self.command(for: event, layout: pickerLayout()) {
            if !event.isARepeat || { switch command { case .move, .deleteNameCharacter: return true; default: return false } }() {
                handleCommand?(command)
            }
            return
        }
        super.sendEvent(event)
    }

    public static func command(for event: NSEvent, layout: PickerLayout = .list) -> PickerCommand? {
        // charactersIgnoringModifiers retains Option's symbols/dead keys. Translate
        // without modifiers using the active layout, rather than hardcoded key codes.
        let characters = event.modifierFlags.contains(.option)
            ? event.characters(byApplyingModifiers: []) : event.charactersIgnoringModifiers
        return PickerCommand.decode(keyCode: event.keyCode, characters: characters,
                             command: event.modifierFlags.contains(.command),
                             shift: event.modifierFlags.contains(.shift),
                             option: event.modifierFlags.contains(.option),
                             control: event.modifierFlags.contains(.control), layout: layout)
    }
}

@MainActor
final class PickerHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
}

/// AppKit glass used by the resizable settings preview. The live picker groups
/// its surfaces in SwiftUI. NSGlassEffectView requires its host in contentView.
@MainActor
final class PickerGlassView: NSGlassEffectView {
    override var fittingSize: NSSize { contentView?.fittingSize ?? super.fittingSize }
}

/// Leave room for the glass's effect outside its rounded bounds. The window
/// itself stays transparent instead of clipping the effect at all four corners.
@MainActor
final class PickerSurfaceView: NSView {
    static let inset: CGFloat = 16
    let glass: PickerGlassView

    init(glass: PickerGlassView) {
        self.glass = glass
        super.init(frame: .zero)
        clipsToBounds = false
        addSubview(glass)
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }
    override var fittingSize: NSSize {
        let content = glass.fittingSize
        return NSSize(width: content.width + Self.inset * 2, height: content.height + Self.inset * 2)
    }
    override func layout() {
        super.layout()
        glass.frame = bounds.insetBy(dx: Self.inset, dy: Self.inset)
    }
}

@MainActor
public final class PickerPanelController: NSObject, NSWindowDelegate {
    public let panel: PickerPanel
    private let session: PickerSession
    private let diagnostics: Diagnostics
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var isPresenting = false
    private var presentationAnchor: CGPoint?
    private var presentationRequestID: UUID?
    private let pointerLocation: () -> CGPoint
    private var pickerBounds: CGRect = .zero
    private var searchBounds: CGRect = .zero
    private var linkBounds: CGRect = .zero

    public init(session: PickerSession, diagnostics: Diagnostics,
                pointerLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation }) {
        self.session = session
        self.diagnostics = diagnostics
        self.pointerLocation = pointerLocation
        panel = PickerPanel()
        super.init()
        panel.delegate = self
        let hostingView = PickerHostingView(rootView: PickerPanelContent(session: session, copy: { [weak self] in
            self?.copyLink()
        }, contentChanged: { [weak self] in
            self?.repositionIfVisible()
        }, pickerBoundsChanged: { [weak self] in
            self?.pickerBounds = $0
        }, searchBoundsChanged: { [weak self] in
            self?.searchBounds = $0
        }, linkBoundsChanged: { [weak self] in
            self?.linkBounds = $0
        }))
        panel.contentView = hostingView
        panel.pickerLayout = { [weak session] in session?.layout ?? .list }
        panel.handleCommand = { [weak self] in self?.handle($0) }
        panel.modifiersChanged = { [weak session] flags in
            session?.showsAppShortcuts = flags.contains(.option)
        }
        session.onShow = { [weak self] in self?.show() }
        session.onHide = { [weak self] in self?.hide() }
    }

    private func show() {
        isPresenting = true
        session.showsAppShortcuts = NSEvent.modifierFlags.contains(.option)
        reposition()
        diagnostics.record("panel-before-show", panel: panel, request: session.current?.id)
        panel.makeKeyAndOrderFront(nil)
        if let contentView = panel.contentView {
            let accepted = panel.makeFirstResponder(contentView)
            diagnostics.record(accepted ? "first-responder-accepted" : "first-responder-rejected",
                               panel: panel, request: session.current?.id)
        }
        installMouseMonitors()
        isPresenting = false
        diagnostics.record("panel-after-show", panel: panel, request: session.current?.id)
    }

    private func hide() {
        session.showsAppShortcuts = false
        removeMouseMonitors()
        panel.orderOut(nil)
        // Dispatch temporarily hides the panel. A failed open should return the
        // same link to its original anchor, even if the pointer moved meanwhile.
        if !session.isOpening {
            presentationAnchor = nil
            presentationRequestID = nil
        }
        diagnostics.record("panel-hidden", panel: panel)
    }

    public func repositionIfVisible() {
        guard panel.isVisible else { return }
        reposition()
        diagnostics.record("visible-panel-repositioned", panel: panel, request: session.current?.id)
    }

    func reposition(screens suppliedScreens: [(frame: CGRect, visibleFrame: CGRect)]? = nil) {
        let screens = suppliedScreens ?? NSScreen.screens.map { (frame: $0.frame, visibleFrame: $0.visibleFrame) }
        if presentationAnchor == nil || presentationRequestID != session.current?.id {
            presentationAnchor = pointerLocation()
            presentationRequestID = session.current?.id
        }
        guard let pointer = presentationAnchor else { return }
        guard let index = PickerPlacement.screenIndex(pointer: pointer, frames: screens.map(\.frame)) else {
            diagnostics.record("no-display-available", panel: panel)
            return
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? CGSize(width: 320, height: 220)
        panel.setFrame(PickerPlacement.frame(pointer: pointer, size: size,
                                            visibleFrame: screens[index].visibleFrame,
                                            constrainsWidthToScreen: session.layout == .list), display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        session.showsAppShortcuts = NSEvent.modifierFlags.contains(.option)
        diagnostics.record("panel-became-key", panel: panel, request: session.current?.id)
    }

    public func windowDidResignKey(_ notification: Notification) {
        session.showsAppShortcuts = false
        diagnostics.record("panel-resigned-key", panel: panel, request: session.current?.id)
        guard !isPresenting else { return }
        session.dismiss()
    }

    public func copyLink() {
        session.copy { text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        }
    }

    /// SwiftUI reports bounds from the top left; NSEvent uses window coordinates.
    /// Empty space around and between the glass surfaces dismisses the picker.
    func containsSurface(at pointInWindow: CGPoint) -> Bool {
        guard let content = panel.contentView else { return false }
        var point = content.convert(pointInWindow, from: nil)
        if !content.isFlipped { point.y = content.bounds.height - point.y }
        if RoundedRectangle(cornerRadius: session.layout.cornerRadius).path(in: pickerBounds).contains(point) { return true }
        if session.current != nil,
           Capsule().path(in: linkBounds).contains(point) { return true }
        return !session.typedQuery.isEmpty && Capsule().path(in: searchBounds).contains(point)
    }

    private func handle(_ command: PickerCommand) {
        diagnostics.record("keyboard-command", panel: panel, request: session.current?.id)
        switch command {
        case .move(let offset): session.move(offset)
        case .choose: Task { await session.choose() }
        case .chooseShortcut(let letter): Task { await session.chooseShortcut(letter) }
        case .chooseIndex(let index):
            if session.typedQuery.isEmpty { Task { await session.choose(index: index) } }
            else { session.typeName(String(index + 1)) }
        case .typeName(let text):
            if text == " ", session.typedQuery.isEmpty { Task { await session.choose() } }
            else { session.typeName(text) }
        case .deleteNameCharacter: session.deleteNameCharacter()
        case .clearNameSearch:
            if !session.typedQuery.isEmpty { session.clearNameSearch() }
        case .dismiss:
            if session.isResolving { session.cancelResolution() }
            else if session.typedQuery.isEmpty { session.dismiss() }
            else { session.clearNameSearch() }
        case .copy: copyLink()
        }
    }

    private func installMouseMonitors() {
        removeMouseMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // AppKit invokes event-monitor callbacks on the main thread. Observe mouse
        // events only: no Accessibility permission or global keyboard interception.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.diagnostics.record("outside-click", panel: self.panel, request: self.session.current?.id)
                self.session.dismiss()
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                if let self {
                    if event.window !== self.panel || !self.containsSurface(at: event.locationInWindow) {
                        self.session.dismiss()
                    }
                }
            }
            return event
        }
    }

    public func removeMouseMonitors() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
    }
}
