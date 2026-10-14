import Foundation
import Observation

@MainActor @Observable
final class SettingsUpdates {
    enum State: Equatable {
        case idle, checking, finished(UpdateCheckResult), failed
    }

    private(set) var state: State = .idle
    private(set) var isOpening = false
    private(set) var openingError: String?
    @ObservationIgnored private let checker: UpdateChecker
    @ObservationIgnored private let currentVersion: String
    @ObservationIgnored private let opener: any DestinationOpening

    init(checker: UpdateChecker = UpdateChecker(), currentVersion: String = AppInformation.version,
         opener: any DestinationOpening = WorkspaceDestinationOpener()) {
        self.checker = checker
        self.currentVersion = currentVersion
        self.opener = opener
    }

    var availableUpdate: AvailableUpdate? {
        guard case .finished(.available(let update)) = state else { return nil }
        return update
    }

    var message: String? {
        switch state {
        case .idle: nil
        case .checking: L10n.text("Checking for updates")
        case .finished(.upToDate): L10n.text("You have the latest version.")
        case .finished(.noPublicRelease): L10n.text("No public release is available yet.")
        case .finished(.available(let update)): L10n.format("Narly %@ is available.", update.version)
        case .failed: L10n.text("Couldn’t check for updates. Try again.")
        }
    }

    /// Construction, launch and Settings presentation never start a network request.
    func check() async {
        guard state != .checking, !isOpening else { return }
        state = .checking
        openingError = nil
        do {
            state = .finished(try await checker.check(currentVersion: currentVersion))
        } catch {
            state = .failed
        }
    }

    func openUpdate(in browser: Destination) async {
        guard let update = availableUpdate, !isOpening else { return }
        isOpening = true
        openingError = nil
        defer { isOpening = false }
        do {
            guard browser.isWebBrowser, !DestinationPolicy.isRecursive(browser.id)
            else { throw DestinationOpenError.recursiveDestination }
            try await opener.open(update.releaseURL, in: browser)
        } catch {
            // Keep the release and browser/copy recovery available after a failed dispatch.
            openingError = L10n.format("Couldn’t open the link in %@. Choose a browser or copy the link.", browser.name)
        }
    }
}
