import Testing
@testable import PickerKit

struct AppReorderPreviewTests {
    @Test func draggingDownOpensExactlyOneSlotAtDestination() {
        let height = AppReorderPreview.rowHeight
        let preview = AppReorderPreview(id: "a", source: 1, count: 5, translation: 2 * height)
        #expect(preview.destination == 3)
        #expect((0..<5).map { preview.offset(for: $0) } == [0, 0, -height, -height, 0])
    }
    @Test func draggingUpShiftsOnlyCrossedRows() {
        let height = AppReorderPreview.rowHeight
        let preview = AppReorderPreview(id: "a", source: 3, count: 5, translation: -2 * height)
        #expect(preview.destination == 1)
        #expect((0..<5).map { preview.offset(for: $0) } == [0, height, height, 0, 0])
    }
    @Test func smallMovementsAndBounds() {
        let still = AppReorderPreview(id: "a", source: 2, count: 5, translation: 10)
        #expect(still.destination == 2)
        #expect((0..<5).allSatisfy { still.offset(for: $0) == 0 })
        #expect(AppReorderPreview(id: "a", source: 2, count: 5, translation: -1000).destination == 0)
        #expect(AppReorderPreview(id: "a", source: 2, count: 5, translation: 1000).destination == 4)
    }
}
