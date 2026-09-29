import SwiftUI

struct SettingsGeneralView: View {
    let preferences: DestinationPreferences
    let defaultBrowser: DefaultBrowserSettings
    let loginItem: LoginItemSettings
    let introduction: IntroductionState
    let customizeSize: () -> Void

    var body: some View {
        if introduction.isVisible { IntroductionView(state: introduction) }

        Section {
            LabeledContent(L10n.text("Default browser")) {
                if defaultBrowser.isDefault {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(AppInformation.name).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.text("Narly is your default browser"))
                } else {
                    Button(defaultBrowser.isChanging ? L10n.text("Waiting for macOS…") : L10n.text("Set as default browser"),
                           action: makeDefault)
                        .disabled(defaultBrowser.isChanging || !defaultBrowser.isInstalled)
                        .accessibilityIdentifier("make-default-browser")
                }
            }
            if !defaultBrowser.isDefault, let message = defaultBrowserMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("default-browser-result")
            }

            Toggle(L10n.text("Open at login"), isOn: Binding(
                get: { loginItem.isRequested }, set: { setLoginEnabled($0) }
            ))
            .disabled(loginItem.isChanging || !defaultBrowser.isInstalled)
            .accessibilityIdentifier("launch-at-login")

            if loginItem.status == .requiresApproval || loginItem.errorMessage != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text(loginItem.errorMessage ?? loginItem.description)
                        .font(.callout).foregroundStyle(.secondary)
                    Button(L10n.text("Open System Settings…"), action: loginItem.openSystemSettings)
                }
            } else if loginItem.status == .notFound, defaultBrowser.isInstalled {
                Text(loginItem.description).font(.callout).foregroundStyle(.secondary)
            }

            Toggle(L10n.text("Show Narly in the menu bar"), isOn: Binding(
                get: { preferences.showsMenuBarIcon }, set: { preferences.setShowsMenuBarIcon($0) }
            ))
            .accessibilityIdentifier("show-menu-bar-icon")
        } header: {
            Text(L10n.text("General"))
        } footer: {
            Text(L10n.text(preferences.showsMenuBarIcon
                ? "Narly opens your links even when the menu bar icon is hidden."
                : "Open Narly from Applications or Spotlight to access settings."))
        }
        .toggleStyle(.switch)

        Section {
            Picker(L10n.text("Layout"), selection: Binding(
                get: { preferences.pickerLayout }, set: { preferences.setPickerLayout($0) }
            )) {
                ForEach(PickerLayout.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("picker-layout")

            if preferences.pickerLayout == .list {
                Picker(L10n.text("Window size"), selection: Binding(
                    get: { preferences.pickerMode }, set: { setPickerMode($0) }
                )) {
                    ForEach(PickerDisplayMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("picker-display-mode")

                if preferences.pickerMode == .custom {
                    LabeledContent(L10n.text("Custom size")) {
                        Button(L10n.text("Resize…"), action: customizeSize)
                            .accessibilityIdentifier("customize-picker-size")
                    }
                }
            }

            Picker(L10n.text("Preselected browser"), selection: Binding(
                get: { preferences.availableBrowsers.contains(where: { $0.id == preferences.preferredID }) ? preferences.preferredID ?? "" : "" },
                set: { preferences.setPreferred($0.isEmpty ? nil : $0) }
            )) {
                Text(L10n.text("First available app")).tag("")
                ForEach(preferences.availableBrowsers) { Text($0.name).tag($0.id) }
            }
            .accessibilityIdentifier("preferred-browser")
        } header: {
            Text(L10n.text("Link picker"))
        } footer: {
            Text(sizeDescription)
        }
        .pickerStyle(.menu)
    }

    private var defaultBrowserMessage: String? {
        if !defaultBrowser.isInstalled {
            return L10n.text("Open Narly from the Applications folder to set it as your default browser.")
        }
        return defaultBrowser.message ?? (defaultBrowser.hasPartialSelection
            ? L10n.text("Narly is set as the default for only some web links. Try again to finish setup.") : nil)
    }

    private var sizeDescription: String {
        if preferences.pickerLayout == .horizontal {
            return L10n.text("Horizontal shows all your apps in one row. Use the left and right arrow keys to choose an app.")
        }
        return switch preferences.pickerMode {
        case .full: L10n.text("Standard window size shows up to 10 apps. Scroll to see more.")
        case .compact: L10n.text("Compact window size shows up to 5 apps. Scroll to see more.")
        case .custom: L10n.text("Custom window size lets you resize the picker. Scroll to see more apps.")
        }
    }

    private func makeDefault() { Task { await defaultBrowser.makeDefault() } }
    private func setLoginEnabled(_ enabled: Bool) { Task { await loginItem.setEnabled(enabled) } }
    private func setPickerMode(_ mode: PickerDisplayMode) {
        if mode == .custom { customizeSize() }
        else { preferences.setPickerMode(mode) }
    }
}
