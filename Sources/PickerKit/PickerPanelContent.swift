import SwiftUI

/// The stationary picker has its own glass surface; only the search indicator
/// participates in the morphing container. The transparent search slot keeps
/// the picker anchored even when it opens at the bottom of a display.
@MainActor
struct PickerPanelContent: View {
    static let linkHeight: CGFloat = 28
    static let searchHeight: CGFloat = 32
    static let searchSpacing: CGFloat = 8
    static let inset: CGFloat = 16
    nonisolated private static let coordinateSpace = "picker-panel-content"

    let session: PickerSession
    let copy: () -> Void
    let contentChanged: () -> Void
    let pickerBoundsChanged: (CGRect) -> Void
    let searchBoundsChanged: (CGRect) -> Void
    let linkBoundsChanged: (CGRect) -> Void
    @State private var searchPresentation = PickerSearchPresentation()
    @Namespace private var glassNamespace

    private var searchStatus: String? {
        guard !session.typedQuery.isEmpty, session.selectedIndex < 0 else { return nil }
        return session.nameMatchCount == 0 ? L10n.text("No matches")
            : L10n.format("%ld matches", session.nameMatchCount)
    }

    var body: some View {
        VStack(spacing: Self.searchSpacing) {
            if let link = session.current {
                PickerLinkPill(link: link, queuedCount: session.queue.pending.count,
                               isOpening: session.isOpening, copy: copy)
                    .onGeometryChange(for: CGRect.self) {
                        $0.frame(in: .named(Self.coordinateSpace))
                    } action: { linkBoundsChanged($0) }
                    .frame(width: session.contentWidth, height: Self.linkHeight)
            }

            PickerView(session: session, contentChanged: contentChanged)
                .glassEffect(.regular, in: .rect(cornerRadius: session.layout.cornerRadius))
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .named(Self.coordinateSpace))
                } action: { pickerBoundsChanged($0) }
                .transaction { transaction in
                    // Row updates and the picker's glass must stay immediate.
                    // The search pill owns the only animated surface here.
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }

            GlassEffectContainer(spacing: Self.searchSpacing) {
                ZStack {
                    if searchPresentation.isMounted {
                        PickerSearchPill(query: searchPresentation.query, status: searchStatus,
                                         glassNamespace: glassNamespace)
                            .onGeometryChange(for: CGRect.self) {
                                $0.frame(in: .named(Self.coordinateSpace))
                            } action: { searchBoundsChanged($0) }
                            .transition(.opacity)
                    }
                }
                .frame(width: session.contentWidth, height: Self.searchHeight)
            }
        }
        .onChange(of: session.typedQuery, initial: true) { _, query in
            // Ordinary typing updates text immediately without restarting motion.
            guard searchPresentation.isMounted != !query.isEmpty else {
                searchPresentation.update(query: query)
                return
            }
            let revision = searchPresentation.revision + 1
            var animation: Animation = .easeOut(duration: 0.08)
            #if DEBUG
            // Inspect intermediate native glass frames without changing release timing.
            if query.isEmpty && ProcessInfo.processInfo.arguments.contains("--slow-search-exit") {
                animation = animation.speed(0.1)
            }
            #endif
            // Remove the glass in this transaction so its native materialize
            // transition can render the exit, rather than hiding only its text.
            withAnimation(animation, completionCriteria: .removed) {
                searchPresentation.update(query: query)
            } completion: {
                // Only release the retained text here; the native transition
                // already owns removal. An old completion cannot clear new text.
                searchPresentation.finishHiding(revision: revision)
            }
        }
        .padding(Self.inset)
        .coordinateSpace(name: Self.coordinateSpace)
        .fixedSize()
    }
}

@MainActor
private struct PickerSearchPill: View {
    let query: String
    let status: String?
    let glassNamespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(verbatim: query)
                .lineLimit(1)
                .truncationMode(.head)
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: PickerPanelContent.searchHeight)
        .background {
            if reduceTransparency {
                Capsule().fill(Color(nsColor: .windowBackgroundColor))
            }
        }
        .glassEffect(.regular, in: Capsule())
        .glassEffectID("search-pill", in: glassNamespace)
        .glassEffectTransition(reduceMotion ? .identity : .materialize)
        .overlay {
            if contrast == .increased {
                Capsule().strokeBorder(.primary, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([L10n.format("Search: %@", query), status].compactMap { $0 }.joined(separator: ". "))
        .accessibilityIdentifier("picker-search-pill")
    }
}
