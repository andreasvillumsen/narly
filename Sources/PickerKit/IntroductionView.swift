import SwiftUI

struct IntroductionView: View {
    let state: IntroductionState

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    NarlyBrandImage(size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("Welcome to Narly")).font(.title2).bold()
                        Text(L10n.text("Your links. The right place.")).foregroundStyle(.secondary)
                    }
                }
                Text(L10n.text("Narly lets you choose which browser or app opens links from other apps."))
                Label(L10n.text("Set Narly as your default browser to start choosing where links open."), systemImage: "globe")
                Label(L10n.text("Drag your favourite apps to the top of the list."), systemImage: "line.3.horizontal")
                Label(L10n.text("Open Narly from Applications or Spotlight to find settings and help."), systemImage: "menubar.rectangle")
                Text(L10n.text("To switch back, choose another default browser in System Settings."))
                    .font(.callout).foregroundStyle(.secondary)
                Button(L10n.text("Continue")) { state.complete() }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("complete-introduction")
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("narly-introduction")
        }
    }
}
