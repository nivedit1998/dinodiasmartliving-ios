import Foundation

enum OnboardingServiceError: LocalizedError {
    case server(String)
    case missingChallenge

    var errorDescription: String? {
        switch self {
        case .server(let msg): return msg
        case .missingChallenge: return "We could not start email verification."
        }
    }
}

struct RegisterAdminResponse: Decodable {
    let ok: Bool?
    let challengeId: String?
    let error: String?
}

struct ClaimValidateResponse: Decodable {
    let ok: Bool?
    let homeStatus: String?
    let error: String?
}

struct ClaimStartResponse: Decodable {
    let ok: Bool?
    let challengeId: String?
    let requiresEmailVerification: Bool?
    let error: String?
}

enum OnboardingService {
    static func registerAdmin(
        username: String,
        password: String,
        email: String,
        dinodiaSerial: String,
        bootstrapSecret: String
    ) async throws -> String {
        let identity = DeviceIdentity.shared
        let payload: [String: Any] = [
            "username": username.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "dinodiaSerial": dinodiaSerial.trimmingCharacters(in: .whitespacesAndNewlines),
            "bootstrapSecret": bootstrapSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            "deviceId": identity.deviceId,
            "deviceLabel": identity.deviceLabel
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let result: PlatformFetchResult<RegisterAdminResponse> = try await PlatformFetch.request(
            "/api/auth/register-admin",
            method: "POST",
            body: body
        )
        if result.data.ok == true, let id = result.data.challengeId, !id.isEmpty {
            return id
        }
        throw OnboardingServiceError.server(result.data.error ?? "We could not finish setup.")
    }

    static func claimValidate(code: String) async throws {
        let payload = ["claimCode": code, "validateOnly": true] as [String: Any]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let result: PlatformFetchResult<ClaimValidateResponse> = try await PlatformFetch.request(
            "/api/claim",
            method: "POST",
            body: body
        )
        if result.data.ok == true { return }
        throw OnboardingServiceError.server(result.data.error ?? "We could not validate that claim code.")
    }

    static func claimStart(
        code: String,
        username: String,
        password: String,
        email: String
    ) async throws -> String {
        let identity = DeviceIdentity.shared
        let payload: [String: Any] = [
            "claimCode": code,
            "username": username.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "deviceId": identity.deviceId,
            "deviceLabel": identity.deviceLabel
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let result: PlatformFetchResult<ClaimStartResponse> = try await PlatformFetch.request(
            "/api/claim",
            method: "POST",
            body: body
        )
        if result.data.ok == true, let id = result.data.challengeId, !id.isEmpty {
            return id
        }
        throw OnboardingServiceError.server(result.data.error ?? "We could not start email verification.")
    }
}
