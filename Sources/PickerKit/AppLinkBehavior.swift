import SwiftUI

public enum AppLinkBehavior: String, CaseIterable, Sendable {
    case ask, app, browser

    var title: String {
        switch self {
        case .ask: L10n.text("Ask every time")
        case .app: L10n.text("Open in app")
        case .browser: L10n.text("Open in browser")
        }
    }

    func route(optionHeld: Bool) -> Self {
        optionHeld ? .ask : self
    }
}
