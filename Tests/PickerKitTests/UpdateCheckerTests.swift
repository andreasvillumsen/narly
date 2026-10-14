import Foundation
import Testing
@testable import PickerKit

@Suite @MainActor struct UpdateCheckerTests {
    private func response(_ status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: UpdateChecker.endpoint, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private func release(_ tag: String = "v0.3.0", draft: Bool = false, prerelease: Bool = false,
                         assets: [[String: String]] = [["name": "Narly.dmg", "state": "uploaded"]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["tag_name": tag, "draft": draft,
                                                    "prerelease": prerelease, "assets": assets])
    }

    @Test(arguments: [("0.9.0", "v0.10.0"), ("0.2.9", "0.3.0"), ("0.99.99", "1.0.0")])
    func versionsCompareNumerically(_ older: String, _ newer: String) throws {
        #expect(try #require(ReleaseVersion(older)) < #require(ReleaseVersion(newer)))
    }

    @Test(arguments: ["", "v", "1.2", "1.2.3.4", "1..3", "1.2.-3", "1.2.3-beta.1",
                      "1.2.3+26", "01.2.3", "1.2. 3", "1.2.٣", "1.2.999999999999999999999999"])
    func malformedVersionsAreRejected(_ value: String) {
        #expect(ReleaseVersion(value) == nil)
    }

    @Test func requestTargetsPublicRepositoryWithoutUserContentOrCredentials() async throws {
        let data = try release()
        let checker = UpdateChecker { request in
            #expect(request.url == UpdateChecker.endpoint)
            #expect(request.httpMethod == "GET")
            #expect(request.httpBody == nil)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(request.timeoutInterval == 15)
            #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
            return (data, response())
        }
        let result = try await checker.check(currentVersion: "0.2.0")
        #expect(result == .available(AvailableUpdate(version: "0.3.0", releaseURL:
            URL(string: "https://github.com/andreasvillumsen/narly/releases/tag/v0.3.0")!)))
    }

    @Test(arguments: ["0.3.0", "0.4.0"])
    func sameOrNewerInstalledVersionIsUpToDate(_ installed: String) async throws {
        let data = try release()
        let checker = UpdateChecker { _ in (data, response()) }
        #expect(try await checker.check(currentVersion: installed) == .upToDate)
    }

    @Test func missingPublicReleaseDoesNotClaimUpToDate() async throws {
        let checker = UpdateChecker { _ in (Data(), response(404)) }
        #expect(try await checker.check(currentVersion: "0.2.0") == .noPublicRelease)
    }

    @Test(arguments: [403, 429, 500])
    func httpFailuresAreRecoverableErrors(_ status: Int) async throws {
        let data = try release()
        let checker = UpdateChecker { _ in (data, response(status)) }
        await #expect(throws: (any Error).self) { try await checker.check(currentVersion: "0.2.0") }
    }

    @Test func invalidAndUndownloadableReleasesAreRejected() async throws {
        let invalid = try [Data("not json".utf8), release("v0.3.0-beta"), release(draft: true),
                           release(prerelease: true), release(assets: []),
                           release(assets: [["name": "Narly.dmg", "state": "new"]])]
        for data in invalid {
            let checker = UpdateChecker { _ in (data, response()) }
            await #expect(throws: (any Error).self) { try await checker.check(currentVersion: "0.2.0") }
        }
    }

    @Test func networkFailureCanBeRetriedAndChecksAreExplicitAndDeduplicated() async throws {
        var calls = 0
        var settings: SettingsUpdates?
        let data = try release()
        let checker = UpdateChecker { _ in
            calls += 1
            #expect(settings?.state == .checking)
            await settings?.check() // Re-entry while the first request is suspended must do nothing.
            if calls == 1 { throw URLError(.notConnectedToInternet) }
            return (data, response())
        }
        let updates = SettingsUpdates(checker: checker, currentVersion: "0.2.0")
        settings = updates
        #expect(calls == 0)
        #expect(updates.state == .idle)
        await updates.check()
        #expect(calls == 1)
        #expect(updates.state == .failed)
        await updates.check()
        #expect(calls == 2)
        #expect(updates.availableUpdate?.version == "0.3.0")
    }

    @Test func failedBrowserDispatchKeepsReleaseAndRecoveryAndNeverFallsBack() async throws {
        let opener = UpdateOpenerSpy()
        let data = try release()
        let updates = SettingsUpdates(checker: UpdateChecker { _ in (data, response()) },
                                      currentVersion: "0.2.0", opener: opener)
        await updates.check()
        let browser = Destination(id: "test.browser", name: "Test Browser", applicationURL: URL(fileURLWithPath: "/Browser.app"))
        opener.fails = true
        await updates.openUpdate(in: browser)
        #expect(opener.destinations == [browser])
        #expect(opener.urls == [updates.availableUpdate?.releaseURL])
        #expect(updates.openingError != nil)
        #expect(updates.availableUpdate != nil)
        #expect(!updates.isOpening)
        opener.fails = false
        await updates.openUpdate(in: browser)
        #expect(opener.destinations == [browser, browser])
        #expect(updates.openingError == nil)
    }

    @Test(arguments: ["app.narlymac", "app.narlymac.dev", "com.browserosaurus", "xyz.alexstrnik.Browserino"])
    func recursiveDestinationsAreNeverDispatched(_ id: String) async throws {
        let opener = UpdateOpenerSpy()
        let data = try release()
        let updates = SettingsUpdates(checker: UpdateChecker { _ in (data, response()) },
                                      currentVersion: "0.2.0", opener: opener)
        await updates.check()
        await updates.openUpdate(in: Destination(id: id, name: id, applicationURL: URL(fileURLWithPath: "/Picker.app")))
        #expect(opener.destinations.isEmpty)
        #expect(updates.openingError != nil)
        #expect(updates.availableUpdate != nil)
    }
}

@MainActor private final class UpdateOpenerSpy: DestinationOpening {
    var destinations: [Destination] = []
    var urls: [URL] = []
    var fails = false

    func open(_ url: URL, in destination: Destination) async throws {
        destinations.append(destination)
        urls.append(url)
        if fails { throw DestinationOpenError.unavailable }
    }
}
