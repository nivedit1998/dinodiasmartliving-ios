import Foundation

enum AlexaLinkService {
    private struct LinkStatusResponse: Decodable {
        let linked: Bool?
        let error: String?
    }

    private struct UnlinkResponse: Decodable {
        let ok: Bool?
        let error: String?
    }

    static func checkLinked() async -> Bool {
        do {
            let result: PlatformFetchResult<LinkStatusResponse> = try await PlatformFetch.request(
                "/api/alexa/link-status",
                method: "GET"
            )
            return result.data.linked ?? false
        } catch {
            return false
        }
    }

    static func unlink() async throws {
        let result: PlatformFetchResult<UnlinkResponse> = try await PlatformFetch.request(
            "/api/alexa/link",
            method: "DELETE"
        )
        if result.data.ok != true {
            throw PlatformFetchError.network(result.data.error ?? "Unable to disconnect Alexa.")
        }
    }
}
