import Foundation

/// One WebSocket connection to the Harold app. A new value is made for each attempt.
protocol HaroldTransport: Sendable {
    func connect() async throws
    func send(_ text: String) async throws
    func receive() async throws -> String
    /// Closes the connection. A pending `receive` throws.
    func close()
}

enum TransportError: Error {
    case notConnected
    case binaryFrame
    case notText
    case noValidHost
}

private let haroldChannelScheme = "ws"
private let haroldChannelPort = 47391
private let haroldChannelPath = "/harold/v1"

/// The WebSocket address of the Harold app on `host` (ADR 0020).
func haroldChannelURL(host: String) -> URL? {
    var components = URLComponents()
    components.scheme = haroldChannelScheme
    components.host = host
    components.port = haroldChannelPort
    components.path = haroldChannelPath
    return components.url
}

/// `URLSessionWebSocketTask` transport.
final class URLSessionTransport: HaroldTransport {
    private struct Connection: Sendable {
        let session: URLSession
        let task: URLSessionWebSocketTask
    }

    private let url: URL
    private let connection = Locked<Connection?>(nil)

    init(url: URL) {
        self.url = url
    }

    func connect() async throws {
        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: url)
        connection.withLock { $0 = Connection(session: session, task: task) }
        task.resume()
    }

    func send(_ text: String) async throws {
        try await current().task.send(.string(text))
    }

    func receive() async throws -> String {
        switch try await current().task.receive() {
        case .string(let text): return text
        case .data: throw TransportError.binaryFrame
        @unknown default: throw TransportError.binaryFrame
        }
    }

    func close() {
        let closed = connection.withLock { current -> Connection? in
            defer { current = nil }
            return current
        }
        closed?.task.cancel(with: .goingAway, reason: nil)
        closed?.session.invalidateAndCancel()
    }

    private func current() throws -> Connection {
        guard let current = connection.withLock({ $0 }) else { throw TransportError.notConnected }
        return current
    }
}
