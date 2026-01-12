import Foundation

enum DinodiaServiceError: LocalizedError {
    case userNotFound
    case connectionMissing(String)

    var errorDescription: String? {
        switch self {
        case .userNotFound:
            return "User not found"
        case .connectionMissing(let message):
            return message
        }
    }
}

enum DinodiaService {
    struct KioskContextUser: Decodable {
        let id: Int
        let username: String
        let role: Role
        let homeId: Int?
    }

    struct KioskContextResponse: Decodable {
        let user: KioskContextUser?
        let haConnection: HaConnection?
        let accessRules: [AccessRule]?
    }

    private static func fetchKioskContext() async throws -> (UserWithRelations, HaConnection) {
        let result: PlatformFetchResult<KioskContextResponse> = try await PlatformFetch.request("/api/kiosk/context", method: "GET")
        guard let user = result.data.user, let ha = result.data.haConnection else {
            throw DinodiaServiceError.connectionMissing("Dinodia Hub connection is not configured for this account.")
        }
        let access = (result.data.accessRules ?? []).filter { !$0.area.isEmpty }
        let summary = UserSummary(id: user.id, username: user.username, role: user.role, haConnectionId: ha.id)
        return (UserWithRelations(summary: summary, accessRules: access), ha)
    }

    static func getUserWithHaConnection(userId: Int) async throws -> (UserWithRelations, HaConnection) {
        // userId is unused because platform resolves from the active token, but keep signature for compatibility.
        return try await fetchKioskContext()
    }

    static func fetchDevicesForUser(userId: Int, mode: HaMode) async throws -> [UIDevice] {
        let (relations, _) = try await getUserWithHaConnection(userId: userId)

        if mode == .cloud {
            struct DevicesResponse: Decodable { let devices: [UIDevice]?; let error: String? }
            let response: PlatformFetchResult<DevicesResponse> = try await PlatformFetch.request("/api/devices?fresh=1", method: "GET")
            if let err = response.data.error, !err.isEmpty {
                throw DinodiaServiceError.connectionMissing(err)
            }
            let list = response.data.devices ?? []
            if relations.summary.role == .TENANT {
                let allowed = Set(relations.accessRules.map { $0.area })
                return list.filter { device in
                    guard let area = device.areaName ?? device.area else { return false }
                    return allowed.contains(area)
                }
            }
            return list
        }

        let secrets = try await HomeModeSecretsStore.fetch()
        let haLike = HaConnectionLike(baseUrl: secrets.baseUrl, longLivedToken: secrets.longLivedToken)
        let reachable = await HAService.probeHaReachability(haLike, timeout: 2.0)
        if !reachable {
            throw DinodiaServiceError.connectionMissing(
                "We cannot find your Dinodia Hub on the home Wi‑Fi. Switch to Dinodia Cloud to control your place."
            )
        }

        let enriched = try await HAService.getDevicesWithMetadata(haLike)
        var devices: [UIDevice] = enriched.map { device in
            let labels = device.labels
            let labelCategory = classifyDeviceByLabel(labels) ?? device.labelCategory
            let primaryLabel = labels.first ?? labelCategory
            return UIDevice(
                entityId: device.entityId,
                deviceId: device.deviceId,
                name: device.name,
                state: device.state,
                area: device.areaName,
                areaName: device.areaName,
                label: primaryLabel,
                labelCategory: labelCategory,
                labels: labels,
                domain: device.domain,
                attributes: device.attributes,
                blindTravelSeconds: nil
            )
        }

        if relations.summary.role == .TENANT {
            let rules = Set(relations.accessRules.map { $0.area })
            devices = devices.filter { device in
                guard let areaName = device.areaName else { return false }
                return rules.contains(areaName)
            }
        }

        let coverEntityIds = devices
            .filter { $0.entityId.hasPrefix("cover.") }
            .map { $0.entityId }
        if !coverEntityIds.isEmpty {
            do {
                let overrides = try await BlindTravelSecondsService.fetch(entityIds: coverEntityIds)
                if !overrides.isEmpty {
                    devices = devices.map { device in
                        if let override = overrides[device.entityId],
                           let seconds = override,
                           seconds.isFinite,
                           seconds > 0 {
                            return UIDevice(
                                entityId: device.entityId,
                                deviceId: device.deviceId,
                                name: device.name,
                                state: device.state,
                                area: device.area,
                                areaName: device.areaName,
                                label: device.label,
                                labelCategory: device.labelCategory,
                                labels: device.labels,
                                domain: device.domain,
                                attributes: device.attributes,
                                blindTravelSeconds: seconds
                            )
                        }
                        return device
                    }
                }
            } catch {
                // Ignore and fall back to defaults.
            }
        }

        return devices
    }

    struct UpdateHaSettingsParams {
        let adminId: Int
        let haUsername: String
        let haBaseUrl: String
        let haCloudUrl: String?
        let haPassword: String?
        let haLongLivedToken: String?
    }

    static func updateHaSettings(_ params: UpdateHaSettingsParams) async throws -> HaConnection {
        let (_, existingConnection) = try await getUserWithHaConnection(userId: params.adminId)
        let normalizedBase = try normalizeHaBaseUrl(params.haBaseUrl)
        var payload: [String: Any] = [
            "haUsername": params.haUsername.trimmingCharacters(in: .whitespacesAndNewlines),
            "haBaseUrl": normalizedBase,
        ]
        if let cloud = params.haCloudUrl {
            let trimmed = cloud.trimmingCharacters(in: .whitespacesAndNewlines)
            payload["haCloudUrl"] = trimmed.isEmpty ? NSNull() : trimmed
        }
        if let password = params.haPassword, !password.isEmpty {
            payload["haPassword"] = password
        }
        if let token = params.haLongLivedToken, !token.isEmpty {
            payload["haLongLivedToken"] = token
        }

        let body = try JSONSerialization.data(withJSONObject: payload)
        struct UpdateResponse: Decodable {
            let ok: Bool?
            let haUsername: String?
            let haBaseUrl: String?
            let cloudEnabled: Bool?
            let error: String?
        }
        let result: PlatformFetchResult<UpdateResponse> = try await PlatformFetch.request("/api/admin/profile/ha-settings", method: "PUT", body: body)
        if result.data.ok == false {
            throw DinodiaServiceError.connectionMissing(result.data.error ?? "We could not save these Dinodia Hub settings. Please try again.")
        }

        return HaConnection(
            id: existingConnection.id,
            baseUrl: result.data.haBaseUrl ?? normalizedBase,
            cloudUrl: params.haCloudUrl,
            haUsername: result.data.haUsername ?? params.haUsername,
            haPassword: "",
            longLivedToken: params.haLongLivedToken ?? "",
            ownerId: existingConnection.ownerId,
            cloudEnabled: result.data.cloudEnabled
        )
    }

    private static func normalizeHaBaseUrl(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw DinodiaServiceError.connectionMissing("Dinodia Hub URL must start with http:// or https://")
        }
        if scheme == "http" {
            let host = (url.host ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !LocalNetwork.isLocalHost(host) {
                throw DinodiaServiceError.connectionMissing("For security, http:// Dinodia Hub URLs are only allowed on the local network.")
            }
        }
        var cleaned = trimmed
        while cleaned.hasSuffix("/") {
            cleaned.removeLast()
        }
        return cleaned
    }
}
