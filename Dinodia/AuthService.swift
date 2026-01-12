import Foundation

enum AuthServiceError: LocalizedError {
    case invalidInput
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Enter both username and password to sign in."
        case .custom(let message):
            return message
        }
    }
}

enum LoginStep {
    case ok(role: Role, token: String)
    case needsEmail
    case challenge(id: String)
}

enum ChallengeStatus: String, Decodable {
    case PENDING, APPROVED, CONSUMED, EXPIRED, NOT_FOUND
}

private struct LoginResponse: Decodable {
    let ok: Bool?
    let role: Role?
    let token: String?
    let requiresEmailVerification: Bool?
    let needsEmailInput: Bool?
    let challengeId: String?
    let error: String?
}

private struct ChallengeResponse: Decodable {
    let status: ChallengeStatus?
    let error: String?
}

private struct ChallengeCompleteResponse: Decodable {
    let ok: Bool?
    let role: Role?
    let token: String?
    let error: String?
    let stepUpApproved: Bool?
}

private struct PasswordResetResponse: Decodable {
    let ok: Bool?
    let error: String?
}

struct AuthService {
    private static let loginPath = "/api/auth/mobile-login"
    private static let logoutPath = "/api/auth/logout"
    private static let kioskLogoutPath = "/api/auth/kiosk-logout"
    private static let challengePath = "/api/auth/challenges"
    private static let adminChangePassword = "/api/admin/profile/change-password"
    private static let tenantChangePassword = "/api/tenant/profile/change-password"
    private static let passwordResetRequest = "/api/auth/password-reset/request"

    static func login(username: String, password: String, email: String? = nil) async throws -> LoginStep {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !password.isEmpty else {
            throw AuthServiceError.invalidInput
        }
        var payload: [String: String] = [
            "username": trimmedUsername,
            "password": password,
            "deviceId": DeviceIdentity.shared.deviceId,
            "deviceLabel": DeviceIdentity.shared.deviceLabel,
        ]
        if let email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["email"] = email.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let body = try JSONSerialization.data(withJSONObject: payload)
        let result: PlatformFetchResult<LoginResponse> = try await PlatformFetch.request(loginPath, method: "POST", body: body)
        let data = result.data

        if data.requiresEmailVerification == true {
            if data.needsEmailInput == true {
                return .needsEmail
            }
            if let challengeId = data.challengeId {
                return .challenge(id: challengeId)
            }
            throw AuthServiceError.custom("Email verification is required to continue.")
        }

        if data.ok == true, let role = data.role, let token = data.token, !token.isEmpty {
            PlatformTokenStore.set(token)
            return .ok(role: role, token: token)
        }

        throw AuthServiceError.custom(
            (data.error?.isEmpty == false ? data.error! : "We could not log you in right now. Please try again.")
        )
    }

    static func fetchChallengeStatus(id: String) async throws -> ChallengeStatus {
        let result: PlatformFetchResult<ChallengeResponse> = try await PlatformFetch.request("\(challengePath)/\(id)", method: "GET")
        if let status = result.data.status {
            return status
        }
        throw AuthServiceError.custom("Invalid verification status response.")
    }

    static func completeChallenge(id: String) async throws -> (role: Role, token: String?) {
        let body = try JSONSerialization.data(withJSONObject: [
            "deviceId": DeviceIdentity.shared.deviceId,
            "deviceLabel": DeviceIdentity.shared.deviceLabel,
        ])
        let result: PlatformFetchResult<ChallengeCompleteResponse> = try await PlatformFetch.request(
            "\(challengePath)/\(id)/complete",
            method: "POST",
            body: body
        )
        let data = result.data
        if data.ok == true, let role = data.role {
            if let token = data.token, !token.isEmpty {
                PlatformTokenStore.set(token)
            }
            return (role, data.token)
        }
        throw AuthServiceError.custom(data.error ?? "We could not complete verification. Please try again.")
    }

    static func completeStepUpChallenge(id: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "deviceId": DeviceIdentity.shared.deviceId,
            "deviceLabel": DeviceIdentity.shared.deviceLabel,
        ])
        let result: PlatformFetchResult<ChallengeCompleteResponse> = try await PlatformFetch.request(
            "\(challengePath)/\(id)/complete",
            method: "POST",
            body: body
        )
        if result.data.ok == true || result.data.stepUpApproved == true {
            return
        }
        throw AuthServiceError.custom(result.data.error ?? "We could not complete verification. Please try again.")
    }

    static func resendChallenge(id: String) async throws {
        let _: PlatformFetchResult<Empty> = try await PlatformFetch.request("\(challengePath)/\(id)/resend", method: "POST")
    }

    static func changePassword(role: Role, currentPassword: String, newPassword: String, confirmPassword: String) async throws {
        let path = role == .ADMIN ? adminChangePassword : tenantChangePassword
        let payload = [
            "currentPassword": currentPassword,
            "newPassword": newPassword,
            "confirmNewPassword": confirmPassword,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let _: PlatformFetchResult<Empty> = try await PlatformFetch.request(path, method: "POST", body: body)
    }

    static func requestPasswordReset(identifier: String) async throws {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw AuthServiceError.custom("Enter your username or email to continue.")
        }
        let body = try JSONSerialization.data(withJSONObject: ["identifier": trimmed])
        let _: PlatformFetchResult<PasswordResetResponse> = try await PlatformFetch.request(
            passwordResetRequest,
            method: "POST",
            body: body
        )
    }

    static func logoutRemote() async {
        let empty = "{}".data(using: .utf8)
        _ = try? await PlatformFetch.request(kioskLogoutPath, method: "POST", body: empty) as PlatformFetchResult<Empty>
        _ = try? await PlatformFetch.request(logoutPath, method: "POST", body: empty) as PlatformFetchResult<Empty>
        PlatformTokenStore.clear()
    }
}
