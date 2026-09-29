import Foundation
import Observation

@MainActor @Observable
public final class PickerSession {
    public private(set) var queue = LinkQueue()
    public var layout: PickerLayout
    var contentWidth: CGFloat {
        layout == .horizontal
            ? HorizontalPickerMetrics.contentWidth(count: destinations.count)
            : pickerSize.width
    }
    public var displayMode: PickerDisplayMode
    public var customPickerSize: PickerSize
    public var pickerSize: PickerSize {
        switch displayMode {
        case .full: .standard
        case .compact: .compact
        case .custom: customPickerSize
        }
    }
    public var appLinkBehaviors: [String: String] = [:]
    public var routingDestinations: [Destination] = []
    private var automaticRoutes: [UUID: AppLinkBehavior] = [:]

    public var appShortcuts: [String: String]
    public var showsAppShortcuts = false
    private var catalog: [Destination]
    public var destinations: [Destination] { catalog.filter { $0.isWebBrowser || $0.applicationURL != nil } }

    public func canOpen(_ destination: Destination) -> Bool {
        guard current != nil, destination.applicationURL != nil else { return false }
        guard let appLink = destination.appLink else { return true }
        return current.map { appLink.accepts($0.url) } == true
    }
    public private(set) var selectedIndex = 0
    public private(set) var typedQuery = ""
    private var nameMatches: [Int] {
        destinations.indices.filter { !matchedNameRanges(for: destinations[$0]).isEmpty }
    }
    var nameMatchCount: Int { nameMatches.count }
    var searchScrollIndex: Int { selectedIndex >= 0 ? selectedIndex : (nameMatches.first ?? -1) }

    func matchedNameRanges(for destination: Destination) -> [Range<String.Index>] {
        guard canOpen(destination) else { return [] }
        return PickerNameMatch.ranges(in: destination.name, query: typedQuery)
    }

    public func typeName(_ text: String) {
        guard isPresented, current != nil, !isOpening, typedQuery.count + text.count <= 128 else { return }
        typedQuery += text
        selectNameMatch()
    }

    public func deleteNameCharacter() {
        guard isPresented, !isOpening, !typedQuery.isEmpty else { return }
        typedQuery.removeLast()
        selectNameMatch()
    }

    public func clearNameSearch() {
        guard !isOpening else { return }
        typedQuery = ""
        selectedIndex = initialSelection
    }

    private func selectNameMatch() {
        guard !typedQuery.isEmpty else { selectedIndex = initialSelection; return }
        let matches = nameMatches
        let exact = matches.filter { PickerNameMatch.isExact(destinations[$0].name, query: typedQuery) }
        // Never let Return open the old selection after an ambiguous search or typo.
        selectedIndex = exact.count == 1 ? exact[0] : (matches.count == 1 ? matches[0] : -1)
    }
    public private(set) var preferredBrowserID: String?
    public private(set) var isReady = false
    public private(set) var isOpening = false
    public private(set) var isResolving = false
    public private(set) var isPresented = false
    public private(set) var errorMessage: String?
    public private(set) var rejectionNotice: LinkRejections?
    public var current: PendingLink? { queue.pending.first }
    public var hasPendingPresentation: Bool { current != nil || rejectionNotice != nil }

    public var rejectionMessage: String? {
        guard let notice = rejectionNotice else { return nil }
        var reasons: [String] = []
        if notice.queueFull > 0 { reasons.append(L10n.format("Queue full: %ld.", notice.queueFull)) }
        if notice.oversized > 0 { reasons.append(L10n.format("Link addresses too long: %ld.", notice.oversized)) }
        if notice.unsupported > 0 { reasons.append(L10n.format("Unsupported link types: %ld.", notice.unsupported)) }
        return ([L10n.format("Links not added: %ld.", notice.total)] + reasons
                + [L10n.text("Open or copy links in the queue to make room, then try the skipped links again from the app they came from. Open links with addresses that are too long or unsupported types in another app.")]).joined(separator: " ")
    }

    public func dismissRejectionNotice() {
        rejectionNotice = nil
        if current == nil, !isOpening, isPresented {
            isPresented = false
            onHide?()
        }
    }

    @ObservationIgnored public var onShow: (() -> Void)?
    @ObservationIgnored public var onHide: (() -> Void)?
    @ObservationIgnored public var onOpenFailure: (() -> Void)?
    @ObservationIgnored public var trace: ((String, UUID?) -> Void)?
    @ObservationIgnored private let opener: any DestinationOpening
    @ObservationIgnored private var resolutionTask: Task<URL, Error>?
    @ObservationIgnored private var openingID: UUID?

    public init(destinations: [Destination], opener: any DestinationOpening, preferredBrowserID: String? = nil, displayMode: PickerDisplayMode = .full,
                customPickerSize: PickerSize = .standard, layout: PickerLayout = .list,
                appShortcuts: [String: String] = [:]) {
        self.layout = layout
        self.appShortcuts = appShortcuts
        self.displayMode = displayMode
        self.customPickerSize = customPickerSize
        self.catalog = destinations
        self.opener = opener
        self.preferredBrowserID = preferredBrowserID
    }

    public func ready() {
        isReady = true
        presentIfPossible()
    }

    public func receive(_ urls: [URL], optionHeld: Bool = false) {
        let previousIDs = Set(queue.pending.map(\.id))
        let wasEmpty = queue.pending.isEmpty
        let result = queue.enqueue(urls)
        for link in queue.pending where !previousIDs.contains(link.id) {
            guard let app = AppLink.allCases.first(where: { $0.accepts(link.url) }) else { continue }
            let behavior = AppLinkBehavior(rawValue: appLinkBehaviors[app.rawValue] ?? "") ?? .ask
            let route = behavior.route(optionHeld: optionHeld)
            if route != .ask { automaticRoutes[link.id] = route }
        }
        if result.rejected.total > 0 {
            rejectionNotice = rejectionNotice?.merging(result.rejected) ?? result.rejected
            trace?("urls-rejected-full-\(result.rejected.queueFull)-oversized-\(result.rejected.oversized)-unsupported-\(result.rejected.unsupported)", current?.id)
        } else if result.accepted > 0 {
            trace?("urls-accepted", current?.id)
        }
        guard result.accepted > 0 || result.rejected.total > 0 else { return }
        if wasEmpty, result.accepted > 0 { resetSelection() }
        presentIfPossible()
    }

    public func refreshDestinations(_ destinations: [Destination], preferredBrowserID: String? = nil) {
        let selected = self.destinations.indices.contains(selectedIndex) ? self.destinations[selectedIndex].id : nil
        self.catalog = destinations
        self.preferredBrowserID = preferredBrowserID
        selectedIndex = self.destinations.firstIndex(where: { $0.id == selected && canOpen($0) })
            ?? initialSelection
        if !typedQuery.isEmpty { selectNameMatch() }
    }

    public func highlight(index: Int) {
        guard !isOpening, destinations.indices.contains(index), canOpen(destinations[index]) else { return }
        typedQuery = ""
        selectedIndex = index
    }

    public func move(_ offset: Int) {
        guard !isOpening else { return }
        typedQuery = ""
        let available = destinations.indices.filter { canOpen(destinations[$0]) }
        guard !available.isEmpty else { return }
        if let old = available.firstIndex(of: selectedIndex) {
            selectedIndex = available[(old + offset % available.count + available.count) % available.count]
        } else {
            selectedIndex = offset < 0 ? available[available.count - 1] : available[0]
        }
        trace?("selection-moved", current?.id)
    }

    public func choose(index: Int? = nil) async {
        guard isPresented, !isOpening, let link = current else { return }
        let index = index ?? selectedIndex
        guard destinations.indices.contains(index), canOpen(destinations[index]) else { return }
        let destination = destinations[index]
        let showsProgress = destination.appLink == .slack
        let attempt = UUID()
        openingID = attempt
        isOpening = true
        isResolving = showsProgress
        errorMessage = nil
        trace?("open-start-\(destination.id)", link.id)
        if !showsProgress {
            isPresented = false
            onHide?()
        }
        // Retain the task so Escape/Cancel can stop lookup without cancelling a
        // later selection. An attempt identity also rejects late resolver results.
        let resolution = Task { try await opener.resolve(link.url, in: destination) }
        resolutionTask = resolution
        do {
            let resolvedURL = try await withTaskCancellationHandler {
                try await resolution.value
            } onCancel: {
                resolution.cancel()
            }
            guard openingID == attempt else { return }
            try Task.checkCancellation()
            resolutionTask = nil
            isResolving = false
            if showsProgress {
                isPresented = false
                onHide?()
            }
            try await opener.open(resolvedURL, in: destination)
            queue.complete(link.id)
            trace?("open-dispatched", link.id)
            resetSelection()
        } catch {
            guard openingID == attempt else { return }
            if error is CancellationError || Task.isCancelled {
                isResolving = false
                isOpening = false
                resolutionTask = nil
                openingID = nil
                presentIfPossible()
                return
            }
            // Never log Error descriptions: system errors may contain the requested URL.
            errorMessage = L10n.format("Couldn’t open the link in %@. Choose a browser or copy the link.", destination.name)
            trace?("open-failed", link.id)
            onOpenFailure?()
        }
        resolutionTask = nil
        openingID = nil
        isResolving = false
        isOpening = false
        presentIfPossible()
    }

    /// Stop only lookup. Once dispatch starts, focus loss must not cancel the queue.
    public func cancelResolution() {
        guard isResolving else { return }
        openingID = nil
        resolutionTask?.cancel()
        resolutionTask = nil
        isResolving = false
        isOpening = false
        errorMessage = nil
        trace?("lookup-cancelled", current?.id)
    }

    public func chooseShortcut(_ letter: String) async {
        let matches = destinations.indices.filter { appShortcuts[destinations[$0].id] == letter }
        guard matches.count == 1, let index = matches.first else { return }
        await choose(index: index)
    }

    func shortcutHint(at index: Int) -> String? {
        guard destinations.indices.contains(index) else { return nil }
        if showsAppShortcuts {
            return appShortcuts[destinations[index].id].map(AppShortcut.displayKey)
        }
        return index < 9 ? String(index + 1) : nil
    }

    public func dismiss() {
        cancelResolution()
        guard !isOpening, isPresented else { return }
        trace?("queue-dismissed", current?.id)
        automaticRoutes.removeAll()
        queue.dismiss()
        typedQuery = ""
        isPresented = false
        errorMessage = nil
        rejectionNotice = nil
        onHide?()
    }

    public func restore() {
        guard !isOpening, queue.restore() else { return }
        trace?("queue-restored", current?.id)
        resetSelection()
        presentIfPossible()
    }

    /// Copy is a completed action on the current link, not cancellation of the queue.
    public func copy(using write: (String) -> Bool) {
        guard isPresented, !isOpening, let link = current else { return }
        guard write(link.url.absoluteString) else {
            errorMessage = L10n.text("Couldn’t copy the link. Try again.")
            return
        }
        trace?("link-copied", link.id)
        queue.complete(link.id)
        isPresented = false
        onHide?()
        resetSelection()
        presentIfPossible()
    }

    private func resetSelection() {
        typedQuery = ""
        selectedIndex = initialSelection
        errorMessage = nil
    }

    private var initialSelection: Int {
        destinations.firstIndex(where: { $0.id == preferredBrowserID && canOpen($0) })
            ?? destinations.firstIndex(where: { canOpen($0) }) ?? 0
    }

    private func openAutomatically(_ link: PendingLink, route: AppLinkBehavior) async {
        let routingCatalog = routingDestinations.isEmpty ? catalog : routingDestinations
        let fallback = catalog.first { $0.id == preferredBrowserID && $0.isWebBrowser && $0.applicationURL != nil }
            ?? catalog.first { $0.isWebBrowser && $0.applicationURL != nil }
        let app = routingCatalog.first { $0.applicationURL != nil && $0.appLink?.accepts(link.url) == true }
        var candidates: [Destination] = []
        if route == .app, let app { candidates.append(app) }
        if let fallback { candidates.append(fallback) }
        var opened = false
        for destination in candidates {
            do {
                let url = try await opener.resolve(link.url, in: destination)
                try await opener.open(url, in: destination)
                opened = true
                break
            } catch {
                onOpenFailure?()
            }
        }
        if opened {
            queue.complete(link.id)
            resetSelection()
        } else {
            errorMessage = L10n.text("Couldn’t open the link automatically. Choose an app or copy the link.")
        }
        isOpening = false
        presentIfPossible()
    }

    private func presentIfPossible() {
        guard isReady, !isOpening, hasPendingPresentation, !isPresented else { return }
        if let link = current, let route = automaticRoutes.removeValue(forKey: link.id) {
            isOpening = true
            Task { await openAutomatically(link, route: route) }
            return
        }
        isPresented = true
        onShow?()
    }
}
