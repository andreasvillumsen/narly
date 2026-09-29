import AppKit
import Observation
import SwiftUI

enum SettingsPane: String, CaseIterable {
    case general, apps, about

    var title: String {
        switch self {
        case .general: L10n.text("General")
        case .apps: L10n.text("Apps")
        case .about: L10n.text("About")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .apps: "square.grid.2x2"
        case .about: "info.circle"
        }
    }

    var toolbarIdentifier: NSToolbarItem.Identifier { .init("narly.settings.\(rawValue)") }
}

@MainActor @Observable
final class SettingsNavigation {
    var selection: SettingsPane = .general
}

struct SettingsView: View {
    let preferences: DestinationPreferences
    let defaultBrowser: DefaultBrowserSettings
    let loginItem: LoginItemSettings
    let introduction: IntroductionState
    let navigation: SettingsNavigation
    let addApplication: () -> Void
    let customizeSize: () -> Void

    var body: some View {
        Form {
            switch navigation.selection {
            case .general:
                SettingsGeneralView(preferences: preferences, defaultBrowser: defaultBrowser,
                                    loginItem: loginItem, introduction: introduction, customizeSize: customizeSize)
            case .apps:
                SettingsDestinationsView(preferences: preferences, addApplication: addApplication)
            case .about:
                SettingsAboutSection()
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            preferences.refreshInstalledApplications()
            defaultBrowser.refresh()
            loginItem.refresh()
        }
    }
}
