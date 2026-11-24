import Foundation

/// A bounded queue of log entries. It drops the oldest entry first and counts the drops.
struct RingBuffer: Sendable {
    let capacity: Int
    private(set) var entries: [LogEntry] = []
    private(set) var dropped = 0

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    mutating func append(_ entry: LogEntry) {
        if entries.count >= capacity {
            entries.removeFirst()
            dropped += 1
        }
        entries.append(entry)
    }

    /// The oldest entries, at most `limit`. The batch stays queued until ``remove(_:)``.
    func nextBatch(limit: Int) -> LogBatch? {
        guard !entries.isEmpty else { return nil }
        return LogBatch(entries: Array(entries.prefix(limit)), dropped: dropped)
    }

    /// Removes a sent batch. Entries and drops that came after `nextBatch` stay.
    mutating func remove(_ batch: LogBatch) {
        if let last = batch.entries.last?.seq {
            entries.removeAll { $0.seq <= last }
        }
        dropped = max(0, dropped - batch.dropped)
    }
}
