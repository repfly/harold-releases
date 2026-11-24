import Foundation
import Testing

@testable import HaroldKit

/// Reads a wire fixture from `SDKs/protocol/`.
func fixtureData(_ name: String, file: StaticString = #filePath) throws -> Data {
    let url = URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("protocol/\(name).json")
    return try Data(contentsOf: url)
}

func fixtureObject(_ name: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: fixtureData(name)) as? [String: Any])
}

func encodedObject<Message: Encodable>(_ message: Message) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
}

func makeEntry(_ seq: Int) -> LogEntry {
    LogEntry(seq: seq, time: Int64(seq), level: .info, category: "test", message: "m\(seq)", metadata: [:])
}
