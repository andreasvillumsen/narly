import AppKit
import SwiftUI

/// The selected app's name replaces its numeric hint in the same caption slot.
/// Holding Option reveals app shortcuts without changing the tile's geometry.
struct PickerAppIcon: View {
    let destination: Destination
    let shortcut: String?
    let name: AttributedString
    let showsAppShortcuts: Bool
    let isSelected: Bool
    let isAvailable: Bool

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let url = destination.applicationURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                } else {
                    Image(systemName: "globe").resizable().foregroundStyle(.secondary)
                }
            }
            .scaledToFit()
            .frame(width: HorizontalPickerMetrics.iconSize, height: HorizontalPickerMetrics.iconSize)
            .opacity(isAvailable ? 1 : 0.4)
            .frame(width: HorizontalPickerMetrics.selectionSize, height: HorizontalPickerMetrics.selectionSize)
            .background {
                PickerSelectionMaterial(isSelected: isSelected, cornerRadius: 10)
            }
            Text(isSelected && !showsAppShortcuts ? name : AttributedString(shortcut ?? " "))
                .font(.caption2).monospacedDigit()
                .lineLimit(1).truncationMode(.tail)
                .foregroundStyle(isSelected && !showsAppShortcuts ? .primary : .secondary)
                .opacity(isAvailable ? 1 : 0.4)
                .frame(width: HorizontalPickerMetrics.itemWidth, height: 12)
                .accessibilityHidden(true)
        }
        .frame(width: HorizontalPickerMetrics.itemWidth, height: HorizontalPickerMetrics.itemHeight)
    }
}
