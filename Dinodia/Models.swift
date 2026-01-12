import Foundation

enum Role: String, Codable {
    case ADMIN
    case TENANT
}

struct AuthUser: Codable {
    let id: Int
    let username: String
    let role: Role
}

struct UserSummary: Codable {
    let id: Int
    let username: String
    let role: Role
    let haConnectionId: Int?
}

enum HaMode: String, Codable {
    case home
    case cloud
}

struct SessionPayload: Codable {
    let user: AuthUser
    let haMode: HaMode
    let haConnection: HaConnection?
}

struct UserWithRelations {
    let summary: UserSummary
    let accessRules: [AccessRule]
}

struct HaConnection: Codable {
    let id: Int
    let baseUrl: String?
    let cloudUrl: String?
    let haUsername: String?
    let haPassword: String?
    let longLivedToken: String?
    let ownerId: Int?
    let cloudEnabled: Bool?
}

struct HaConnectionLike {
    let baseUrl: String
    let longLivedToken: String
}

struct AccessRule: Codable {
    let id: Int?
    let userId: Int?
    let area: String
}

struct UIDevice: Codable, Identifiable {
    var id: String { entityId }
    let entityId: String
    let deviceId: String?
    let name: String
    let state: String
    let area: String?
    let areaName: String?
    let label: String?
    let labelCategory: String?
    let labels: [String]?
    let domain: String
    let attributes: [String: CodableValue]
    let blindTravelSeconds: Double?
}

struct DeviceOverride: Codable {
    let id: Int
    let haConnectionId: Int
    let entityId: String
    let name: String
    let area: String?
    let label: String?
}

enum CodableValue: Codable, Hashable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([CodableValue])
    case dictionary([String: CodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([CodableValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: CodableValue].self) {
            self = .dictionary(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var anyValue: Any? {
        switch self {
        case .bool(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .string(let value):
            return value
        case .array(let value):
            return value.map { $0.anyValue }
        case .dictionary(let dict):
            return dict.mapValues { $0.anyValue }
        case .null:
            return nil
        }
    }
}

enum HistoryBucket: String, CaseIterable, Codable {
    case daily
    case weekly
    case monthly
}

struct HistoryPoint: Identifiable, Codable {
    var id: String { bucketStart }
    let bucketStart: String
    let label: String
    let value: Double
    let count: Int
}

struct HistoryResult: Codable {
    let unit: String?
    let points: [HistoryPoint]
}
