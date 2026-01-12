import Foundation

struct DiscoveryFlow: Decodable, Identifiable {
    var id: String { flowId }
    let flowId: String
    let handler: String
    let source: String?
    let title: String
    let description: String?
}

enum CommissionStatus: String, Decodable {
    case needsInput = "NEEDS_INPUT"
    case inProgress = "IN_PROGRESS"
    case succeeded = "SUCCEEDED"
    case failed = "FAILED"
    case canceled = "CANCELED"
    case unknown
}

struct SchemaField: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let type: String?
    let required: Bool?
    let options: [String]?

    private enum CodingKeys: String, CodingKey {
        case name
        case type
        case required
        case options
    }
}

struct HaStep: Decodable {
    let type: String?
    let dataSchema: [SchemaField]?
    private enum CodingKeys: String, CodingKey {
        case type
        case dataSchema = "data_schema"
    }
}

struct CommissionSession: Decodable {
    let id: String
    let status: CommissionStatus
    let requestedArea: String?
    let requestedName: String?
    let requestedHaLabelId: String?
    let requestedDinodiaType: String?
    let requestedPairingCode: String?
    let error: String?
    let newDeviceIds: [String]?
    let newEntityIds: [String]?
    let isFinal: Bool?
    let lastHaStep: HaStep?
}

struct CommissionResponse: Decodable {
    let ok: Bool?
    let session: CommissionSession?
    let warnings: [String]?
    let error: String?
}

enum DeviceOnboardingService {
    static func listFlows() async throws -> [DiscoveryFlow] {
        struct Response: Decodable { let flows: [DiscoveryFlow]?; let error: String? }
        let result: PlatformFetchResult<Response> = try await PlatformFetch.request("/api/tenant/homeassistant/discovery", method: "GET")
        if let err = result.data.error, !err.isEmpty { throw PlatformFetchError.network(err) }
        return result.data.flows ?? []
    }

    static func startSession(
        flowId: String,
        area: String,
        name: String?,
        haLabelId: String?,
        dinodiaType: String?,
        pairingCode: String?
    ) async throws -> CommissionResponse {
        let payload: [String: Any?] = [
            "flowId": flowId,
            "requestedArea": area,
            "requestedName": (name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true) ? nil : name,
            "requestedHaLabelId": (haLabelId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true) ? nil : haLabelId,
            "requestedDinodiaType": (dinodiaType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true) ? nil : dinodiaType,
            "pairingCode": (pairingCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true) ? nil : pairingCode
        ]
        let body = try JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 })
        let result: PlatformFetchResult<CommissionResponse> = try await PlatformFetch.request("/api/tenant/discovery/sessions", method: "POST", body: body)
        return result.data
    }

    static func step(sessionId: String, userInput: [String: Any]) async throws -> CommissionResponse {
        let body = try JSONSerialization.data(withJSONObject: ["userInput": userInput])
        let result: PlatformFetchResult<CommissionResponse> = try await PlatformFetch.request("/api/tenant/discovery/sessions/\(sessionId)/step", method: "POST", body: body)
        return result.data
    }

    static func cancel(sessionId: String) async throws -> CommissionResponse {
        let result: PlatformFetchResult<CommissionResponse> = try await PlatformFetch.request("/api/tenant/discovery/sessions/\(sessionId)/cancel", method: "POST")
        return result.data
    }
}
