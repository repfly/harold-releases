import Foundation
import Testing

@testable import HaroldKit

/// A scripted transport: it plays `incoming` frames and records what the session sends.
private final class FakeTransport: HaroldTransport {
    let sent: AsyncStream<String>
    private let sentContinuation: AsyncStream<String>.Continuation
    private let incoming: AsyncStream<String>
    private let incomingContinuation: AsyncStream<String>.Continuation

    init(script: [String]) {
        (sent, sentContinuation) = AsyncStream.makeStream()
        (incoming, incomingContinuation) = AsyncStream.makeStream()
        for frame in script { incomingContinuation.yield(frame) }
    }

    func connect() async throws {}

    func send(_ text: String) async throws { sentContinuation.yield(text) }

    func receive() async throws -> String {
        for await frame in incoming { return frame }
        throw TransportError.notConnected
    }

    func close() {
        incomingContinuation.finish()
        sentContinuation.finish()
    }
}

private func makeHello() -> Hello {
    Hello(
        deviceKey: "k", deviceName: "n", model: "m", osVersion: "1.0", simulator: true, appID: "a", appName: "A",
        appVersion: "1")
}

struct SessionTests {
    @Test("no batch has more than 100 entries, and the first one carries the drop count")
    func batchesAreBounded() async throws {
        let queue = LogQueue()
        queue.activate(capacity: 240)
        for index in 1...250 {
            queue.record(
                message: "m\(index)", level: .info, category: "c", metadata: [:],
                time: Date(timeIntervalSince1970: 0))
        }
        let transport = FakeTransport(script: [#"{"type":"welcome","sessionID":"s"}"#])
        let session = HaroldSession(
            hello: makeHello(), queue: queue, stateBox: StateBox(), overrides: HaroldOverrides(),
            dependencies: SessionDependencies(makeTransport: { transport }, sleep: { _ in })
        )
        let task = Task { await session.run() }
        var counts: [Int] = []
        var dropped: [Int] = []
        var messages = 0
        for await text in transport.sent {
            messages += 1
            if messages == 1 { continue }  // hello
            let object = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            counts.append((object["entries"] as? [Any])?.count ?? -1)
            dropped.append(object["dropped"] as? Int ?? -1)
            if counts.reduce(0, +) == 240 { break }
        }
        task.cancel()
        #expect(counts == [100, 100, 40])
        #expect(dropped == [10, 0, 0])
    }

    @Test("rejected stops the reconnect loop")
    func rejectedStops() async {
        let connects = Locked(0)
        let session = HaroldSession(
            hello: makeHello(), queue: LogQueue(), stateBox: StateBox(), overrides: HaroldOverrides(),
            dependencies: SessionDependencies(
                makeTransport: {
                    connects.withLock { $0 += 1 }
                    return FakeTransport(script: [#"{"type":"rejected","reason":"no"}"#])
                },
                sleep: { _ in }
            )
        )
        await session.run()
        #expect(connects.withLock { $0 } == 1)
    }

    @Test("a state answer uses the provider, else the last snapshot")
    func stateAnswers() throws {
        let box = StateBox()
        box.set(["a": "1"])
        #expect(box.takePending() == ["a": "1"])
        #expect(box.takePending() == nil)
        #expect(box.answer() == ["a": "1"])
        box.setProvider { ["b": "2"] }
        #expect(box.answer() == ["b": "2"])
        box.setProvider(nil)
        #expect(box.answer() == ["b": "2"])
    }
}
