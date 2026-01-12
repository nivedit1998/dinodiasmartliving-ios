import Foundation

enum CloudService {
    private struct MeResponse: Decodable { let user: AuthUser? }

    static func checkPlatformReachable() async -> Bool {
        do {
            let result: PlatformFetchResult<MeResponse> = try await PlatformFetch.request("/api/auth/me", method: "GET")
            return result.data.user?.id != nil
        } catch {
            return false
        }
    }
}
