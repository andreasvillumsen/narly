import AppKit
import SwiftUI

/// Shared native selection treatment for rows and icons. Selection follows
/// the keyboard immediately; AppKit adapts the material to system appearance.
struct PickerSelectionMaterial: View {
    let isSelected: Bool
    let cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        NativePickerSelectionMaterial(isSelected: isSelected, cornerRadius: cornerRadius)
            .overlay {
                if isSelected && contrast == .increased {
                    RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.primary, lineWidth: 1)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// SwiftUI has no selection-material shape style.
private struct NativePickerSelectionMaterial: NSViewRepresentable {
    let isSelected: Bool
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .selection
        view.blendingMode = .withinWindow
        view.state = .active
        view.isEmphasized = false
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.layer?.cornerRadius = cornerRadius
        view.isHidden = !isSelected
    }
}
