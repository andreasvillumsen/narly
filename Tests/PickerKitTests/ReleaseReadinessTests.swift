import AppKit
import ServiceManagement
import Testing
@testable import PickerKit

@MainActor private final class LoginHandlerSpy: LoginItemHandling {
    var status: SMAppService.Status = .notRegistered
    var registrations = 0
    var removals = 0
    var registrationStatus: SMAppService.Status = .enabled
    var fails = false
    func register() throws {
        registrations += 1
        if fails { throw CocoaError(.fileWriteNoPermission) }
        status = registrationStatus
    }
    func unregister() async throws {
        removals += 1
        if fails { throw CocoaError(.fileWriteNoPermission) }
        status = .notRegistered
    }
}

@Suite @MainActor struct ReleaseReadinessTests {
    @Test func loginStateIsReadWithoutRegisteringAndRequiresAnExplicitChoice() async {
        let handler = LoginHandlerSpy()
        let settings = LoginItemSettings(handler: handler)
        settings.refresh()
        #expect(!settings.isRequested)
        #expect(handler.registrations == 0)
        await settings.setEnabled(true)
        #expect(settings.status == .enabled)
        #expect(handler.registrations == 1)
        await settings.setEnabled(false)
        #expect(settings.status == .notRegistered)
        #expect(handler.removals == 1)
    }

    @Test func loginApprovalAndFailureDoNotClaimEnabled() async {
        let handler = LoginHandlerSpy()
        handler.registrationStatus = .requiresApproval
        let settings = LoginItemSettings(handler: handler)
        await settings.setEnabled(true)
        #expect(settings.status == .requiresApproval)
        #expect(settings.isRequested)
        handler.fails = true
        await settings.setEnabled(false)
        #expect(settings.status == .requiresApproval)
        #expect(settings.errorMessage != nil)
        handler.status = .notRegistered
        settings.refresh()
        #expect(!settings.isRequested)
    }

    @Test func introductionCompletesAndCanBeRevisitedWithoutResettingStoredChoice() throws {
        let suite = "narly-intro-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let introduction = IntroductionState(defaults: defaults)
        #expect(introduction.isVisible)
        introduction.complete()
        #expect(!IntroductionState(defaults: defaults).isVisible)
        introduction.show()
        #expect(introduction.isVisible)
        #expect(!IntroductionState(defaults: defaults).isVisible)
    }

    @Test func loginAppleEventNeverOpensSettingsOrIntroduction() {
        let event = NSAppleEventDescriptor(eventClass: kCoreEventClass, eventID: kAEOpenApplication,
                                          targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem), forKeyword: keyAEPropData)
        #expect(LaunchPresentation.isLoginLaunch(event: event))
        #expect(!LaunchPresentation.shouldShowSettings(isDefaultLaunch: true, hasPendingLinks: false, isLoginLaunch: true))
        #expect(!LaunchPresentation.shouldShowSettings(isDefaultLaunch: true, hasPendingLinks: true))
        #expect(LaunchPresentation.shouldShowSettings(isDefaultLaunch: true, hasPendingLinks: false))
        #expect(!LaunchPresentation.isLoginLaunch(event: nil))
    }

    @Test func explicitReopenProvidesSettingsRecoveryWithoutInterruptingLinks() {
        let reopen = NSAppleEventDescriptor(eventClass: kCoreEventClass, eventID: kAEReopenApplication,
                                           targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        let link = NSAppleEventDescriptor(eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL),
                                         targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        #expect(LaunchPresentation.shouldShowSettingsOnReopen(event: reopen, hasPendingLinks: false))
        #expect(!LaunchPresentation.shouldShowSettingsOnReopen(event: reopen, hasPendingLinks: true))
        #expect(!LaunchPresentation.shouldShowSettingsOnReopen(event: link, hasPendingLinks: false))
        #expect(!LaunchPresentation.shouldShowSettingsOnReopen(event: nil, hasPendingLinks: false))
    }

    @Test func longListNavigationSkipsUnsupportedDestinationsAndWraps() throws {
        var destinations = (0..<15).map { Destination(id: "browser-\($0)", name: "Browser \($0)", applicationURL: URL(fileURLWithPath: "/Browser.app")) }
        destinations.insert(Destination(id: "linear", name: "Linear", applicationURL: URL(fileURLWithPath: "/Linear.app"), appLink: .linear), at: 1)
        let session = PickerSession(destinations: destinations, opener: WorkspaceDestinationOpener())
        session.receive([try #require(URL(string: "https://example.com"))])
        session.move(1)
        #expect(session.selectedIndex == 2)
        session.move(-1)
        #expect(session.selectedIndex == 0)
        session.move(-1)
        #expect(session.selectedIndex == 15)
        session.highlight(index: 1)
        #expect(session.selectedIndex == 15)
        session.move(1)
        #expect(session.selectedIndex == 0)
    }
}
