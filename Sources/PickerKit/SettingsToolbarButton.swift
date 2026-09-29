import AppKit

/// AppKit owns interaction and toolbar selection; the content stays neutral.
@MainActor
final class SettingsToolbarButton: NSButton {
    let pane: SettingsPane

    init(pane: SettingsPane) {
        self.pane = pane
        super.init(frame: NSRect(x: 0, y: 0, width: 76, height: 56))
        cell = SettingsToolbarButtonCell(textCell: pane.title)
        setButtonType(.momentaryChange)
        isBordered = false
        imagePosition = .imageAbove
        imageScaling = .scaleProportionallyDown
        title = pane.title
        setAccessibilityLabel(pane.title)
        setAccessibilityIdentifier("settings-tab-\(pane.rawValue)")
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(76, attributedTitle.size().width + 24), height: 56)
    }

    func updateSelection(_ selected: Bool) {
        state = selected ? .on : .off
        let color: NSColor = selected ? .labelColor : .secondaryLabelColor
        contentTintColor = color
        attributedTitle = NSAttributedString(string: pane.title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: selected ? .semibold : .regular),
            .foregroundColor: color
        ])
        image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 21, weight: selected ? .semibold : .regular))
        setAccessibilityValue(selected ? 1 : 0)
    }
}

/// Keep native button rendering while separating the icon and its caption.
private final class SettingsToolbarButtonCell: NSButtonCell {
    override func imageRect(forBounds rect: NSRect) -> NSRect {
        super.imageRect(forBounds: rect).offsetBy(dx: 0, dy: controlView?.isFlipped == true ? 6 : -6)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        super.titleRect(forBounds: rect).offsetBy(dx: 0, dy: controlView?.isFlipped == true ? 5 : -5)
    }
}
