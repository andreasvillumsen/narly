import Foundation
import Observation
import ServiceManagement

@MainActor
public protocol LoginItemHandling {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() async throws
}

@MainActor
public struct SystemLoginItemHandler: LoginItemHandling {
    public init() {}
    public var status: SMAppService.Status { SMAppService.mainApp.status }
    public func register() throws { try SMAppService.mainApp.register() }
    public func unregister() async throws { try await SMAppService.mainApp.unregister() }
}

@MainActor @Observable
public final class LoginItemSettings {
    public private(set) var status: SMAppService.Status
    public private(set) var isChanging = false
    public private(set) var errorMessage: String?
    @ObservationIgnored private let handler: any LoginItemHandling

    public init(handler: any LoginItemHandling = SystemLoginItemHandler()) {
        self.handler = handler
        status = handler.status
    }

    public var isRequested: Bool { status == .enabled || status == .requiresApproval }
    public var description: String {
        switch status {
        case .enabled: L10n.text("Narly opens automatically when you log in.")
        case .requiresApproval: L10n.text("Allow Narly in System Settings to open it automatically at login.")
        case .notFound: L10n.text("macOS couldn’t find Narly. Open it from Applications and try again.")
        case .notRegistered: L10n.text("If Narly is your default browser, opening a link starts it automatically.")
        @unknown default: L10n.text("Couldn’t check whether Narly opens at login.")
        }
    }

    public func refresh() { status = handler.status }

    public func setEnabled(_ enabled: Bool) async {
        guard !isChanging else { return }
        isChanging = true
        errorMessage = nil
        defer { refresh(); isChanging = false }
        do {
            if enabled { try handler.register() } else { try await handler.unregister() }
        } catch {
            errorMessage = L10n.text("Couldn’t change whether Narly opens at login. Check Narly’s permissions in System Settings.")
        }
    }

    public func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
