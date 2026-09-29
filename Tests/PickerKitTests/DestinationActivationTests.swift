import Foundation
import Testing
@testable import PickerKit

@Suite @MainActor struct DestinationActivationTests {
    @Test func waitsForDelayedActivation() async {
        var turns = 0
        await DestinationActivation.waitUntilReady(isReady: { turns == 3 }, pause: { turns += 1 })
        #expect(turns == 3)
    }

    @Test func alreadyActiveDestinationStillYieldsToAppKit() async {
        var yielded = false
        await DestinationActivation.waitUntilReady(isReady: { true }, pause: { yielded = true })
        #expect(yielded)
    }

    @Test func refusedActivationHasABoundedWait() async {
        var turns = 0
        await DestinationActivation.waitUntilReady(timeout: .zero, isReady: { false }, pause: { turns += 1 })
        #expect(turns == 1)
    }

    @Test func cancellationAfterDispatchDoesNotReportAnOpenFailure() async {
        var checks = 0
        await DestinationActivation.waitUntilReady(isReady: { checks += 1; return false },
                                                   pause: { throw CancellationError() })
        #expect(checks == 0)
    }
}
