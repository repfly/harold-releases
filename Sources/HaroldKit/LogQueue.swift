import Foundation

/// Wakes the sender task. A signal never blocks the caller.
final class WakeSignal: Sendable {
    private let continuation = Locked<AsyncStream<Void>.Continuation?>(nil)

    /// Binds a new stream and ends the previous one. The stream yields once at once.
    func stream() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        self.continuation.withLock { current in
            current?.finish()
            current = continuation
        }
        continuation.yield()
        return stream
    }

    func signal() {
        continuation.withLock { _ = $0?.yield() }
    }
}

/// The log entries that wait for the Mac. The owner of the ring buffer.
final class LogQueue: Sendable {
    private struct Storage: Sendable {
        var buffer = RingBuffer(capacity: 1000)
        var nextSeq = 0
        var isActive = false
    }

    let wake = WakeSignal()
    private let storage = Locked(Storage())

    /// Empties the buffer, sets its size and starts to accept entries.
    func activate(capacity: Int) {
        storage.withLock {
            $0.buffer = RingBuffer(capacity: capacity)
            $0.isActive = true
        }
    }

    /// Queues an entry. Does nothing before `activate`.
    func record(message: String, level: HaroldLevel, category: String, metadata: [String: String], time: Date) {
        let accepted = storage.withLock { storage -> Bool in
            guard storage.isActive else { return false }
            storage.nextSeq += 1
            storage.buffer.append(
                LogEntry(
                    seq: storage.nextSeq,
                    time: Int64(time.timeIntervalSince1970 * 1000),
                    level: level,
                    category: category,
                    message: message,
                    metadata: metadata
                )
            )
            return true
        }
        if accepted { wake.signal() }
    }

    func nextBatch(limit: Int) -> LogBatch? {
        storage.withLock { $0.buffer.nextBatch(limit: limit) }
    }

    func remove(_ batch: LogBatch) {
        storage.withLock { $0.buffer.remove(batch) }
    }
}

/// The last state snapshot and the closure that answers state requests.
final class StateBox: Sendable {
    private struct Storage: Sendable {
        var last: [String: String]?
        var provider: (@Sendable () -> [String: String])?
        var isPending = false
    }

    private let storage = Locked(Storage())

    func set(_ values: [String: String]) {
        storage.withLock {
            $0.last = values
            $0.isPending = true
        }
    }

    func setProvider(_ provider: (@Sendable () -> [String: String])?) {
        storage.withLock { $0.provider = provider }
    }

    /// The snapshot that was set and not yet sent.
    func takePending() -> [String: String]? {
        storage.withLock { storage in
            guard storage.isPending else { return nil }
            storage.isPending = false
            return storage.last
        }
    }

    func markPending() {
        storage.withLock { $0.isPending = $0.last != nil }
    }

    /// The answer to a state request: the provider's values, else the last snapshot.
    func answer() -> [String: String]? {
        let provider = storage.withLock { $0.provider }
        let values = provider?() ?? storage.withLock { $0.last }
        storage.withLock { storage in
            storage.last = values
            storage.isPending = false
        }
        return values
    }
}
