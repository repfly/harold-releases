import Foundation
import Testing

@testable import HaroldKit

private let environmentWithProxy = ["HAROLD_PROXY": "127.0.0.1:47392"]

// No element is ever sent and the continuation stays alive, so a session waits on the hello
// until its task is cancelled. The test opens no socket.
private let neverHello = AsyncStream.makeStream(of: Never.self)

private func makeClient(
    environment: @escaping @Sendable () -> [String: String] = { environmentWithProxy },
    makeHosts: @escaping @Sendable () -> HaroldHostOrder = { HaroldHostOrder() }
) -> HaroldClient {
    HaroldClient(
        environment: environment,
        makeHello: {
            for await _ in neverHello.stream {}
            return Hello(
                deviceKey: "k", deviceName: "n", model: "m", osVersion: "1.0", simulator: true, appID: "a",
                appName: "A", appVersion: "1")
        },
        makeHosts: makeHosts
    )
}

struct ClientGatingTests {
    @Test("the client init reads no environment and makes no host order")
    func initReadsNothing() {
        let calls = Locked(0)
        _ = makeClient(
            environment: {
                calls.withLock { $0 += 1 }
                return [:]
            },
            makeHosts: {
                calls.withLock { $0 += 1 }
                return HaroldHostOrder()
            })
        #expect(calls.withLock { $0 } == 0)
    }

    @Test("apply adds no proxy before start and one after")
    func applyNeedsStart() {
        guard #available(iOS 17, macOS 14, *) else { return }
        let client = makeClient()
        let before = URLSessionConfiguration.default
        client.apply(to: before)
        #expect(before.proxyConfigurations.isEmpty)
        client.start(bufferCapacity: 10)
        let after = URLSessionConfiguration.default
        client.apply(to: after)
        #expect(after.proxyConfigurations.count == 1)
    }
}
