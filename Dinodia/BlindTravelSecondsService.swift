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
    private static var cache: [String: (ts: Date, overrides: [String: Double?])] = [:]
    private static let ttl: TimeInterval = 24 * 60 * 60

    private static func cacheKey(entityIds: [String], haConnectionId: Int) -> String {
        let sorted = entityIds.sorted().joined(separator: ",")
        return "\(haConnectionId)::\(sorted)"
    }

    static func fetchCached(entityIds: [String], haConnectionId: Int) async throws -> [String: Double?] {
        let key = cacheKey(entityIds: entityIds, haConnectionId: haConnectionId)
        if let entry = cache[key], Date().timeIntervalSince(entry.ts) < ttl {
            return entry.overrides
        }
        let overrides = try await fetch(entityIds: entityIds)
        cache[key] = (Date(), overrides)
        return overrides
    }

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
