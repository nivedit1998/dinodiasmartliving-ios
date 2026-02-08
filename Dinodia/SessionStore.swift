import Foundation
import Combine
import Network
import UIKit
import WebKit

enum LoginOutcome {
    case success
    case needsEmail
    case challenge(String)
}

@MainActor
final class SessionStore: ObservableObject {
    @Published var user: AuthUser? = nil {
        didSet {
            SessionStore.lastKnownUserId = user?.id
        }
    }
    @Published var haMode: HaMode = .home
    @Published var isLoading: Bool = true
    @Published var haConnection: HaConnection?
    @Published var onHomeNetwork: Bool = false
    @Published var cloudAvailable: Bool = false
    @Published var isConfiguringHub: Bool = false
    @Published var hubConfiguringError: String?
    @Published private(set) var hasEverFetchedHomeSecrets: Bool = false
    @Published private(set) var homeHubStatus: HomeHubStatus = .unknown
    private static var lastKnownUserId: Int?

    private let storageKey = "dinodia_session_v1"
    private var verifyTimer: Timer?
    private var pathMonitor: NWPathMonitor?
    private var lastInterfaceWasWifi: Bool?
    private var isResetting = false
    private var homeNetworkTask: Task<Void, Never>?
    private var cloudTask: Task<Void, Never>?
    private var homeReachabilityLossTask: Task<Void, Never>?
    private var homeHubProbeTask: Task<Void, Never>?
    private var homeHubConsecutiveFailures: Int = 0
    private var homeHubLastSuccessAt: Date?

    init() {
        SessionInvalidation.setHandler { [weak self] in
            Task { await self?.resetApp() }
        }
        loadSession()
        startNetworkMonitor()
        startLifecycleObservers()
        startVerifyTimer()
    }

    private func loadSession() {
        defer { isLoading = false }
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }
        do {
            let payload = try JSONDecoder().decode(SessionPayload.self, from: data)
            user = payload.user
            // Restore last-selected mode; fallback to home if missing.
            haMode = payload.haMode
            haConnection = nil
            Task { await self.refreshConnection() }
        } catch {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }

    private func saveSession() {
        guard let currentUser = user else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            return
        }
        // Do not persist HA secrets; only persist user and mode.
        let payload = SessionPayload(user: currentUser, haMode: haMode, haConnection: nil)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        // Cache platform token for background fetches (already stored in keychain).
    }

    static func currentUserId() -> Int? {
        return lastKnownUserId
    }

    func login(username: String, password: String, email: String? = nil) async throws -> LoginOutcome {
        let step = try await AuthService.login(username: username, password: password, email: email)
        switch step {
        case .ok:
            try await finalizeLogin()
            return .success
        case .needsEmail:
            return .needsEmail
        case .challenge(let id):
            return .challenge(id)
        }
    }

    func finalizeLogin() async throws {
        let (context, connection) = try await DinodiaService.getUserWithHaConnection(userId: user?.id ?? 0)
        let newUser = AuthUser(id: context.summary.id, username: context.summary.username, role: context.summary.role)
        if let existingId = user?.id, existingId != newUser.id {
            await DeviceStore.clearAll(for: existingId)
            HomeModeSecretsStore.clear(userId: existingId)
        }
        hasEverFetchedHomeSecrets = false
        await DeviceStore.clearAll(for: newUser.id)
        user = newUser
        SessionStore.lastKnownUserId = newUser.id
        haConnection = connection
        haMode = .home
        saveSession()
        // Persist Home Mode secrets for offline auth parity.
        // Prefetch home-mode secrets (hub agent + hub token) after login; ignore errors.
        Task { await ensureHomeModeSecretsReady() }
    }

    func logout() {
        Task { await resetApp() }
    }

    func resetApp() async {
        if isResetting { return }
        isResetting = true
        defer { isResetting = false }

        verifyTimer?.invalidate()
        verifyTimer = nil
        homeReachabilityLossTask?.cancel()
        homeReachabilityLossTask = nil
        let userId = user?.id
        // Attempt server-side logout before clearing local auth state.
        await AuthService.logoutRemote()

        user = nil
        SessionStore.lastKnownUserId = nil
        haMode = .home
            haConnection = nil
            onHomeNetwork = false
            homeHubStatus = .unknown
            cloudAvailable = false
            hasEverFetchedHomeSecrets = false
            lastInterfaceWasWifi = nil
            homeNetworkTask?.cancel()
            homeNetworkTask = nil
        cloudTask?.cancel()
        cloudTask = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
        HomeModeSecretsStore.clear(userId: userId)
        // Clear tokens/cookies/web state after server logout.
        PlatformTokenStore.clear()
        clearWebSessionState()
        if let userId {
            await DeviceStore.clearAll(for: userId)
            UserDefaults.standard.removeObject(forKey: "tenant_selected_area_\(userId)")
        }
    }

    func setHaMode(_ mode: HaMode) {
        homeReachabilityLossTask?.cancel()
        homeReachabilityLossTask = nil
        haMode = mode
        saveSession()
        restartHomeNetworkPollingIfNeeded()
        restartCloudPollingIfNeeded()
    }

    func ensureHomeModeSecretsReady(maxWaitSeconds: Int = 300) async {
        guard haMode == .home else { return }
        isConfiguringHub = true
        hubConfiguringError = nil
        let started = Date()
        if let _ = HomeModeSecretsStore.cached() {
            isConfiguringHub = false
            hubConfiguringError = nil
            hasEverFetchedHomeSecrets = true
            return
        }
        while true {
            do {
                _ = try await HomeModeSecretsStore.fetch(force: true)
                isConfiguringHub = false
                hubConfiguringError = nil
                hasEverFetchedHomeSecrets = true
                return
            } catch {
                if HomeModeSecretsStore.isConfiguringError(error) {
                    let elapsed = Date().timeIntervalSince(started)
                    if elapsed >= Double(maxWaitSeconds) {
                        isConfiguringHub = false
                        hubConfiguringError = "We are still configuring your Dinodia Hub. Please retry or log out."
                        return
                    }
                    try? await Task.sleep(nanoseconds: 12 * 1_000_000_000) // 12s
                    continue
                }
                hasEverFetchedHomeSecrets = hasEverFetchedHomeSecrets || HomeModeSecretsStore.cached() != nil
                isConfiguringHub = false
                hubConfiguringError = hasEverFetchedHomeSecrets ? nil : error.localizedDescription
                return
            }
        }
    }

    func updateConnection(_ connection: HaConnection) {
        haConnection = connection
        saveSession()
    }

    func connection(for mode: HaMode) -> HaConnectionLike? {
        if mode == .home {
            // Home mode always uses hub-agent secrets from platform.
            if let cached = HomeModeSecretsStore.cached() {
                return HaConnectionLike(baseUrl: cached.baseUrl, longLivedToken: cached.longLivedToken)
            }
            return nil
        }

        // Cloud mode uses platform APIs; no direct HA connection required/stored.
        return nil
    }

    // MARK: - Private helpers

    private func refreshConnection() async {
        guard let userId = user?.id else { return }
        do {
            let (context, connection) = try await DinodiaService.getUserWithHaConnection(userId: userId)
            user = AuthUser(id: context.summary.id, username: context.summary.username, role: context.summary.role)
            haConnection = connection
            saveSession()
        } catch {
            // If unauthorized, SessionInvalidation will handle logout via PlatformFetch; ignore transient errors.
        }
    }

    private func verifyUserStillExists() async {
        guard !isLoading, let userId = user?.id else { return }
        struct MeResponse: Decodable { let user: AuthUser? }
        do {
            let result: PlatformFetchResult<MeResponse> = try await PlatformFetch.request("/api/auth/me", method: "GET")
            if result.data.user?.id != userId {
                await resetApp()
            }
        } catch {
            // Ignore transient failures; will retry on next tick or foreground.
        }
    }

    private func startVerifyTimer() {
        verifyTimer?.invalidate()
        verifyTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.verifyUserStillExists() }
        }
    }

    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let isWifi = path.usesInterfaceType(.wifi)
                self.lastInterfaceWasWifi = isWifi
                if self.user == nil { return }
                if !isWifi {
                    self.onHomeNetwork = false
                    return
                }
                await self.updateHomeNetworkStatus(isFromNetworkChange: true)
            }
        }
        monitor.start(queue: DispatchQueue(label: "dinodia.network.monitor"))
    }

    private func clearWebSessionState() {
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        URLCache.shared.removeAllCachedResponses()

        let credentialStorage = URLCredentialStorage.shared
        for (protectionSpace, credentials) in credentialStorage.allCredentials {
            for (_, credential) in credentials {
                credentialStorage.remove(credential, for: protectionSpace)
            }
        }

        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().fetchDataRecords(ofTypes: types) { records in
            WKWebsiteDataStore.default().removeData(ofTypes: types, for: records) {}
        }
    }

    private func startLifecycleObservers() {
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.verifyUserStillExists()
                await self.refreshConnection()
                await self.updateHomeNetworkStatus()
                await self.updateCloudAvailability()
                await MainActor.run {
                    self.restartHomeNetworkPollingIfNeeded()
                    self.restartCloudPollingIfNeeded()
                }
            }
        }
    }

    // MARK: - Home network reachability (Home mode only)

    func updateHomeNetworkStatus(isFromNetworkChange: Bool = false) async {
        let isWifi = lastInterfaceWasWifi ?? false
        if lastInterfaceWasWifi == nil {
            // Unknown yet: optimistic probe once
        } else if !isWifi {
            await MainActor.run {
                self.onHomeNetwork = false
                self.homeHubStatus = .unreachable
            }
            return
        }
        guard haMode == .home else {
            await MainActor.run {
                self.onHomeNetwork = false
                self.homeHubStatus = .unknown
            }
            return
        }
        guard let secrets = try? await HomeModeSecretsStore.fetch() else {
            await MainActor.run {
                self.onHomeNetwork = false
                self.homeHubStatus = .unreachable
            }
            return
        }
        let ha = HaConnectionLike(baseUrl: secrets.baseUrl, longLivedToken: secrets.longLivedToken)
        homeHubProbeTask?.cancel()
        homeHubProbeTask = Task {
            await MainActor.run {
                if self.homeHubStatus == .unknown {
                    self.homeHubStatus = .checking
                } else if self.homeHubStatus == .reachable {
                    // keep last stable display; internal state moves to reconnecting
                    self.homeHubStatus = .reconnecting
                }
            }
            let reachable = await HAService.probeHaReachability(ha, timeout: 4.0)
            await MainActor.run {
                if reachable {
                    self.homeHubConsecutiveFailures = 0
                    self.homeHubLastSuccessAt = Date()
                    self.onHomeNetwork = true
                    self.homeHubStatus = .reachable
                } else {
                    self.homeHubConsecutiveFailures += 1
                    let exceededFailures = self.homeHubConsecutiveFailures >= 3
                    let exceededTime = {
                        guard let last = self.homeHubLastSuccessAt else { return false }
                        return Date().timeIntervalSince(last) > 10
                    }()
                    if exceededFailures || exceededTime {
                        self.onHomeNetwork = false
                        self.homeHubStatus = .unreachable
                    } else {
                        // Avoid flapping on transient failures; keep reconnecting state but do not drop onHomeNetwork yet.
                        self.homeHubStatus = .reconnecting
                    }
                }
            }
        }
    }

    private func restartHomeNetworkPollingIfNeeded() {
        homeNetworkTask?.cancel()
        homeNetworkTask = nil
        guard user != nil, haMode == .home else { return }
        homeNetworkTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.user != nil, self.haMode == .home {
                await self.updateHomeNetworkStatus()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    // MARK: - Cloud reachability (Cloud mode only)

    func updateCloudAvailability() async {
        guard haMode == .cloud else {
            await MainActor.run { self.cloudAvailable = false }
            return
        }
        let reachable = await CloudService.checkPlatformReachable()
        await MainActor.run {
            self.cloudAvailable = reachable
        }
    }

    private func restartCloudPollingIfNeeded() {
        cloudTask?.cancel()
        cloudTask = nil
        guard user != nil, haMode == .cloud else { return }
        cloudTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.user != nil, self.haMode == .cloud {
                await self.updateCloudAvailability()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }
}
