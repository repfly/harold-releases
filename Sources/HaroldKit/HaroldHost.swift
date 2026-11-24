import Foundation
import os

/// Which Mac address the SDK connects to: the launch variable, the last host that gave
/// `welcome`, then the loopback. Each attempt takes the next one; `welcome` stores the host.
final class HaroldHostOrder: Sendable {
    /// Same text as `SDKChannel.hostVariable` in Core. HaroldKit cannot import Core.
    static let hostVariable = "HAROLD_HOST"
    static let loopback = "127.0.0.1"
    static let storedHostKey = "dev.alpr.harold.kit.lastHost"

    private struct State {
        var attempt = 0
        var tried: String?
        var hintTaken = false
    }

    private let launchHost: String?
    private let storedHost: String?
    private let isSimulator: Bool
    private let save: @Sendable (String) -> Void
    private let state = Locked(State())
    private let logger = Logger(subsystem: "dev.alpr.harold.kit", category: "connection")

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isSimulator: Bool = haroldRunsInSimulator,
        load: @Sendable () -> String? = { UserDefaults.standard.string(forKey: HaroldHostOrder.storedHostKey) },
        save: @escaping @Sendable (String) -> Void = {
            UserDefaults.standard.set($0, forKey: HaroldHostOrder.storedHostKey)
        }
    ) {
        launchHost = environment[Self.hostVariable].flatMap { $0.isEmpty ? nil : $0 }
        storedHost = load()
        self.isSimulator = isSimulator
        self.save = save
    }

    /// The hosts in the order to try them, without repeats.
    var candidates: [String] {
        var result: [String] = []
        for host in [launchHost, storedHost, Self.loopback] {
            if let host, !result.contains(host) { result.append(host) }
        }
        return result
    }

    /// The host for the next attempt. After the last one it starts again.
    func nextHost() -> String {
        let hosts = candidates
        return state.withLock {
            let host = hosts[$0.attempt % hosts.count]
            $0.attempt += 1
            $0.tried = host
            return host
        }
    }

    /// The channel address for the next attempt. A host that does not build an address is skipped.
    func nextChannelURL() -> URL? {
        for _ in candidates {
            let host = nextHost()
            if let url = haroldChannelURL(host: host) { return url }
            logger.error("Harold: skipped the host \(host, privacy: .private), it is not a valid address.")
        }
        return nil
    }

    /// Stores the host of the last attempt, because it gave `welcome`.
    func confirm() {
        let host = state.withLock {
            defer { $0.attempt = 0 }
            return $0.tried
        }
        if let host, host != storedHost { save(host) }
    }

    /// True once per process on a real device with no host to try but the loopback.
    func takeLaunchHint() -> Bool {
        guard !isSimulator, launchHost == nil, storedHost == nil else { return false }
        return state.withLock {
            defer { $0.hintTaken = true }
            return !$0.hintTaken
        }
    }
}

#if targetEnvironment(simulator)
    let haroldRunsInSimulator = true
#else
    let haroldRunsInSimulator = false
#endif
