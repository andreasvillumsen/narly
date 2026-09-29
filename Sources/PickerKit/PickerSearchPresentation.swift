/// Requests insertion/removal within the caller's animation transaction, retaining
/// outgoing text until completion. Old completions cannot clear a new query.
struct PickerSearchPresentation {
    private(set) var query = ""
    private(set) var isMounted = false
    private(set) var isVisible = false
    private(set) var revision = 0

    mutating func update(query: String) {
        revision += 1
        if !query.isEmpty {
            self.query = query
        }
        isVisible = !query.isEmpty
        isMounted = isVisible
    }

    mutating func finishHiding(revision: Int) {
        guard revision == self.revision, !isVisible else { return }
        isMounted = false
        query = ""
    }
}
