import AppKit
import SwiftUI

/// AppKit owns native window resizing; the isolated session owns the draft.
/// The ordinary link panel never becomes resizable.
@MainActor
final class PickerSizeWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    let session: PickerSession
    private let preferences: DestinationPreferences
    private let host: PickerHostingView<PickerView>
    private let surface: PickerSurfaceView
    private let layout: PickerSizeWindowLayout
    private var isUpdatingSize = true
    private static let resetItem = NSToolbarItem.Identifier("narly.resetPickerSize")

    init(preferences: DestinationPreferences) {
        self.preferences = preferences
        session = Self.previewSession(preferences: preferences)
        host = PickerHostingView(rootView: PickerView(session: session, contentChanged: {}, isPreview: true))
        let glass = PickerGlassView()
        glass.style = .regular
        glass.cornerRadius = 12
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 12
        glass.layer?.masksToBounds = true
        glass.contentView = host
        surface = PickerSurfaceView(glass: glass)
        layout = PickerSizeWindowLayout(surfaceChromeHeight: surface.fittingSize.height - session.pickerSize.height(for: session.destinations.count))
        // Measure natural content before disabling its automatic window limits.
        // AppKit owns resizing after this initial measurement.
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: layout.contentSize(for: session.pickerSize)),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = L10n.text("Resize link picker")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .canJoinAllApplications]
        window.setAccessibilityIdentifier("picker-size-window")
        super.init(window: window)
        window.delegate = self
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.contentMinSize = layout.contentSize(for: .minimum)
        window.contentMaxSize = layout.contentSize(for: PickerSize(width: PickerSize.widthRange.upperBound, rows: PickerSize.rowRange.upperBound))
        configureContent(in: window)
        let toolbar = NSToolbar(identifier: "narly.pickerSize")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbarStyle = .unifiedCompact
        window.toolbar = toolbar
        window.setContentSize(layout.contentSize(for: session.pickerSize))
        isUpdatingSize = false
    }

    required init?(coder: NSCoder) { nil }

    static func previewSession(preferences: DestinationPreferences) -> PickerSession {
        var destinations = preferences.visibleDestinations.filter { $0.isWebBrowser || $0.applicationURL != nil }
        while destinations.count < PickerSize.rowRange.upperBound {
            let index = destinations.count + 1
            destinations.append(Destination(id: "narly-preview-\(index)", name: L10n.format("Example app %ld", index), applicationURL: nil))
        }
        let session = PickerSession(destinations: destinations, opener: PreviewOpener(), displayMode: .custom,
                                    customPickerSize: preferences.pickerSize)
        if let url = URL(string: "https://example.com") { session.receive([url]) }
        return session
    }

    private func configureContent(in window: NSWindow) {
        guard let content = window.contentView else { return }
        let instruction = NSTextField(wrappingLabelWithString: L10n.text("Drag the window edges to set the link picker’s size, then click Save."))
        instruction.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        instruction.textColor = .secondaryLabelColor
        instruction.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let cancel = NSButton(title: L10n.text("Cancel"), target: self, action: #selector(cancelEditing))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.setAccessibilityIdentifier("cancel-picker-size")
        let save = NSButton(title: L10n.text("Save"), target: self, action: #selector(saveEditing))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.setAccessibilityIdentifier("save-picker-size")
        window.defaultButtonCell = save.cell as? NSButtonCell
        for view in [instruction, surface, cancel, save] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            instruction.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            instruction.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            instruction.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            instruction.heightAnchor.constraint(equalToConstant: 32),
            surface.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            surface.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            surface.topAnchor.constraint(equalTo: content.topAnchor, constant: PickerSizeWindowLayout.headerHeight),
            surface.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -PickerSizeWindowLayout.footerHeight),
            save.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            save.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            save.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            cancel.trailingAnchor.constraint(equalTo: save.leadingAnchor, constant: -8),
            cancel.centerYAnchor.constraint(equalTo: save.centerYAnchor),
            cancel.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])
    }

    func present(relativeTo parent: NSWindow?) {
        guard let window else { return }
        if !window.isVisible {
            let visibleFrame = parent?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
            var frame = window.frame
            frame.origin = CGPoint(x: (parent?.frame.midX ?? visibleFrame.midX) - frame.width / 2,
                                   y: (parent?.frame.midY ?? visibleFrame.midY) - frame.height / 2)
            frame.origin.x = max(visibleFrame.minX, min(frame.minX, visibleFrame.maxX - frame.width))
            frame.origin.y = max(visibleFrame.minY, min(frame.minY, visibleFrame.maxY - frame.height))
            window.setFrame(frame, display: false)
        }
        window.makeKeyAndOrderFront(nil)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window, let content = window.contentView else { return }
        // Let AppKit handle continuous edge dragging and its resize cursors.
        // Snapping every proposal to a whole row rejects small height changes.
        let size = layout.pickerSize(for: content.bounds.size)
        let oldFrame = window.frame
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: layout.contentSize(for: size)))
        frame.origin = CGPoint(x: oldFrame.minX, y: oldFrame.maxY - frame.height)
        window.setFrame(frame, display: true)
        updateDraft(size)
    }

    func windowDidResize(_ notification: Notification) {
        guard !isUpdatingSize, let content = window?.contentView else { return }
        updateDraft(layout.pickerSize(for: content.bounds.size))
    }

    private func updateDraft(_ size: PickerSize) {
        guard size != session.customPickerSize else { return }
        session.customPickerSize = size
        host.rootView = PickerView(session: session, contentChanged: {}, isPreview: true)
        surface.needsLayout = true
    }

    @objc func resetSize() {
        guard let window else { return }
        isUpdatingSize = true
        updateDraft(.standard)
        let oldFrame = window.frame
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: layout.contentSize(for: .standard)))
        frame.origin = CGPoint(x: oldFrame.minX, y: oldFrame.maxY - frame.height)
        window.setFrame(frame, display: true)
        isUpdatingSize = false
    }

    @objc func cancelEditing() { close() }
    @objc func saveEditing() {
        preferences.savePickerSize(session.pickerSize)
        close()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.resetItem]
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.resetItem]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard identifier == Self.resetItem else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = L10n.text("Reset size")
        item.toolTip = item.label
        item.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: item.label)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular, scale: .medium))
        item.target = self
        item.action = #selector(resetSize)
        item.isBordered = true
        return item
    }
}

struct PickerSizeWindowLayout {
    static let headerHeight: CGFloat = 52
    static let footerHeight: CGFloat = 60
    let surfaceChromeHeight: CGFloat
    private var verticalInset: CGFloat { surfaceChromeHeight + Self.headerHeight + Self.footerHeight }

    func contentSize(for size: PickerSize) -> CGSize {
        CGSize(width: size.width + 72, height: CGFloat(size.rows) * 32 + verticalInset)
    }
    func pickerSize(for contentSize: CGSize) -> PickerSize {
        let rows = min(max((contentSize.height - verticalInset) / 32, CGFloat(PickerSize.rowRange.lowerBound)),
                       CGFloat(PickerSize.rowRange.upperBound))
        return PickerSize(width: contentSize.width - 72, rows: Int(rows.rounded()))
    }
}

@MainActor
private struct PreviewOpener: DestinationOpening {
    func open(_ url: URL, in destination: Destination) async throws {}
}
