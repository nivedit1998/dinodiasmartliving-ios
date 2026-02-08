import Foundation

enum RemoteAccessService {
    private struct AlexaDevicesResponse: Decodable {
        let devices: [AnyCodable]?
        let error: String?
    }

    static func checkHomeReachable() async -> Bool {
        guard let secrets = try? await HomeModeSecretsStore.fetch() else { return false }
        let ha = HaConnectionLike(baseUrl: secrets.baseUrl, longLivedToken: secrets.longLivedToken)
        return await HAService.probeHaReachability(ha, timeout: 2.0)
    }
}
