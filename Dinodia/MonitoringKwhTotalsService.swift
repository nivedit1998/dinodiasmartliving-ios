import Foundation

struct MonitoringKwhTotalsService {
    struct BaselineResponse: Decodable {
        let ok: Bool?
        let baselines: [BaselineItem]?
        let pricePerKwh: Double?
        let error: String?
    }

    struct BaselineItem: Decodable {
        let entityId: String
        let firstKwh: Double?
    }

    static func fetchBaselines(entityIds: [String]) async throws -> (baselines: [String: Double], pricePerKwh: Double?) {
        let ids = Array(Set(entityIds.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
        if ids.isEmpty { return ([:], nil) }
        let body = try JSONSerialization.data(withJSONObject: ["entityIds": ids])
        let result: PlatformFetchResult<BaselineResponse> = try await PlatformFetch.request(
            "/api/admin/monitoring/kwh-totals",
            method: "POST",
            body: body
        )
        guard result.data.ok == true, let rows = result.data.baselines else {
            throw NSError(domain: "MonitoringKwhTotals", code: 1, userInfo: [NSLocalizedDescriptionKey: result.data.error ?? "Failed to load energy baselines"])
        }
        var map: [String: Double] = [:]
        for row in rows {
            if let value = row.firstKwh {
                map[row.entityId] = value
            }
        }
        let price = (result.data.pricePerKwh != nil && result.data.pricePerKwh!.isFinite && result.data.pricePerKwh! >= 0) ? result.data.pricePerKwh : nil
        return (map, price)
    }
}
