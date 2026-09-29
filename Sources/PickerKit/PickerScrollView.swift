import AppKit
import SwiftUI

/// Own only the scroll container: AppKit provides the thin overlay scroller,
/// while SwiftUI still owns rows, selection styling and actions.
struct PickerRowsScrollView<Content: View>: NSViewRepresentable {
    let rowCount: Int
    let selectedIndex: Int
    let requestID: UUID?
    let mode: PickerDisplayMode
    var visibleRows: Int = 10
    @ViewBuilder var content: Content

    func makeNSView(context: Context) -> PickerNativeScrollView<Content> {
        PickerNativeScrollView(content: content)
    }

    func updateNSView(_ view: PickerNativeScrollView<Content>, context: Context) {
        view.host.rootView = content
        view.rowCount = rowCount
        let selection = PickerScrollSelection(index: selectedIndex, request: requestID, mode: mode, count: rowCount,
                                              visibleRows: visibleRows)
        if view.selection != selection {
            view.selection = selection
            view.revealSelectionOnLayout = true
        }
        view.needsLayout = true
    }
}

struct PickerScrollSelection: Equatable {
    let index: Int
    let request: UUID?
    let mode: PickerDisplayMode
    let count: Int
    var visibleRows: Int = 10
}

@MainActor
final class PickerNativeScrollView<Content: View>: NSScrollView {
    let host: NSHostingView<Content>
    var rowCount = 0
    var selection: PickerScrollSelection?
    var revealSelectionOnLayout = false

    init(content: Content) {
        host = NSHostingView(rootView: content)
        super.init(frame: .zero)
        drawsBackground = false
        contentView.drawsBackground = false
        borderType = .noBorder
        hasHorizontalScroller = false
        hasVerticalScroller = true
        scrollerStyle = .overlay
        verticalScroller?.controlSize = .small
        autohidesScrollers = true
        horizontalScrollElasticity = .none
        verticalScrollElasticity = .automatic
        host.sizingOptions = []
        documentView = host
        setAccessibilityIdentifier("picker-app-scroll")
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        host.frame = NSRect(x: 0, y: 0, width: contentSize.width, height: CGFloat(rowCount) * 32)
        if revealSelectionOnLayout, let selection, (0..<rowCount).contains(selection.index) {
            // NSHostingView's document coordinates are flipped: row zero is at the top.
            host.scrollToVisible(NSRect(x: 0, y: CGFloat(selection.index) * 32,
                                        width: host.bounds.width, height: 32))
            revealSelectionOnLayout = false
        }
    }
}
