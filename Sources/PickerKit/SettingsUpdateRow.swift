import AppKit
import SwiftUI

struct SettingsUpdateRow: View {
    let updates: SettingsUpdates
    let preferences: DestinationPreferences
    @State private var copyMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AppInformation.versionDescription)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                Button(L10n.text("Check for updates")) {
                    copyMessage = nil
                    Task { await updates.check() }
                }
                .disabled(updates.state == .checking || updates.isOpening)
                .accessibilityIdentifier("check-for-updates")
            }
            if let message = updates.message {
                HStack {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("update-check-status")
                    Spacer()
                    if updates.availableUpdate != nil {
                        Menu(L10n.text("View update")) {
                            ForEach(preferences.availableBrowsers.filter { !DestinationPolicy.isRecursive($0.id) }) { browser in
                                Button(L10n.format("Open in %@", browser.name)) {
                                    Task { await updates.openUpdate(in: browser) }
                                }
                            }
                            Divider()
                            Button(L10n.text("Copy link")) { copyUpdateLink() }
                        }
                        .disabled(updates.isOpening)
                        .accessibilityIdentifier("view-update")
                    }
                }
            }
            if let error = updates.openingError {
                Text(error).font(.callout).foregroundStyle(.secondary)
            }
            if let copyMessage {
                Text(copyMessage).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func copyUpdateLink() {
        guard let update = updates.availableUpdate else { return }
        NSPasteboard.general.clearContents()
        copyMessage = L10n.text(NSPasteboard.general.setString(update.releaseURL.absoluteString, forType: .string)
                               ? "Copied" : "Couldn’t copy the link. Try again.")
    }
}
