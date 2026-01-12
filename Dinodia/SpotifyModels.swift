import Foundation

struct SpotifyTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
}

struct SpotifyPlaybackState: Codable {
    var isPlaying: Bool
    var trackName: String?
    var artistName: String?
    var albumName: String?
    var coverURL: URL?
    var deviceId: String?
    var deviceName: String?
}

struct SpotifyDevice: Identifiable, Codable {
    let id: String
    let name: String
    let isActive: Bool
    let isRestricted: Bool
    let type: String
}
