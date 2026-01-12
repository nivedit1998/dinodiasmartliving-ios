import Foundation
import Security

struct HomeModeSecrets: Codable {
    let baseUrl: String
    let longLivedToken: String
}

enum HomeModeSecretsStore {
    private static var cache: HomeModeSecrets?
    private static var inflight: Task<HomeModeSecrets, Error>?
    private static let configuringNeedles = [
        "no published hub token",
        "hub agent is not linked to this home",
        "hub not paired yet",
    ]

    static func isConfiguringError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return configuringNeedles.contains { message.contains($0) }
    }

    static func fetch(force: Bool = false) async throws -> HomeModeSecrets {
        if !force, let cached = cache { return cached }
        if !force, let inflight { return try await inflight.value }

        if force {
            inflight?.cancel()
            inflight = nil
            let secrets = try await fetchFromPlatform()
            persist(secrets)
            return secrets
        } else {
            let task: Task<HomeModeSecrets, Error> = Task {
                defer { inflight = nil }
                // Try keychain first for persistence across restarts.
                if let userId = SessionStore.currentUserId(), let saved = HomeModeSecretsKeychain.load(for: userId) {
                    cache = saved
                    return saved
                }
                let secrets = try await fetchFromPlatform()
                persist(secrets)
                return secrets
            }
            inflight = task
            return try await task.value
        }
    }

    static func cached() -> HomeModeSecrets? {
        if let cached = cache { return cached }
        if let userId = SessionStore.currentUserId(), let saved = HomeModeSecretsKeychain.load(for: userId) {
            cache = saved
            return saved
        }
        return nil
    }

    static func clear(userId: Int? = nil) {
        cache = nil
        inflight = nil
        let uid = userId ?? SessionStore.currentUserId()
        if let userId = uid {
            HomeModeSecretsKeychain.clear(for: userId)
        }
    }

    static func cacheSecrets(baseUrl: String, token: String) {
        let secrets = HomeModeSecrets(baseUrl: baseUrl, longLivedToken: token)
        persist(secrets)
    }

    private static func persist(_ secrets: HomeModeSecrets) {
        cache = secrets
        if let userId = SessionStore.currentUserId() {
            HomeModeSecretsKeychain.save(secrets, for: userId)
        }
    }

    private static func fetchFromPlatform() async throws -> HomeModeSecrets {
        let result: PlatformFetchResult<HomeModeSecrets> = try await PlatformFetch.request("/api/kiosk/home-mode/secrets", method: "POST")
        let secrets = result.data
        guard !secrets.baseUrl.isEmpty, !secrets.longLivedToken.isEmpty else {
            throw PlatformFetchError.network("We could not load Dinodia Hub access details. Please try again.")
        }
        let normalizedBase = secrets.baseUrl.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard let url = URL(string: normalizedBase), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw PlatformFetchError.network("Invalid Dinodia Hub URL. Please save Home Mode again.")
        }
        if scheme == "http" {
            let host = (url.host ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !LocalNetwork.isLocalHost(host) {
                throw PlatformFetchError.network("Dinodia Hub over http:// is only allowed on the local network.")
            }
        }
        return HomeModeSecrets(baseUrl: normalizedBase, longLivedToken: secrets.longLivedToken)
    }
}

private enum HomeModeSecretsKeychain {
    private static func key(userId: Int) -> String { "com.dinodia.home.mode.secrets.\(userId)" }

    static func save(_ secrets: HomeModeSecrets, for userId: Int) {
        guard userId > 0 else { return }
        let k = key(userId: userId)
        guard let data = try? JSONEncoder().encode(secrets) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: k,
            kSecAttrAccount as String: k,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func load(for userId: Int) -> HomeModeSecrets? {
        guard userId > 0 else { return nil }
        let k = key(userId: userId)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: k,
            kSecAttrAccount as String: k,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(HomeModeSecrets.self, from: data)
    }

    static func clear(for userId: Int) {
        guard userId > 0 else { return }
        let k = key(userId: userId)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: k,
            kSecAttrAccount as String: k,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
