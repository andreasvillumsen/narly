import AppKit
import SwiftUI

struct SettingsDestinationsView: View {
    let preferences: DestinationPreferences
    let addApplication: () -> Void
    @State private var dragPreview: AppReorderPreview?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rows: [Destination] { preferences.installedSettingsDestinations }
    private func previewOffset(for id: String) -> CGFloat {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return 0 }
        return dragPreview?.offset(for: index) ?? 0
    }

    var body: some View {
        Section {
            if rows.isEmpty {
                Text(L10n.text("No installed apps found. Add an app to open your links."))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    DestinationColumns {
                        Text(L10n.text("App"))
                    } shortcut: {
                        Text(L10n.text("Shortcut"))
                    } opening: {
                        Text(L10n.text("Open links"))
                            .padding(.leading, 12)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                    .accessibilityHidden(true)

                    ForEach(rows) { destination in
                        DestinationSettingsRow(destination: destination, preferences: preferences,
                                           dragPreview: $dragPreview)
                            .overlay(alignment: .bottom) {
                                if destination.id != rows.last?.id { Divider().padding(.leading, 56) }
                            }
                            .offset(y: previewOffset(for: destination.id))
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: previewOffset(for: destination.id))
                            .zIndex(dragPreview?.id == destination.id ? 1 : 0)
                    }
                }
            }
            HStack {
                Button(action: addApplication) { Label(L10n.text("Add app…"), systemImage: "plus") }
                    .accessibilityIdentifier("add-application")
                Spacer()
            }
            .buttonStyle(.bordered)
        } header: {
            Text(L10n.text("Browsers and apps"))
        } footer: {
            Text(L10n.text("Drag to reorder. Uncheck an app to hide it from the picker."))
        }

        if preferences.availableBrowsers.isEmpty {
            Section {
                Text(L10n.text("No browsers are available. Enable an installed browser above, or add a browser."))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The header and every row share the same control columns; names take the remaining space.
private struct DestinationColumns<AppContent: View, Shortcut: View, Opening: View>: View {
    @ViewBuilder let app: AppContent
    @ViewBuilder let shortcut: Shortcut
    @ViewBuilder let opening: Opening

    var body: some View {
        HStack(spacing: 16) {
            app.frame(maxWidth: .infinity, alignment: .leading)
            shortcut.frame(width: 64, alignment: .trailing)
            opening.frame(width: 164, alignment: .leading)
        }
        .padding(.horizontal, 6)
    }
}

private struct DestinationSettingsRow: View {
    let destination: Destination
    let preferences: DestinationPreferences
    @Binding var dragPreview: AppReorderPreview?
    @GestureState private var dragOffset: CGFloat = 0

    private func preview(for translation: CGFloat) -> AppReorderPreview? {
        let order = preferences.installedSettingsDestinations
        guard let source = order.firstIndex(where: { $0.id == destination.id }) else { return nil }
        return AppReorderPreview(id: destination.id, source: source, count: order.count, translation: translation)
    }

    var body: some View {
        DestinationColumns {
            appIdentity
        } shortcut: {
            HotkeyRecorder(destination: destination, preferences: preferences)
        } opening: {
            linkOpening
        }
        .frame(height: AppReorderPreview.rowHeight)
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($dragOffset) { value, offset, _ in offset = value.translation.height }
            .onChanged { value in
                guard let preview = preview(for: value.translation.height) else { return }
                if dragPreview != preview { dragPreview = preview }
            }
            .onEnded { value in
                guard let preview = preview(for: value.translation.height) else { return }
                let order = preferences.installedSettingsDestinations
                dragPreview = nil
                if preview.destination != preview.source {
                    preferences.reorderApp(destination.id, relativeTo: order[preview.destination].id,
                                           after: preview.destination > preview.source)
                }
            })
        .onChange(of: dragOffset) { _, offset in
            if offset == 0, dragPreview?.id == destination.id { dragPreview = nil }
        }
        .background {
            if dragOffset != 0 { Color(nsColor: .controlBackgroundColor) }
        }
        .offset(y: dragOffset)
        .zIndex(dragOffset != 0 ? 1 : 0)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("destination-row-\(destination.id)")
        .contextMenu {
            if preferences.isManuallyAdded(destination.id) {
                Button(L10n.text("Remove from Narly"), role: .destructive) { preferences.removeApplication(destination.id) }
                    .disabled(!preferences.canHide(destination))
            }
        }
    }

    private var appIdentity: some View {
        HStack(spacing: 8) {
            Toggle(L10n.format("Show %@", destination.name), isOn: Binding(
                get: { preferences.isVisible(destination.id) },
                set: { preferences.setVisible($0, id: destination.id) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .frame(width: 16)
            .disabled(!preferences.canHide(destination))
            .help(L10n.text("Show in Link Picker"))
            .accessibilityIdentifier("destination-visible-\(destination.id)")

            if let url = destination.applicationURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().frame(width: 20, height: 20).accessibilityHidden(true)
            }
            Text(destination.name).lineLimit(1)
        }
    }

    @ViewBuilder private var linkOpening: some View {
        if let app = destination.appLink {
            let selection = Binding(
                get: { AppLinkBehavior(rawValue: preferences.appLinkBehaviors[app.rawValue] ?? "") ?? .ask },
                set: { preferences.setAppLinkBehavior($0, for: app) }
            )
            AppLinkBehaviorPicker(app: app, destinationName: destination.name, selection: selection)
        } else {
            Text(L10n.text("Browser"))
                .foregroundStyle(.secondary)
                .padding(.leading, 12) // Match the native pop-up button's title inset.
        }
    }
}
