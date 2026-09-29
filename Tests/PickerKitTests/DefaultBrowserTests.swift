import Foundation
import Testing
@testable import PickerKit

@MainActor private final class DefaultHandlerSpy: DefaultBrowserHandling {
    enum Failure: Error { case cancelled }
    var handlers = ["http": "other", "https": "other"]
    var calls: [String] = []
    var failOn: String?
    var applyChange = true
    func handlerID(for scheme: String) -> String? { handlers[scheme] }
    func setDefaultApplication(at url: URL, for scheme: String) async throws {
        calls.append(scheme)
        if failOn == scheme { throw Failure.cancelled }
        if applyChange { handlers[scheme] = "narly" }
    }
}

@Suite @MainActor struct DefaultBrowserTests {
    private func settings(_ spy: DefaultHandlerSpy) -> DefaultBrowserSettings {
        DefaultBrowserSettings(handler: spy, applicationURL: URL(fileURLWithPath: "/Applications/Narly.app"), bundleID: "narly")
    }

    @Test func readingStatusNeverChangesDefaults() {
        let spy = DefaultHandlerSpy()
        spy.handlers["http"] = "narly"
        let model = settings(spy)
        model.refresh()
        #expect(!model.isDefault)
        #expect(model.hasPartialSelection)
        #expect(spy.calls.isEmpty)
    }

    @Test func temporaryBuildCannotBecomeDefaultBrowser() async {
        let spy = DefaultHandlerSpy()
        let model = DefaultBrowserSettings(handler: spy, applicationURL: URL(fileURLWithPath: "/private/tmp/Narly.app"), bundleID: "narly")
        await model.makeDefault()
        #expect(!model.isInstalled)
        #expect(spy.calls.isEmpty)
        #expect(model.message != nil)
    }

    @Test func explicitChoiceSetsBothSchemesAndVerifiesResult() async {
        let spy = DefaultHandlerSpy()
        let model = settings(spy)
        await model.makeDefault()
        #expect(spy.calls == ["http", "https"])
        #expect(model.isDefault)
        #expect(model.message == nil)
        #expect(!model.isChanging)
        await model.makeDefault()
        #expect(spy.calls.count == 2)
    }

    @Test func cancellationStopsWithoutChangingSecondScheme() async {
        let spy = DefaultHandlerSpy()
        spy.failOn = "http"
        let model = settings(spy)
        await model.makeDefault()
        #expect(spy.calls == ["http"])
        #expect(spy.handlers["https"] == "other")
        #expect(!model.isDefault)
        #expect(model.message != nil)
    }

    @Test func partialChangeIsReportedAndRetryOnlyRepairsMissingScheme() async {
        let spy = DefaultHandlerSpy()
        spy.failOn = "https"
        let model = settings(spy)
        await model.makeDefault()
        #expect(model.hasPartialSelection)
        #expect(!model.isDefault)
        #expect(model.message == L10n.text("Narly is set as the default for only some web links. Try again to finish setup."))
        spy.failOn = nil
        await model.makeDefault()
        #expect(spy.calls == ["http", "https", "https"])
        #expect(model.isDefault)
    }

    @Test func completionWithoutActualChangeDoesNotClaimSuccess() async {
        let spy = DefaultHandlerSpy()
        spy.applyChange = false
        let model = settings(spy)
        await model.makeDefault()
        #expect(!model.isDefault)
        #expect(model.message != nil)
    }

    @Test func settingsOnlyAppearForOrdinaryLaunchWithoutQueuedLinks() {
        #expect(LaunchPresentation.shouldShowSettings(isDefaultLaunch: true, hasPendingLinks: false))
        #expect(!LaunchPresentation.shouldShowSettings(isDefaultLaunch: false, hasPendingLinks: false))
        #expect(!LaunchPresentation.shouldShowSettings(isDefaultLaunch: true, hasPendingLinks: true))
        #expect(!LaunchPresentation.shouldShowSettings(isDefaultLaunch: false, hasPendingLinks: true))
    }
}
