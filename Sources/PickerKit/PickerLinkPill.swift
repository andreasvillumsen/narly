import SwiftUI

/// A compact copy target above either picker layout. Its reported bounds
/// include only the capsule, so the surrounding transparent slot dismisses normally.
struct PickerLinkPill: View {
    let link: PendingLink
    let queuedCount: Int
    let isOpening: Bool
    let copy: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 8) {
                Text(link.displayName)
                    .lineLimit(1).truncationMode(.middle)
                if queuedCount > 1 {
                    Text(L10n.format("%ld links", queuedCount))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .frame(height: PickerPanelContent.linkHeight)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isOpening)
        .background {
            if reduceTransparency {
                Capsule().fill(Color(nsColor: .windowBackgroundColor))
            }
        }
        .glassEffect(.regular.interactive(), in: Capsule())
        .overlay {
            if contrast == .increased {
                Capsule().strokeBorder(.primary, lineWidth: 1).allowsHitTesting(false)
            }
        }
        .help(link.url.absoluteString)
        .accessibilityLabel(L10n.text("Copy link"))
        .accessibilityValue(link.displayName)
        .accessibilityIdentifier("copy-link")
    }
}
