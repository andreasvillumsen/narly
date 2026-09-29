import AppKit
import SwiftUI

/// A native pop-up button with explicit text alignment inside the shared settings column.
struct AppLinkBehaviorPicker: NSViewRepresentable {
    let app: AppLink
    let destinationName: String
    @Binding var selection: AppLinkBehavior

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.isBordered = true
        button.bezelStyle = .rounded
        button.alignment = .left
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectBehavior(_:))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        let titles = [L10n.text("Show link picker"), L10n.format("Open in %@", destinationName),
                      L10n.text("Open in browser")]
        if button.itemTitles != titles {
            button.removeAllItems()
            button.addItems(withTitles: titles)
        }
        button.selectItem(at: AppLinkBehavior.allCases.firstIndex(of: selection) ?? 0)
        button.toolTip = L10n.text("Hold ⌥ to choose each time.")
        button.setAccessibilityLabel(L10n.format("Open links for %@", destinationName))
        button.setAccessibilityIdentifier("app-link-behavior-\(app.rawValue)")
    }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<AppLinkBehavior>

        init(selection: Binding<AppLinkBehavior>) { self.selection = selection }

        @objc func selectBehavior(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard AppLinkBehavior.allCases.indices.contains(index) else { return }
            selection.wrappedValue = AppLinkBehavior.allCases[index]
        }
    }
}
