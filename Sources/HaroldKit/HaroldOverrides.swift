import Foundation

/// A handle for an override callback. Call ``cancel()`` to stop it.
public final class HaroldObservation: Sendable {
    private let onCancel: @Sendable () -> Void

    init(onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    /// Stops the callback. Calling it twice is safe.
    public func cancel() {
        onCancel()
    }
}

/// String key/value overrides that the Harold app sends, with typed reads and change callbacks.
public final class HaroldOverrides: Sendable {
    private struct Observer: Sendable {
        let key: String?
        let handler: @Sendable (String, String?) -> Void
    }

    private struct Call: Sendable {
        let handler: @Sendable (String, String?) -> Void
        let key: String
        let value: String?
    }

    private struct Storage: Sendable {
        var values: [String: String] = [:]
        var observers: [Int: Observer] = [:]
        var nextID = 0
    }

    private let storage = Locked(Storage())

    init() {}

    /// All current values.
    public var all: [String: String] {
        storage.withLock { $0.values }
    }

    /// The raw value for `key`, or `nil`.
    public func string(_ key: String) -> String? {
        storage.withLock { $0.values[key] }
    }

    /// The value as a boolean. `true`, `on`, `yes`, `1` and `false`, `off`, `no`, `0` (any case) are known.
    public func bool(_ key: String) -> Bool? {
        switch string(key)?.lowercased() {
        case "true", "on", "yes", "1": true
        case "false", "off", "no", "0": false
        default: nil
        }
    }

    /// The value as an integer, or `nil` when it is missing or not a number.
    public func int(_ key: String) -> Int? {
        string(key).flatMap { Int($0) }
    }

    /// Runs `handler` when the value of `key` changes, or of any key when `key` is `nil`.
    ///
    /// The handler gets the key and the new value (`nil` when the key was removed).
    /// It runs on an arbitrary thread, once for each change, and not for an equal value.
    @discardableResult
    public func observe(
        key: String? = nil,
        _ handler: @escaping @Sendable (_ key: String, _ value: String?) -> Void
    ) -> HaroldObservation {
        let id = storage.withLock { storage -> Int in
            storage.nextID += 1
            storage.observers[storage.nextID] = Observer(key: key, handler: handler)
            return storage.nextID
        }
        return HaroldObservation { [storage] in
            storage.withLock { _ = $0.observers.removeValue(forKey: id) }
        }
    }

    /// Applies changes. A `nil` value removes the key. Callbacks run after the lock is released.
    func apply(_ changes: [String: String?]) {
        let calls = storage.withLock { storage -> [Call] in
            var calls: [Call] = []
            for (key, newValue) in changes.sorted(by: { $0.key < $1.key }) {
                guard storage.values[key] != newValue else { continue }
                storage.values[key] = newValue
                for observer in storage.observers.values where observer.key == nil || observer.key == key {
                    calls.append(Call(handler: observer.handler, key: key, value: newValue))
                }
            }
            return calls
        }
        for call in calls {
            call.handler(call.key, call.value)
        }
    }
}
