import Foundation

enum ManagedDeviceStatus: String, Decodable {
    case active = "ACTIVE"
    case stolen = "STOLEN"
    case blocked = "BLOCKED"
}

struct ManagedDevice: Decodable, Identifiable {
    let id: String
    let deviceId: String
    let label: String?
    let registryLabel: String?
    let firstSeenAt: String?
    let lastSeenAt: String?
    let revokedAt: String?
    let status: ManagedDeviceStatus
}

enum ManageDevicesServiceError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let msg):
            return msg
        }
    }
}

enum ManageDevicesService {
    private struct ListResponse: Decodable {
        let devices: [ManagedDevice]?
        let error: String?
    }

    static func list() async throws -> [ManagedDevice] {
        let result: PlatformFetchResult<ListResponse> = try await PlatformFetch.request("/api/devices/manage", method: "GET")
        if let error = result.data.error, !error.isEmpty {
            throw ManageDevicesServiceError.server(error)
        }
        return result.data.devices ?? []
    }

    static func markStolen(deviceId: String) async throws {
        guard !deviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ManageDevicesServiceError.server("Device id is required.")
        }
        let body = try JSONSerialization.data(withJSONObject: ["deviceId": deviceId])
        let result: PlatformFetchResult<StatusResponse> = try await PlatformFetch.request("/api/devices/manage/stolen", method: "POST", body: body)
        if result.data.ok == false {
            throw ManageDevicesServiceError.server(result.data.error ?? "Unable to mark device as stolen.")
        }
    }

    static func restore(deviceId: String) async throws {
        guard !deviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ManageDevicesServiceError.server("Device id is required.")
        }
        let body = try JSONSerialization.data(withJSONObject: ["deviceId": deviceId])
        let result: PlatformFetchResult<StatusResponse> = try await PlatformFetch.request("/api/devices/manage/restore", method: "POST", body: body)
        if result.data.ok == false {
            throw ManageDevicesServiceError.server(result.data.error ?? "Unable to restore device.")
        }
    }
}

private struct StatusResponse: Decodable {
    let ok: Bool?
    let error: String?
}
