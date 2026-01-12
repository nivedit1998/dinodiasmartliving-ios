import Foundation

enum DeviceAdminService {
    static func updateDevice(entityId: String, name: String, blindTravelSeconds: Double?) async throws {
        var payload: [String: Any] = [
            "entityId": entityId,
            "name": name.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        if let travel = blindTravelSeconds {
            payload["blindTravelSeconds"] = travel
        } else {
            payload["blindTravelSeconds"] = NSNull()
        }

        let body = try JSONSerialization.data(withJSONObject: payload)
        let result: PlatformFetchResult<BlindTravelSecondsResponse> = try await PlatformFetch.request(
            "/api/admin/device",
            method: "POST",
            body: body
        )
        if result.data.ok == false {
            throw DinodiaServiceError.connectionMissing(
                result.data.error ?? "Unable to update this device right now."
            )
        }
    }
}
