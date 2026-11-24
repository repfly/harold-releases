import Foundation

/// The version of this SDK. It goes into `hello`.
let haroldKitVersion = "0.1.0"

/// The first message of a connection (SDK to Mac).
struct Hello: Codable, Equatable {
    var type = "hello"
    var protocolVersion = 1
    var sdk = "ios"
    var sdkVersion = haroldKitVersion
    var deviceKey: String
    var deviceName: String
    var model: String
    var osVersion: String
    var simulator: Bool
    var appID: String
    var appName: String
    var appVersion: String

    private enum CodingKeys: String, CodingKey {
        case type, sdk, sdkVersion, deviceKey, deviceName, model, osVersion, simulator, appID, appName, appVersion
        case protocolVersion = "protocol"
    }
}

/// One log entry on the wire.
struct LogEntry: Codable, Equatable, Sendable {
    var seq: Int
    var time: Int64
    var level: HaroldLevel
    var category: String
    var message: String
    var metadata: [String: String]
}

/// Up to `limit` queued entries and the count of entries dropped before them.
struct LogBatch: Equatable, Sendable {
    var entries: [LogEntry]
    var dropped: Int
}

struct LogMessage: Encodable {
    var type = "log"
    var entries: [LogEntry]
    var dropped: Int
}

struct StateMessage: Encodable {
    var type = "state"
    var values: [String: String]
}

/// A message from the Mac.
enum ServerMessage: Decodable, Equatable {
    case pairing(code: String)
    case welcome(sessionID: String)
    case rejected(reason: String)
    case override(values: [String: String?])
    case stateRequest
    case unknown(type: String)

    private enum CodingKeys: String, CodingKey {
        case type, code, sessionID, reason, values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "pairing": self = .pairing(code: try container.decode(String.self, forKey: .code))
        case "welcome": self = .welcome(sessionID: try container.decode(String.self, forKey: .sessionID))
        case "rejected": self = .rejected(reason: try container.decode(String.self, forKey: .reason))
        case "override": self = .override(values: try container.decode([String: String?].self, forKey: .values))
        case "stateRequest": self = .stateRequest
        default: self = .unknown(type: type)
        }
    }
}

/// Decodes the `HAROLD_OVERRIDES` launch payload: base64 of a JSON string map. A bad payload gives no values.
func decodeLaunchOverrides(_ payload: String?) -> [String: String] {
    guard let payload, let data = Data(base64Encoded: payload) else { return [:] }
    return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
}
