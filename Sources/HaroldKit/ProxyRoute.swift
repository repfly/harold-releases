import Foundation
import Network
import os

/// Routes a session configuration through the Harold proxy. The client calls it only after `start`.
struct ProxyRoute: Sendable {
    private let environment: @Sendable () -> [String: String]
    private let logger = Logger(subsystem: "dev.alpr.harold.kit", category: "proxy")

    init(environment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment }) {
        self.environment = environment
    }

    func apply(to configuration: URLSessionConfiguration) {
        guard let value = environment()["HAROLD_PROXY"] else { return }
        guard #available(iOS 17, macOS 14, *) else {
            logger.info("HAROLD_PROXY needs iOS 17 or macOS 14. No proxy route.")
            return
        }
        guard let parsed = value.hostAndPort, let port = NWEndpoint.Port(rawValue: parsed.port) else {
            logger.error("HAROLD_PROXY value is not host:port. No proxy route.")
            return
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(parsed.host), port: port)
        // ProxyConfiguration cannot be compared, so call apply once for each configuration.
        configuration.proxyConfigurations.append(ProxyConfiguration(httpCONNECTProxy: endpoint))
    }
}

extension String {
    /// Parses `host:port`. A missing host, a non-numeric port or a port outside 1...65535 gives `nil`.
    var hostAndPort: (host: String, port: UInt16)? {
        guard let colon = lastIndex(of: ":") else { return nil }
        let host = String(self[..<colon])
        guard !host.isEmpty, let port = UInt16(self[index(after: colon)...]), port > 0 else { return nil }
        return (host, port)
    }
}
