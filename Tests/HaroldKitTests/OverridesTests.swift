import Foundation
import Testing

@testable import HaroldKit

struct OverridesTests {
    @Test("the launch payload fixture gives the values")
    func launchPayload() throws {
        let fixture = try fixtureObject("launch-overrides")
        let payload = try #require(fixture["HAROLD_OVERRIDES"] as? String)
        let expected = try #require(fixture["values"] as? [String: String])
        #expect(decodeLaunchOverrides(payload) == expected)
        #expect(decodeLaunchOverrides("not base64!") == [:])
        #expect(decodeLaunchOverrides(nil) == [:])
    }

    @Test("bool reads", arguments: [("on", true), ("FALSE", false), ("1", true), ("x", nil)] as [(String, Bool?)])
    func boolReads(raw: String, expected: Bool?) {
        let overrides = HaroldOverrides()
        overrides.apply(["k": raw])
        #expect(overrides.bool("k") == expected)
    }

    @Test("int reads", arguments: [("7", 7), ("-2", -2), ("x", nil)] as [(String, Int?)])
    func intReads(raw: String, expected: Int?) {
        let overrides = HaroldOverrides()
        overrides.apply(["k": raw])
        #expect(overrides.int("k") == expected)
    }

    @Test("a callback runs once for a change, not for an equal value, and null removes")
    func callbacks() {
        let overrides = HaroldOverrides()
        let one = Locked<[String]>([])
        let all = Locked<[String]>([])
        overrides.observe(key: "a") { key, value in one.withLock { $0.append("\(key)=\(value ?? "nil")") } }
        let token = overrides.observe { key, value in all.withLock { $0.append("\(key)=\(value ?? "nil")") } }

        overrides.apply(["a": "1", "b": "2"])
        overrides.apply(["a": "1"])
        overrides.apply(["a": nil])
        token.cancel()
        overrides.apply(["b": "3"])

        #expect(one.withLock { $0 } == ["a=1", "a=nil"])
        #expect(all.withLock { $0 } == ["a=1", "b=2", "a=nil"])
        #expect(overrides.all == ["b": "3"])
    }
}
