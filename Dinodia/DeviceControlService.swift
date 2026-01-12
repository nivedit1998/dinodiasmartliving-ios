import Foundation

enum DeviceControlService {
    struct CommandPayload: Encodable {
        let entityId: String
        let command: String
        let value: Double?
    }

    static func sendCloudCommand(entityId: String, command: String, value: Double? = nil) async throws {
        let payload = CommandPayload(entityId: entityId, command: command, value: value)
        let body = try JSONEncoder().encode(payload)
        struct Response: Decodable { let ok: Bool?; let error: String? }
        let result: PlatformFetchResult<Response> = try await PlatformFetch.request("/api/device-control", method: "POST", body: body)
        if result.data.ok == false {
            throw PlatformFetchError.network(result.data.error ?? "Dinodia Cloud could not run that action. Please try again.")
        }
    }
}
