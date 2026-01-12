import Foundation
import Combine

@MainActor
final class ManageDevicesStore: ObservableObject {
    @Published var devices: [ManagedDevice] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var savingId: String?

    private var hasLoaded = false

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false; hasLoaded = true }
        do {
            let list = try await ManageDevicesService.list()
            devices = sort(list)
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadIfNeeded() async {
        if hasLoaded { return }
        await load()
    }

    func markStolen(deviceId: String) async {
        if savingId != nil { return }
        savingId = deviceId
        defer { savingId = nil }
        do {
            try await ManageDevicesService.markStolen(deviceId: deviceId)
            await load()
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    func restore(deviceId: String) async {
        if savingId != nil { return }
        savingId = deviceId
        defer { savingId = nil }
        do {
            try await ManageDevicesService.restore(deviceId: deviceId)
            await load()
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func sort(_ list: [ManagedDevice]) -> [ManagedDevice] {
        return list.sorted { a, b in
            if a.status == .active && b.status != .active { return true }
            if a.status != .active && b.status == .active { return false }
            let aDate = parse(dateString: a.lastSeenAt)
            let bDate = parse(dateString: b.lastSeenAt)
            return aDate > bDate
        }
    }

    private func parse(dateString: String?) -> Date {
        guard let str = dateString, !str.isEmpty else { return .distantPast }
        if let date = ISO8601DateFormatter().date(from: str) {
            return date
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter.date(from: str) ?? .distantPast
    }
}
