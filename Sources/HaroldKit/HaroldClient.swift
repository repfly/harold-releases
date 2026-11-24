import Foundation
import os

/// The instance behind ``Harold``. Until `start`, it opens no socket and reads no environment
/// or `UserDefaults`. ``log(_:level:category:metadata:)`` writes only to `os_log`.
final class HaroldClient: Sendable {
    let overrides = HaroldOverrides()

    private let queue = LogQueue()
    private let stateBox = StateBox()
    private let task = Locked<Task<Void, Never>?>(nil)
    private let environment: @Sendable () -> [String: String]
    private let now: @Sendable () -> Date
    private let makeHello: @Sendable () async -> Hello
    private let makeHosts: @Sendable () -> HaroldHostOrder
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let proxyRoute: ProxyRoute
    private let logger = Logger(subsystem: "dev.alpr.harold.kit", category: "connection")

    init(
        environment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment },
        now: @escaping @Sendable () -> Date = { Date() },
        makeHello: @escaping @Sendable () async -> Hello = { await HelloBuilder().make() },
        makeHosts: @escaping @Sendable () -> HaroldHostOrder = { HaroldHostOrder() },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
            try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
        }
    ) {
        self.environment = environment
        self.now = now
        self.makeHello = makeHello
        self.makeHosts = makeHosts
        self.sleep = sleep
        self.proxyRoute = ProxyRoute(environment: environment)
    }

    func start(bufferCapacity: Int) {
        let hosts = makeHosts()
        let dependencies = SessionDependencies(
            makeTransport: { hosts.nextChannelURL().map { URLSessionTransport(url: $0) } },
            sleep: sleep,
            didWelcome: { hosts.confirm() }
        )
        queue.activate(capacity: bufferCapacity)
        if hosts.takeLaunchHint() { logger.notice("Harold: launch from Harold once to set the Mac address.") }
        overrides.apply(decodeLaunchOverrides(environment()["HAROLD_OVERRIDES"]))
        let session = Task {
            let session = HaroldSession(
                hello: await self.makeHello(),
                queue: self.queue,
                stateBox: self.stateBox,
                overrides: self.overrides,
                dependencies: dependencies
            )
            await session.run()
        }
        task.withLock {
            $0?.cancel()
            $0 = session
        }
    }

    func log(_ message: String, level: HaroldLevel, category: String, metadata: [String: String]) {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HaroldKit", category: category)
        logger.log(level: level.osLogType, "\(message)")
        queue.record(message: message, level: level, category: category, metadata: metadata, time: now())
    }

    func state(_ values: [String: String]) {
        stateBox.set(values)
        queue.wake.signal()
    }

    func setStateProvider(_ provider: (@Sendable () -> [String: String])?) {
        stateBox.setProvider(provider)
    }

    /// Routes the configuration through the Harold proxy. Before `start` it does nothing.
    func apply(to configuration: URLSessionConfiguration) {
        guard task.withLock({ $0 != nil }) else { return }
        proxyRoute.apply(to: configuration)
    }
}

extension HaroldLevel {
    fileprivate var osLogType: OSLogType {
        switch self {
        case .debug: .debug
        case .info: .info
        case .warning: .default
        case .error: .error
        }
    }
}
