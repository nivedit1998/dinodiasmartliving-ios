import Foundation

struct BlindTravelSecondsOverride: Decodable {
    let entityId: String
    let blindTravelSeconds: Double?
}

struct BlindTravelSecondsResponse: Decodable {
    let ok: Bool?
    let overrides: [BlindTravelSecondsOverride]?
    let error: String?
}

enum BlindTravelSecondsService {
    static func fetch(entityIds: [String]) async throws -> [String: Double?] {
        if entityIds.isEmpty { return [:] }

        let body = try JSONSerialization.data(withJSONObject: ["entityIds": entityIds])
        let result: PlatformFetchResult<BlindTravelSecondsResponse> = try await PlatformFetch.request(
            "/api/kiosk/blinds/travel-seconds",
            method: "POST",
            body: body
        )

        if result.data.ok == false {
            throw DinodiaServiceError.connectionMissing(
                result.data.error ?? "Unable to load blind travel time overrides."
            )
        }

        var map: [String: Double?] = [:]
        for override in result.data.overrides ?? [] {
            map[override.entityId] = override.blindTravelSeconds
        }
        return map
    }
}
