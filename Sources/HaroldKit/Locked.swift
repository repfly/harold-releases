import Foundation

/// A value behind a lock. The SDK needs synchronous, non-blocking access from any thread.
final class Locked<Value: Sendable>: @unchecked Sendable {
    // Safe: `value` is only read or written while `lock` is held.
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
