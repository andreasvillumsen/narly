import Darwin
import Foundation
import Testing
@testable import PickerKit

@Suite struct QueueMemoryTests {
    private func residentBytes() throws -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let capacity = Int(count)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        #expect(status == KERN_SUCCESS)
        return info.resident_size
    }

    private func burst(_ round: Int, count: Int) -> [URL] {
        (0..<count).map { index in
            let prefix = "https://example.com/\(round)-\(index)?sample="
            return URL(string: prefix + String(repeating: "a", count: LinkQueueLimits.maximumURLBytes - prefix.utf8.count))!
        }
    }

    @Test func repeatedLargeBurstsKeepOnlyTwentyAcceptedURLs() throws {
        var queue = LinkQueue()
        queue.enqueue(burst(-2, count: 10))
        queue.dismiss()
        queue.enqueue(burst(-1, count: 10))
        let original = queue.pending.map(\.id)
        var samples: [UInt64] = []
        for round in 0..<210 {
            autoreleasepool {
                let result = queue.enqueue(burst(round, count: 32))
                #expect(result.accepted == 0 && result.rejected.queueFull == 32)
            }
            if [9, 59, 109, 209].contains(round) { samples.append(try residentBytes()) }
        }
        #expect(queue.pending.map(\.id) == original)
        #expect(queue.pending.count == 10 && queue.dismissed.count == 10)
        let serializedBytes = queue.pending.reduce(0) { $0 + $1.url.absoluteString.utf8.count }
            + queue.dismissed.reduce(0) { $0 + $1.absoluteString.utf8.count }
        #expect(serializedBytes == 20 * 65_536)
        // Observation only: allocator/OS behaviour is not a stable pass/fail threshold.
        print("Queue memory observation: resident bytes after warmup / 50 / 100 / 200 bursts: \(samples); retained URL bytes: \(serializedBytes)")
    }
}
