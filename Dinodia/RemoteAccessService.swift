import Foundation

enum RemoteAccessStatus: String {
    case checking
    case enabled
    case locked
}

enum RemoteAccessService {
    private struct AlexaDevicesResponse: Decodable {
        let devices: [AnyCodable]?
        let error: String?
    }

    struct StepUpResponse: Decodable {
        let ok: Bool?
        let challengeId: String?
        let error: String?
    }

    struct LeaseResponse: Decodable {
        let ok: Bool?
        let leaseToken: String?
        let expiresAt: String?
        let error: String?
        let stepUpRequired: Bool?
    }

    struct SecretsResponse: Decodable {
        let haUsername: String?
        let haPassword: String?
        let error: String?
        let stepUpRequired: Bool?
    }

    struct CloudUrlResponse: Decodable {
        let ok: Bool?
        let cloudEnabled: Bool?
        let error: String?
    }

    static func checkRemoteAccessEnabled() async -> Bool {
        do {
            let result: PlatformFetchResult<AlexaDevicesResponse> = try await PlatformFetch.request("/api/alexa/devices", method: "GET")
            let devices = result.data.devices ?? []
            return !devices.isEmpty
        } catch {
            return false
        }
    }

    static func checkHomeReachable() async -> Bool {
        guard let secrets = try? await HomeModeSecretsStore.fetch() else { return false }
        let ha = HaConnectionLike(baseUrl: secrets.baseUrl, longLivedToken: secrets.longLivedToken)
        return await HAService.probeHaReachability(ha, timeout: 2.0)
    }

    static func startStepUp() async throws -> String {
        let body = "{}".data(using: .utf8)
        let result: PlatformFetchResult<StepUpResponse> = try await PlatformFetch.request("/api/kiosk/remote-access/step-up/start", method: "POST", body: body)
        if let id = result.data.challengeId, !id.isEmpty {
            return id
        }
        throw PlatformFetchError.network(result.data.error ?? "Unable to start verification.")
    }

    static func mintLease() async throws -> LeaseResponse {
        let body = "{}".data(using: .utf8)
        do {
            let result: PlatformFetchResult<LeaseResponse> = try await PlatformFetch.request("/api/kiosk/remote-access/lease", method: "POST", body: body)
            if result.data.ok == false {
                throw PlatformFetchError.network(result.data.error ?? "Verification is required.")
            }
            return result.data
        } catch let error as PlatformFetchError {
            if case .http(_, let message) = error, message.contains("stepUpRequired") || message.contains("Email verification is required") {
                throw PlatformFetchError.network("Email verification is required.")
            }
            throw error
        } catch {
            throw error
        }
    }

    static func fetchSecrets(leaseToken: String) async throws -> SecretsResponse {
        let body = try JSONSerialization.data(withJSONObject: ["leaseToken": leaseToken])
        let result: PlatformFetchResult<SecretsResponse> = try await PlatformFetch.request("/api/kiosk/remote-access/secrets", method: "POST", body: body)
        if result.data.stepUpRequired == true {
            throw PlatformFetchError.network("Email verification required.")
        }
        if (result.data.haUsername ?? "").isEmpty || (result.data.haPassword ?? "").isEmpty {
            throw PlatformFetchError.network(result.data.error ?? "Unable to load Dinodia Hub credentials.")
        }
        return result.data
    }

    static func saveCloudUrl(leaseToken: String, cloudUrl: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["leaseToken": leaseToken, "cloudUrl": cloudUrl])
        let result: PlatformFetchResult<CloudUrlResponse> = try await PlatformFetch.request("/api/kiosk/remote-access/cloud-url", method: "POST", body: body)
        if result.data.ok == false {
            throw PlatformFetchError.network(result.data.error ?? "Unable to save remote access.")
        }
    }
}
