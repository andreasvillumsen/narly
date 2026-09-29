import Foundation
import Observation

@MainActor @Observable
public final class IntroductionState {
    public private(set) var isVisible: Bool
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "narly.introductionCompleted.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isVisible = !defaults.bool(forKey: Self.key)
    }

    public func complete() {
        defaults.set(true, forKey: Self.key)
        isVisible = false
    }

    public func show() { isVisible = true }
}
