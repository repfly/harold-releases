import Foundation
import Testing

@testable import HaroldKit

struct RingBufferTests {
    @Test("the buffer drops the oldest entries and counts them")
    func dropsOldest() {
        var buffer = RingBuffer(capacity: 3)
        for seq in 1...5 { buffer.append(makeEntry(seq)) }
        #expect(buffer.entries.map(\.seq) == [3, 4, 5])
        #expect(buffer.dropped == 2)
    }

    @Test("a sent batch leaves the entries and drops that came after it")
    func removeKeepsNewer() throws {
        var buffer = RingBuffer(capacity: 3)
        for seq in 1...4 { buffer.append(makeEntry(seq)) }
        let batch = try #require(buffer.nextBatch(limit: 2))
        #expect(batch.entries.map(\.seq) == [2, 3])
        #expect(batch.dropped == 1)
        buffer.append(makeEntry(5))
        buffer.remove(batch)
        #expect(buffer.entries.map(\.seq) == [4, 5])
        #expect(buffer.dropped == 1)
    }

    @Test("an empty buffer has no batch")
    func emptyHasNoBatch() {
        #expect(RingBuffer(capacity: 3).nextBatch(limit: 100) == nil)
    }
}
