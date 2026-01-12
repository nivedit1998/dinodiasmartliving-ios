import Foundation

struct TenantRecord: Decodable, Identifiable {
    let id: Int
    let username: String
    let areas: [String]
}

struct SellingTargets: Decodable {
    let deviceIds: [String]
    let entityIds: [String]
    let automationIds: [String]

    init(deviceIds: [String] = [], entityIds: [String] = [], automationIds: [String] = []) {
        self.deviceIds = deviceIds
        self.entityIds = entityIds
        self.automationIds = automationIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let devices = try container.decodeIfPresent([String].self, forKey: .deviceIds) ?? []
        let entities = try container.decodeIfPresent([String].self, forKey: .entityIds) ?? []
        let automations = try container.decodeIfPresent([String].self, forKey: .automationIds) ?? []
        self.init(deviceIds: devices, entityIds: entities, automationIds: automations)
    }

    private enum CodingKeys: String, CodingKey {
        case deviceIds
        case entityIds
        case automationIds
    }
}

enum AdminServiceError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let message):
            return message
        }
    }
}

enum AdminService {
    struct TenantsResponse: Decodable {
        let ok: Bool?
        let tenants: [TenantRecord]?
        let error: String?
    }

    struct TenantResponse: Decodable {
        let ok: Bool?
        let tenantId: Int?
        let tenant: TenantRecord?
        let error: String?
    }

    struct SellingResponse: Decodable {
        let ok: Bool?
        let targets: SellingTargets?
        let automationIds: [String]?
        let claimCode: String?
        let error: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            ok = try container.decodeIfPresent(Bool.self, forKey: .ok)
            targets = try container.decodeIfPresent(SellingTargets.self, forKey: .targets) ?? SellingTargets()
            automationIds = try container.decodeIfPresent([String].self, forKey: .automationIds) ?? []
            claimCode = try container.decodeIfPresent(String.self, forKey: .claimCode)
            error = try container.decodeIfPresent(String.self, forKey: .error)
        }

        private enum CodingKeys: String, CodingKey {
            case ok
            case targets
            case automationIds
            case claimCode
            case error
        }
    }

    static func fetchTenants() async throws -> [TenantRecord] {
        let result: PlatformFetchResult<TenantsResponse> = try await PlatformFetch.request("/api/admin/tenant", method: "GET")
        if result.data.ok == false {
            throw AdminServiceError.server(result.data.error ?? "Failed to load users.")
        }
        return result.data.tenants ?? []
    }

    static func createTenant(username: String, password: String, areas: [String]) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "username": username,
            "password": password,
            "areas": areas
        ])
        let result: PlatformFetchResult<TenantResponse> = try await PlatformFetch.request("/api/admin/tenant", method: "POST", body: body)
        if result.data.ok == false {
            throw AdminServiceError.server(result.data.error ?? "We couldn't create this user right now. Please try again.")
        }
    }

    static func updateTenantAreas(id: Int, areas: [String]) async throws -> TenantRecord {
        let body = try JSONSerialization.data(withJSONObject: ["areas": areas])
        let result: PlatformFetchResult<TenantResponse> = try await PlatformFetch.request("/api/admin/tenant/\(id)", method: "PATCH", body: body)
        if result.data.ok == false || result.data.tenant == nil {
            throw AdminServiceError.server(result.data.error ?? "Failed to update user areas.")
        }
        return result.data.tenant!
    }

    static func deleteTenant(id: Int) async throws {
        let result: PlatformFetchResult<TenantResponse> = try await PlatformFetch.request("/api/admin/tenant/\(id)", method: "DELETE")
        if result.data.ok == false {
            throw AdminServiceError.server(result.data.error ?? "Failed to delete user.")
        }
    }

    static func fetchSellingTargets() async throws -> SellingTargets {
        let result: PlatformFetchResult<SellingResponse> = try await PlatformFetch.request("/api/admin/selling-property", method: "GET")
        if result.data.ok == false {
            throw AdminServiceError.server(result.data.error ?? "Failed to load cleanup targets.")
        }
        let targets = result.data.targets ?? SellingTargets()
        return SellingTargets(
            deviceIds: targets.deviceIds,
            entityIds: targets.entityIds,
            automationIds: result.data.automationIds ?? targets.automationIds
        )
    }

    static func deregisterProperty(mode: String, cleanup: String? = nil) async throws -> String? {
        var payload: [String: Any] = ["mode": mode]
        if let cleanup { payload["cleanup"] = cleanup }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let result: PlatformFetchResult<SellingResponse> = try await PlatformFetch.request("/api/admin/selling-property", method: "POST", body: body)
        if result.data.ok == false {
            throw AdminServiceError.server(result.data.error ?? "We could not complete this request. Please try again.")
        }
        return result.data.claimCode
    }
}
