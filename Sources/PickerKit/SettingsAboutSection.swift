import AppKit
import SwiftUI

struct SettingsAboutSection: View {
    let updates: SettingsUpdates
    let preferences: DestinationPreferences

    var body: some View {
        Section {
            VStack(spacing: 10) {
                NarlyBrandImage(size: 64)
                Text(AppInformation.name).font(.title2).bold()
                Text(L10n.text("Your links. The right place.")).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }

        Section {
            SettingsUpdateRow(updates: updates, preferences: preferences)

            DisclosureGroup(L10n.text("Help")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("Type an app name to find an app. Press Return to open the link in the selected app. Use ↑ and ↓ to change the selection, or 1–9 to open a link in an app when you aren’t searching. ⌘C copies the link. Escape clears your search. If the search is empty, it closes the picker."))
                    Text(L10n.text("If an app can’t open a link, choose a browser. To stop using Narly for links, choose another default browser in System Settings."))
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.vertical, 4)
            }

            DisclosureGroup(L10n.text("Privacy")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("Narly does not collect usage analytics or save link history to disk. Settings and technical logs stay on your Mac. Logs contain no links, domains or window titles and are not uploaded. Pending and dismissed links stay in memory temporarily."))
                    Text(L10n.text("Links are passed to the app you choose. Narly makes no network requests to resolve them. The selected app and websites you open have their own privacy practices."))
                    Text(L10n.text("When you check for updates, Narly contacts GitHub to read the latest public release. GitHub receives your IP address. Your links and app preferences are not sent."))
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.vertical, 4)
            }
        } header: {
            Text(L10n.text("About Narly"))
        } footer: {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(L10n.text("Send feedback to"))
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Link(destination: URL(string: "mailto:hello@narlymac.app")!) {
                        Text("hello@narlymac.app")
                            .bold()
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .tint(Color(nsColor: .secondaryLabelColor))
                    Text(".")
                }
                .fixedSize()
            }
            .font(.caption)
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
        .disclosureGroupStyle(SettingsDisclosureStyle())
    }

}

private struct SettingsDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack {
                    configuration.label
                    Spacer()
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(L10n.text(configuration.isExpanded ? "Expanded" : "Collapsed"))

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}
