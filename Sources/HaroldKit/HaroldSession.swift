import Foundation
import os

/// What a session needs from outside. Tests replace both closures.
struct SessionDependencies: Sendable {
    /// `nil` when no host builds a valid address.
    var makeTransport: @Sendable () -> (any HaroldTransport)?
    var sleep: @Sendable (TimeInterval) async throws -> Void
    /// Called when the Mac answers `welcome`.
    var didWelcome: @Sendable () -> Void = {}
}

/// The connection loop: connect, say hello, serve until the link breaks, wait, repeat.
/// It stops for good on `rejected`. The owner cancels the task that runs it.
actor HaroldSession {
    private static let maxBatchEntries = 100

    private let hello: Hello
    private let queue: LogQueue
    private let stateBox: StateBox
    private let overrides: HaroldOverrides
    private let dependencies: SessionDependencies
    private let schedule = ReconnectSchedule()
    private let logger = Logger(subsystem: "dev.alpr.harold.kit", category: "connection")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var welcomed = false
    private var isRejected = false

    init(
        hello: Hello,
        queue: LogQueue,
        stateBox: StateBox,
        overrides: HaroldOverrides,
        dependencies: SessionDependencies
    ) {
        self.hello = hello
        self.queue = queue
        self.stateBox = stateBox
        self.overrides = overrides
        self.dependencies = dependencies
    }

    func run() async {
        var failures = 0
        while !Task.isCancelled && !isRejected {
            welcomed = false
            do {
                try await serve()
            } catch {
                logger.debug("Harold connection ended: \(String(describing: error), privacy: .public)")
            }
            if welcomed { failures = 0 }
            guard !isRejected, !Task.isCancelled else { break }
            let delay = schedule.delay(afterFailures: failures)
            failures += 1
            do {
                try await dependencies.sleep(delay)
            } catch {
                break
            }
        }
    }

    private func serve() async throws {
        guard let transport = dependencies.makeTransport() else { throw TransportError.noValidHost }
        try await withTaskCancellationHandler {
            try await transport.connect()
            try await transport.send(encode(hello))
            let wakes = queue.wake.stream()
            try await withThrowingTaskGroup(of: Void.self) { group in
                defer { transport.close() }
                group.addTask { try await self.receiveLoop(transport) }
                group.addTask { try await self.flushLoop(transport, wakes) }
                try await group.next()
                group.cancelAll()
            }
        } onCancel: {
            transport.close()
        }
    }

    private func receiveLoop(_ transport: any HaroldTransport) async throws {
        while !Task.isCancelled {
            let text = try await transport.receive()
            guard let message = try? decoder.decode(ServerMessage.self, from: Data(text.utf8)) else { continue }
            switch message {
            case .pairing(let code):
                logger.notice("Harold pairing code: \(code, privacy: .public)")
            case .welcome:
                welcomed = true
                dependencies.didWelcome()
                queue.wake.signal()
            case .rejected(let reason):
                logger.error("Harold rejected this app: \(reason, privacy: .public)")
                isRejected = true
                return
            case .override(let values):
                overrides.apply(values)
            case .stateRequest:
                if let values = stateBox.answer() {
                    try await transport.send(encode(StateMessage(values: values)))
                }
            case .unknown:
                break
            }
        }
    }

    private func flushLoop(_ transport: any HaroldTransport, _ wakes: AsyncStream<Void>) async throws {
        for await _ in wakes where welcomed {
            if let values = stateBox.takePending() {
                do {
                    try await transport.send(encode(StateMessage(values: values)))
                } catch {
                    stateBox.markPending()
                    throw error
                }
            }
            while let batch = queue.nextBatch(limit: Self.maxBatchEntries) {
                try await transport.send(encode(LogMessage(entries: batch.entries, dropped: batch.dropped)))
                queue.remove(batch)
            }
        }
    }

    private func encode<Message: Encodable>(_ message: Message) throws -> String {
        let data = try encoder.encode(message)
        guard let text = String(bytes: data, encoding: .utf8) else { throw TransportError.notText }
        return text
    }
}
