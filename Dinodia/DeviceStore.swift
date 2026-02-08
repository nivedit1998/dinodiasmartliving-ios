import Foundation
import Combine

struct DeviceCacheEntry: Codable {
    let devices: [UIDevice]
    let updatedAt: Date
}

@MainActor
final class DeviceCache {
    static let shared = DeviceCache()
    private var memory: [String: DeviceCacheEntry] = [:]

    func entry(for key: String) -> DeviceCacheEntry? {
        memory[key]
    }

    func save(_ entry: DeviceCacheEntry, for key: String) {
        memory[key] = entry
        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func remove(_ key: String) {
        memory[key] = nil
        UserDefaults.standard.removeObject(forKey: key)
    }

    func loadFromDisk(for key: String) -> DeviceCacheEntry? {
        if let cached = memory[key] {
            return cached
        }
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DeviceCacheEntry.self, from: data)
    }
}

@MainActor
final class DeviceStore: ObservableObject {
    @Published var devices: [UIDevice] = []
    @Published var isRefreshing: Bool = false
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?

    private let userId: Int
    private let mode: HaMode
    private let cacheKey: String
    private var timer: Timer?
    private var contextCache: (UserWithRelations, HaConnection)?

    init(userId: Int, mode: HaMode) {
        self.userId = userId
        self.mode = mode
        self.cacheKey = "dinodia_devices_\(userId)_\(mode.rawValue)"
        Task {
            await loadCached()
            await refresh(background: true)
            startTimer()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh(background: Bool = false) async {
        if !background {
            isRefreshing = true
        }
        defer {
            if !background {
                isRefreshing = false
            }
        }
        do {
            if contextCache == nil {
                contextCache = try? await DinodiaService.getUserWithHaConnection(userId: userId)
            }
            let fetched = try await DinodiaService.fetchDevicesForUser(
                userId: userId,
                mode: mode,
                context: contextCache
            )
            self.devices = fetched
            self.lastUpdated = Date()
            self.errorMessage = nil
            let entry = DeviceCacheEntry(devices: fetched, updatedAt: Date())
            DeviceCache.shared.save(entry, for: cacheKey)
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
            if devices.isEmpty {
                DeviceCache.shared.save(DeviceCacheEntry(devices: [], updatedAt: Date()), for: cacheKey)
            }
        }
    }

    func reload() {
        Task {
            await refresh(background: false)
        }
    }

    private func loadCached() async {
        if let memory = DeviceCache.shared.entry(for: cacheKey) {
            devices = memory.devices
            lastUpdated = memory.updatedAt
            return
        }
        if let disk = DeviceCache.shared.loadFromDisk(for: cacheKey) {
            devices = disk.devices
            lastUpdated = disk.updatedAt
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.refresh(background: true) }
        }
    }

    static func clearCache(for userId: Int, mode: HaMode) async {
        let key = "dinodia_devices_\(userId)_\(mode.rawValue)"
        await MainActor.run {
            DeviceCache.shared.remove(key)
        }
    }

    static func clearAll(for userId: Int) async {
        await clearCache(for: userId, mode: .home)
        await clearCache(for: userId, mode: .cloud)
    }
}
