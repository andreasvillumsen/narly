import SwiftUI
import AppKit

@MainActor
struct PickerView: View {
    let session: PickerSession
    let contentChanged: () -> Void
    var isPreview = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @State private var lastPointerLocation = NSEvent.mouseLocation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = session.rejectionMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("queue-rejection-notice")
                    Button(L10n.text("Dismiss"), action: session.dismissRejectionNotice)
                        .buttonStyle(.link)
                        .accessibilityIdentifier("dismiss-queue-notice")
                }
                .padding(8)
            }

            if isPreview || session.current != nil {
                VStack(spacing: 0) {
                    if !isPreview && !session.destinations.contains(where: { session.canOpen($0) }) {
                        Text(L10n.text("No available apps can open this link. Copy it, or check Browsers and apps in Narly’s settings."))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true).padding(8)
                    }
                    if session.layout == .horizontal {
                        horizontalApps
                    } else {
                        PickerRowsScrollView(rowCount: session.destinations.count,
                                             selectedIndex: session.searchScrollIndex,
                                             requestID: session.current?.id, mode: session.displayMode,
                                             visibleRows: session.pickerSize.rows) {
                            VStack(spacing: 0) {
                                ForEach(Array(session.destinations.enumerated()), id: \.element.id) { index, destination in
                                    destinationRow(destination, index: index)
                                }
                            }
                        }
                        .frame(height: session.pickerSize.height(for: session.destinations.count))
                    }
                }
            }

            if session.isOpening {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.text("Opening link…")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if session.isResolving {
                        Button(L10n.text("Cancel"), action: session.cancelResolution)
                            .controlSize(.small)
                            .accessibilityIdentifier("cancel-link-lookup")
                    }
                }
                .padding(.horizontal, 8)
            }

            if let error = session.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .accessibilityIdentifier("picker-error")
            }
        }
        .padding(6)
        .frame(width: session.contentWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: session.layout.cornerRadius).fill(Color(nsColor: .windowBackgroundColor))
            }
        }
        .overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: session.layout.cornerRadius).strokeBorder(.primary, lineWidth: 1)
                    .allowsHitTesting(false)
            } else if colorScheme == .light {
                // Keep the clipped glass surface distinct from white backgrounds.
                RoundedRectangle(cornerRadius: session.layout.cornerRadius)
                    .strokeBorder(Color.black.opacity(0.16), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in proxy.size } action: { _ in
            // State changes can precede NSHostingView's new fitting size. Resize after layout too.
            contentChanged()
        }
        .onChange(of: session.current?.id) {
            lastPointerLocation = NSEvent.mouseLocation
            contentChanged()
        }
        .onChange(of: session.rejectionNotice) { contentChanged() }
        .onChange(of: session.errorMessage) { contentChanged() }
        .onChange(of: session.destinations) { contentChanged() }
        .onChange(of: session.layout) {
            lastPointerLocation = NSEvent.mouseLocation
            contentChanged()
        }
        .onChange(of: session.displayMode) { contentChanged() }
        .onChange(of: session.customPickerSize) { contentChanged() }
        .onChange(of: session.isOpening) { contentChanged() }
    }

    private func destinationRow(_ destination: Destination, index: Int) -> some View {
        let available = isPreview || session.canOpen(destination)
        let selected = index == session.selectedIndex && available
        return Button {
            guard !isPreview else { return }
            Task { await session.choose(index: index) }
        } label: {
            Group {
                if session.layout == .horizontal {
                    PickerAppIcon(destination: destination, shortcut: session.shortcutHint(at: index),
                                  name: displayName(for: destination), showsAppShortcuts: session.showsAppShortcuts,
                                  isSelected: selected, isAvailable: available)
                } else {
                    destinationListLabel(destination, index: index)
                }
            }
            .foregroundStyle(Color.primary)
            .contentShape(Rectangle())
            .background {
                if session.layout == .list {
                    PickerSelectionMaterial(isSelected: selected, cornerRadius: 6)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!available || session.isOpening)
        .help(available ? destination.name : unavailableReason(for: destination))
        .onContinuousHover { phase in
            guard case .active = phase else { return }
            let location = NSEvent.mouseLocation
            // Opening or scrolling beneath a stationary pointer must not override
            // the preferred app or the keyboard selection.
            guard location != lastPointerLocation else { return }
            lastPointerLocation = location
            if available { session.highlight(index: index) }
        }
        .accessibilityLabel(isPreview ? destination.name : L10n.format("Open in %@", destination.name))
        .accessibilityValue(isPreview ? "" : (!available ? unavailableReason(for: destination) : (selected ? L10n.text("Selected. Press Return to open the link.") : (index < 9 ? L10n.format("Press %ld to open the link.", index + 1) : ""))))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("destination-\(destination.id)")
        .accessibilityHint(session.appShortcuts[destination.id].map {
            L10n.format("Option-%@ opens the link in this app.", AppShortcut.displayKey($0))
        } ?? "")
    }

    private func unavailableReason(for destination: Destination) -> String {
        destination.applicationURL == nil ? L10n.text("Not installed")
            : L10n.format("Can’t open this link in %@.", destination.name)
    }

    private func destinationListLabel(_ destination: Destination, index: Int) -> some View {
        HStack(spacing: 8) {
            if let url = destination.applicationURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: "globe").font(.system(size: 18))
                    .frame(width: 20, height: 20).foregroundStyle(.secondary)
            }
            HStack(spacing: 5) {
                Text(displayName(for: destination)).font(.body).lineLimit(1)
                if destination.applicationURL == nil && !isPreview {
                    Text(L10n.text("Not installed"))
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if let hint = session.shortcutHint(at: index) {
                Text(hint)
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 16)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 8)
        .frame(height: 32)
    }

    private var horizontalApps: some View {
        HStack(spacing: HorizontalPickerMetrics.spacing) {
            ForEach(Array(session.destinations.enumerated()), id: \.element.id) { index, destination in
                destinationRow(destination, index: index)
            }
        }
        .fixedSize()
        .frame(maxWidth: .infinity)
        .frame(height: session.destinations.isEmpty ? 0 : HorizontalPickerMetrics.itemHeight)
    }

    private func displayName(for destination: Destination) -> AttributedString {
        var name = AttributedString(destination.name)
        for match in session.matchedNameRanges(for: destination) {
            if let start = AttributedString.Index(match.lowerBound, within: name),
               let end = AttributedString.Index(match.upperBound, within: name) {
                name[start..<end].inlinePresentationIntent = .stronglyEmphasized
            }
        }
        return name
    }
}
