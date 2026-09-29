import Foundation

@MainActor
enum DestinationActivation {
    /// Yield to AppKit while the dispatched app activates. A refused activation
    /// must not strand the queue, and cancellation after delivery is not an open
    /// failure (retrying would open the same URL twice).
    static func waitUntilReady(
        timeout: Duration = .seconds(2),
        isReady: () -> Bool,
        pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(20)) }
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        repeat {
            do { try await pause() } catch { return }
            if isReady() { return }
        } while ContinuousClock.now < deadline
    }
}
