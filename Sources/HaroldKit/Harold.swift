import Foundation

/// The severity of a log entry.
public enum HaroldLevel: String, Sendable, CaseIterable, Codable {
    case debug
    case info
    case warning
    case error
}

/// The entry point of HaroldKit.
///
/// After ``start(bufferCapacity:)`` the calls reach the Harold app on this Mac.
/// Before it, no socket opens, the SDK reads no launch environment,
/// ``log(_:level:category:metadata:)`` writes only to `os_log` and ``apply(to:)`` changes nothing.
/// Call `start` only in the builds that may connect, for example under `#if DEBUG`.
public enum Harold {
    private static let client = HaroldClient()

    /// Connects to the Harold app on `127.0.0.1` and keeps the connection alive.
    ///
    /// The first call after an install makes the app show a pairing code. The code also goes to `os_log`.
    /// Calling it again restarts the connection and clears a `rejected` stop.
    /// It also reads the `HAROLD_OVERRIDES` launch payload.
    /// - Parameter bufferCapacity: How many log entries the SDK keeps while the Mac is not reachable.
    public static func start(bufferCapacity: Int = 1000) {
        client.start(bufferCapacity: bufferCapacity)
    }

    /// Writes a log entry to `os_log` and queues it for the Harold app. It never blocks and never throws.
    public static func log(
        _ message: String,
        level: HaroldLevel = .info,
        category: String = "default",
        metadata: [String: String] = [:]
    ) {
        client.log(message, level: level, category: category, metadata: metadata)
    }

    /// Sends a snapshot of the app state. The app can ask for it again with a state request.
    public static func state(_ values: [String: String]) {
        client.state(values)
    }

    /// Sets a closure that answers state requests from the Harold app. `nil` removes it.
    ///
    /// Without a provider, the SDK sends the last snapshot again.
    public static func setStateProvider(_ provider: (@Sendable () -> [String: String])?) {
        client.setStateProvider(provider)
    }

    /// The override values that the Mac sends at launch and later.
    public static var overrides: HaroldOverrides {
        client.overrides
    }

    /// Routes the traffic of a session configuration through the Harold proxy.
    ///
    /// Call it on each `URLSessionConfiguration` of the app before you create the session.
    /// It reads `HAROLD_PROXY=host:port` from the launch environment and adds an HTTP CONNECT proxy
    /// on iOS 17 and macOS 14 or later. It keeps the proxies the configuration already has. Call it once for each configuration.
    /// Before ``start(bufferCapacity:)``, without the variable, with a bad value or on an older OS it changes nothing.
    /// It never changes `URLSession.shared`: that session cannot be configured.
    public static func apply(to configuration: URLSessionConfiguration) {
        client.apply(to: configuration)
    }
}
