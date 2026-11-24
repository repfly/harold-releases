import Foundation
import Testing

@testable import HaroldKit

struct WireTests {
    @Test("hello encodes to the fixture")
    func helloMatchesFixture() throws {
        let hello = Hello(
            deviceKey: "3f9c1c52-7a4e-4f0e-9d58-0c1d6a1b2e77",
            deviceName: "iPhone 17 Pro",
            model: "iPhone18,1",
            osVersion: "26.0",
            simulator: true,
            appID: "dev.example.Shop",
            appName: "Shop",
            appVersion: "2.4.1"
        )
        #expect(NSDictionary(dictionary: try encodedObject(hello)).isEqual(to: try fixtureObject("hello")))
    }

    @Test("log message encodes to the fixture")
    func logMatchesFixture() throws {
        let entries = [
            LogEntry(
                seq: 1, time: 1_790_000_000_123, level: .info, category: "auth", message: "user logged in",
                metadata: ["userId": "42"]),
            LogEntry(
                seq: 2, time: 1_790_000_000_456, level: .error, category: "network", message: "request failed",
                metadata: [:]),
        ]
        let message = LogMessage(entries: entries, dropped: 3)
        #expect(NSDictionary(dictionary: try encodedObject(message)).isEqual(to: try fixtureObject("log")))
    }

    @Test("state message encodes to the fixture")
    func stateMatchesFixture() throws {
        let message = StateMessage(values: ["env": "QA", "userId": "42", "screen": "Checkout"])
        #expect(NSDictionary(dictionary: try encodedObject(message)).isEqual(to: try fixtureObject("state")))
    }

    @Test(
        "server fixtures decode",
        arguments: [
            ("pairing", ServerMessage.pairing(code: "428913")),
            ("welcome", .welcome(sessionID: "7d0c4a52-91d2-4b86-8f0b-3a6a5f1c9e10")),
            ("rejected", .rejected(reason: "Pairing was denied.")),
            ("override", .override(values: ["tutorials": "off", "newCheckout": nil])),
            ("stateRequest", .stateRequest),
        ])
    func serverFixturesDecode(name: String, expected: ServerMessage) throws {
        #expect(try JSONDecoder().decode(ServerMessage.self, from: fixtureData(name)) == expected)
    }

    @Test("an unknown message type is kept, not an error")
    func unknownType() throws {
        let data = Data(#"{"type":"future"}"#.utf8)
        #expect(try JSONDecoder().decode(ServerMessage.self, from: data) == .unknown(type: "future"))
    }

    @Test(
        "the reconnect delay is 1, 2, 5, then 10 seconds",
        arguments: [(0, 1.0), (1, 2.0), (2, 5.0), (3, 10.0), (50, 10.0)])
    func schedule(failures: Int, expected: Double) {
        #expect(ReconnectSchedule().delay(afterFailures: failures) == expected)
    }
}
