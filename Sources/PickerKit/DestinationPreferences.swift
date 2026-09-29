import Foundation
import Observation

@MainActor @Observable
public final class DestinationPreferences {
    private struct Saved: Codable {
        var order: [String] = []
        var hidden: Set<String> = []
        var preferred: String?
    }

    public private(set) var destinations: [Destination]
    public private(set) var pickerLayout: PickerLayout
    public private(set) var pickerMode: PickerDisplayMode
    public private(set) var customPickerSize: PickerSize
    public var pickerSize: PickerSize {
        switch pickerMode {
        case .full: .standard
        case .compact: .compact
        case .custom: customPickerSize
        }
    }
    public private(set) var showsMenuBarIcon: Bool
    public private(set) var appShortcuts: [String: String]
    public private(set) var appLinkBehaviors: [String: String]

    public func setAppLinkBehavior(_ behavior: AppLinkBehavior, for app: AppLink) {
        appLinkBehaviors[app.rawValue] = behavior.rawValue
        defaults.set(appLinkBehaviors, forKey: "narly.appLinkBehaviors.v1")
        onChange?()
    }

    private var saved: Saved
    private var catalog: [Destination]
    private var manualApplications: [ManualApplication]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let catalogProvider: () -> [Destination]
    @ObservationIgnored public var onChange: (() -> Void)?
    private static let key = "narly.destinationPreferences.v1"
    private static let layoutKey = "narly.pickerLayout.v1"
    private static let modeKey = "narly.pickerDisplayMode.v1"
    private static let sizeKey = "narly.customPickerSize.v1"
    private static let menuBarKey = "narly.showsMenuBarIcon.v1"
    private static let manualKey = "narly.manualApplications.v1"
    private static let shortcutsKey = "narly.appShortcuts.v1"

    public init(destinations: [Destination], defaults: UserDefaults = .standard,
                catalogProvider: @escaping () -> [Destination] = { DestinationCatalog.supportedDestinations() }) {
        appLinkBehaviors = defaults.dictionary(forKey: "narly.appLinkBehaviors.v1") as? [String: String] ?? [:]
        self.destinations = destinations
        self.catalog = destinations
        self.defaults = defaults
        self.catalogProvider = catalogProvider
        pickerLayout = defaults.string(forKey: Self.layoutKey).flatMap(PickerLayout.init(rawValue:)) ?? .list
        pickerMode = defaults.string(forKey: Self.modeKey).flatMap(PickerDisplayMode.init(rawValue:)) ?? .full
        customPickerSize = defaults.data(forKey: Self.sizeKey)
            .flatMap { try? JSONDecoder().decode(PickerSize.self, from: $0) } ?? .standard
        showsMenuBarIcon = defaults.object(forKey: Self.menuBarKey) as? Bool ?? true
        appShortcuts = AppShortcut.validated(defaults.dictionary(forKey: Self.shortcutsKey) as? [String: String]
                                            ?? AppShortcut.defaults)
        saved = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) } ?? Saved()
        manualApplications = defaults.data(forKey: Self.manualKey)
            .flatMap { try? JSONDecoder().decode([ManualApplication].self, from: $0) } ?? []
        rebuildCatalog()
    }

    public var orderedDestinations: [Destination] {
        let ids = saved.order + destinations.map(\.id).filter { !saved.order.contains($0) }
        var seen = Set<String>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return destinations.first { $0.id == id }
        }
    }

    public var visibleDestinations: [Destination] { orderedDestinations.filter { isVisible($0.id) && $0.applicationURL != nil } }
    public var activeSettingsDestinations: [Destination] { visibleDestinations }
    public var installedSettingsDestinations: [Destination] { orderedDestinations.filter { $0.applicationURL != nil } }
    // Missing installations are derived from the local catalog, never persisted as a manual hide.
    public var hiddenSettingsDestinations: [Destination] { orderedDestinations.filter { !isVisible($0.id) || $0.applicationURL == nil } }

    /// Accessibility moves follow the same filtered order as the draggable settings list.
    public func moveActive(_ id: String, by offset: Int) {
        var order = activeSettingsDestinations.map(\.id)
        guard let index = order.firstIndex(of: id), order.indices.contains(index + offset) else { return }
        order.remove(at: index)
        order.insert(id, at: index + offset)
        let nextIndex = index + offset + 1
        reorder([id], before: nextIndex < order.count ? order[nextIndex] : nil)
    }

    /// Hidden apps remain in Settings; all move controls use that same order.
    public func moveSettingsApplication(_ id: String, by offset: Int) {
        let order = installedSettingsDestinations
        guard let source = order.firstIndex(where: { $0.id == id }),
              offset != 0, order.indices.contains(source + offset) else { return }
        reorderApp(id, relativeTo: order[source + offset].id, after: offset > 0)
    }

    public var availableBrowsers: [Destination] { visibleDestinations.filter { $0.isWebBrowser && $0.applicationURL != nil } }
    public var preferredID: String? { saved.preferred }

    public func shortcutOwner(for letter: String) -> String? {
        appShortcuts.first { $0.value == letter }?.key
    }

    @discardableResult
    public func setAppShortcut(_ letter: String?, for id: String) -> Bool {
        guard destinations.contains(where: { $0.id == id }) else { return false }
        if let letter {
            guard let normalized = AppShortcut.normalizedKey(letter),
                  shortcutOwner(for: normalized).map({ $0 == id }) ?? true else { return false }
            appShortcuts[id] = normalized
        } else {
            appShortcuts.removeValue(forKey: id)
        }
        defaults.set(appShortcuts, forKey: Self.shortcutsKey)
        onChange?()
        return true
    }

    public func isVisible(_ id: String) -> Bool { !saved.hidden.contains(id) }

    public func canHide(_ destination: Destination) -> Bool {
        !destination.isWebBrowser || !isVisible(destination.id) || destination.applicationURL == nil || availableBrowsers.count > 1
    }

    public func setVisible(_ visible: Bool, id: String) {
        guard let destination = destinations.first(where: { $0.id == id }), visible || canHide(destination) else { return }
        if visible { saved.hidden.remove(id) } else { saved.hidden.insert(id) }
        if !visible, saved.preferred == id { saved.preferred = nil }
        persist()
    }

    public func move(_ id: String, by offset: Int) {
        var order = orderedDestinations.map(\.id)
        guard let index = order.firstIndex(of: id), order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
        saved.order = order
        persist()
    }

    /// The lower half of a row inserts after it, including when moving down one place.
    public func reorderApp(_ id: String, relativeTo target: String?, after: Bool) {
        guard id != target else { return }
        guard let target, after else {
            reorder([id], before: target)
            return
        }
        let order = orderedDestinations.map(\.id)
        guard let index = order.firstIndex(of: target) else { return }
        let next = order.dropFirst(index + 1).first { $0 != id }
        reorder([id], before: next)
    }

    /// Apply a completed native drop using stable identities, not stale row offsets.
    /// nil means the end of the list. A cancelled drag never calls this method.
    public func reorder(_ ids: [String], before target: String?) {
        let order = orderedDestinations.map(\.id)
        let requested = Set(ids)
        guard !requested.isEmpty, requested.isSubset(of: Set(order)) else { return }
        if let target {
            guard order.contains(target), !requested.contains(target) else { return }
        }
        let moving = order.filter { requested.contains($0) }
        var remaining = order.filter { !requested.contains($0) }
        let insertion = target.flatMap { remaining.firstIndex(of: $0) } ?? remaining.endIndex
        remaining.insert(contentsOf: moving, at: insertion)
        guard remaining != order else { return }
        saved.order = remaining
        persist()
    }

    public func setPickerLayout(_ layout: PickerLayout) {
        guard layout != pickerLayout else { return }
        pickerLayout = layout
        defaults.set(layout.rawValue, forKey: Self.layoutKey)
        onChange?()
    }

    public func setPickerMode(_ mode: PickerDisplayMode) {
        guard mode != pickerMode else { return }
        pickerMode = mode
        defaults.set(mode.rawValue, forKey: Self.modeKey)
        onChange?()
    }

    public func setShowsMenuBarIcon(_ visible: Bool) {
        guard visible != showsMenuBarIcon else { return }
        showsMenuBarIcon = visible
        defaults.set(visible, forKey: Self.menuBarKey)
        onChange?()
    }

    public func savePickerSize(_ size: PickerSize) {
        customPickerSize = size
        pickerMode = .custom
        if let data = try? JSONEncoder().encode(size) { defaults.set(data, forKey: Self.sizeKey) }
        defaults.set(pickerMode.rawValue, forKey: Self.modeKey)
        onChange?()
    }

    public func resetPickerSize() {
        customPickerSize = .standard
        pickerMode = .full
        defaults.removeObject(forKey: Self.sizeKey)
        defaults.set(pickerMode.rawValue, forKey: Self.modeKey)
        onChange?()
    }

    public func setPreferred(_ id: String?) {
        guard id == nil || availableBrowsers.contains(where: { $0.id == id }) else { return }
        saved.preferred = id
        persist()
    }

    public func rescan(_ destinations: [Destination]) {
        catalog = destinations
        rebuildCatalog()
        onChange?()
    }

    public func refreshInstalledApplications() {
        rescan(catalogProvider())
    }

    public func addApplication(at url: URL) throws {
        let application = try ManualApplication(url: url)
        if let index = manualApplications.firstIndex(where: { $0.id == application.id }) {
            manualApplications[index] = application
        } else {
            manualApplications.append(application)
        }
        saved.hidden.remove(application.id)
        rebuildCatalog()
        saveManualApplications()
        persist()
    }

    public func isManuallyAdded(_ id: String) -> Bool {
        manualApplications.contains { $0.id == id } && !catalog.contains { $0.id == id }
    }

    public func removeApplication(_ id: String) {
        guard isManuallyAdded(id), let destination = destinations.first(where: { $0.id == id }), canHide(destination) else { return }
        manualApplications.removeAll { $0.id == id }
        saved.order.removeAll { $0 == id }
        saved.hidden.remove(id)
        appShortcuts.removeValue(forKey: id)
        defaults.set(appShortcuts, forKey: Self.shortcutsKey)
        if saved.preferred == id { saved.preferred = nil }
        rebuildCatalog()
        saveManualApplications()
        persist()
    }

    private func rebuildCatalog() {
        var result = catalog
        for application in manualApplications where !DestinationPolicy.isRecursive(application.id) {
            let url = application.resolvedURL()
            if let index = result.firstIndex(where: { $0.id == application.id }) {
                let original = result[index]
                result[index] = Destination(id: original.id, name: original.name,
                                        applicationURL: url ?? original.applicationURL, appLink: original.appLink)
            } else {
                result.append(Destination(id: application.id, name: application.name, applicationURL: url))
            }
        }
        destinations = result
    }

    private func saveManualApplications() {
        if let data = try? JSONEncoder().encode(manualApplications) { defaults.set(data, forKey: Self.manualKey) }
    }

    private func persist() {
        // This value contains only strings and sets of strings; encoding cannot fail.
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.key) }
        onChange?()
    }
}
