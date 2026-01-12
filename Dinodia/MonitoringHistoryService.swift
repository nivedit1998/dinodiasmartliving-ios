import Foundation
import SwiftUI

private struct MonitoringReading: Decodable {
    let entityId: String
    let haConnectionId: Int
    let capturedAt: String
    let unit: String?
    let numericValue: Double?
}

enum MonitoringHistoryError: LocalizedError {
    case unableToLoad

    var errorDescription: String? {
        "We could not load your history right now. Please try again."
    }
}

enum MonitoringHistoryService {
    static func fetchHistory(entityId: String, bucket: HistoryBucket, role: Role?) async throws -> HistoryResult {
        return try await fetchViaPlatformAPI(entityId: entityId, bucket: bucket, role: role)
    }

    private static func fetchViaPlatformAPI(entityId: String, bucket: HistoryBucket, role: Role?) async throws -> HistoryResult {
        let basePath: String
        if role == .TENANT {
            basePath = "/api/tenant/monitoring/history"
        } else {
            basePath = "/api/admin/monitoring/history"
        }
        let path = "\(basePath)?entityId=\(encodePathComponent(entityId))&bucket=\(bucket.rawValue)"
        do {
            let result: PlatformFetchResult<HistoryResult> = try await PlatformFetch.request(path, method: "GET")
            return result.data
        } catch {
            throw MonitoringHistoryError.unableToLoad
        }
    }

    private static func encodePathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func aggregate(readings: [MonitoringReading], bucket: HistoryBucket) -> HistoryResult {
        var unit: String? = nil
        var buckets: [String: (sum: Double, count: Int, label: String, start: Date)] = [:]
        for reading in readings {
            if unit == nil, let readingUnit = reading.unit, !readingUnit.isEmpty {
                unit = readingUnit
            }
            guard let numeric = reading.numericValue else { continue }
            guard let capturedDate = ISO8601DateFormatter().date(from: reading.capturedAt) else { continue }
            let info = bucketInfo(bucket: bucket, capturedAt: capturedDate)
            let existing = buckets[info.key]
            if existing == nil {
                buckets[info.key] = (numeric, 1, info.label, info.start)
            } else {
                buckets[info.key] = (existing!.sum + numeric, existing!.count + 1, info.label, info.start)
            }
        }

        let shouldUseSum = unit?.lowercased().contains("wh") == true
        let points = buckets.values
            .sorted(by: { $0.start < $1.start })
            .map { entry -> HistoryPoint in
                let value = shouldUseSum ? entry.sum : entry.sum / Double(entry.count)
                return HistoryPoint(bucketStart: iso8601String(from: entry.start), label: entry.label, value: value, count: entry.count)
            }

        return HistoryResult(unit: unit, points: points)
    }

    private static func bucketInfo(bucket: HistoryBucket, capturedAt: Date) -> (key: String, label: String, start: Date) {
        switch bucket {
        case .weekly:
            let info = isoWeekInfo(for: capturedAt)
            let label = "Week of \(formatDate(info.weekStart))"
            return ("\(info.year)-W\(String(info.week).pad(with: 2))", label, info.weekStart)
        case .monthly:
            let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: capturedAt)) ?? capturedAt
            return ("\(year(start))-\(String(month(start)).pad(with: 2))", formatMonthLabel(start), start)
        case .daily:
            fallthrough
        default:
            let start = startOfDay(capturedAt)
            return (formatDate(start), formatDate(start), start)
        }
    }

    private static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private static func year(_ date: Date) -> Int {
        Calendar.current.component(.year, from: date)
    }

    private static func month(_ date: Date) -> Int {
        Calendar.current.component(.month, from: date)
    }

    private static func isoWeekInfo(for date: Date) -> (year: Int, week: Int, weekStart: Date) {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2
        let weekOfYear = calendar.component(.weekOfYear, from: date)
        let yearForWeekOfYear = calendar.component(.yearForWeekOfYear, from: date)
        let startComponents = DateComponents(weekOfYear: weekOfYear, yearForWeekOfYear: yearForWeekOfYear)
        let weekStart = calendar.date(from: startComponents) ?? date
        return (yearForWeekOfYear, weekOfYear, weekStart)
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func formatMonthLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private extension String {
    func pad(with digits: Int) -> String {
        self.count >= digits ? self : String(repeating: "0", count: max(0, digits - self.count)) + self
    }
}
