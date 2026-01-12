import Foundation
import CryptoKit

enum SpotifyServiceError: LocalizedError {
    case notConfigured
    case generic(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Spotify is not configured on this build."
        case .generic(let message):
            return message
        }
    }
}

enum SpotifyService {
    static let clientId = "9e88d4fb6e0c44049242fac02aaddea0"
    static let redirectScheme = "dinodia"
    static let redirectURI = "dinodia://spotify-auth"
    static let scopes = [
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
    ]

    static func authorizeURL(codeChallenge: String, state: String) throws -> URL {
        guard !clientId.isEmpty else { throw SpotifyServiceError.notConfigured }
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "show_dialog", value: "true"),
        ]
        guard let url = components.url else { throw SpotifyServiceError.notConfigured }
        return url
    }

    static func exchangeCodeForTokens(code: String, codeVerifier: String) async throws -> SpotifyTokens {
        let body = [
            "client_id": clientId,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier,
        ]
        return try await exchange(body: body)
    }

    static func refreshTokens(refreshToken: String) async throws -> SpotifyTokens {
        let body = [
            "client_id": clientId,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]
        return try await exchange(body: body, originalRefreshToken: refreshToken)
    }

    private static func exchange(body: [String: String], originalRefreshToken: String? = nil) async throws -> SpotifyTokens {
        var components = URLComponents()
        components.queryItems = body.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let data = components.query?.data(using: .utf8) else {
            throw SpotifyServiceError.generic("Unable to encode request")
        }
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let text = String(data: responseData, encoding: .utf8) ?? ""
            throw SpotifyServiceError.generic(text.isEmpty ? "We could not finish Spotify login. Please try again." : text)
        }
        let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        guard let access = json?["access_token"] as? String else {
            throw SpotifyServiceError.generic("Invalid response from Spotify")
        }
        let refresh = (json?["refresh_token"] as? String) ?? originalRefreshToken
        let expiresIn = json?["expires_in"] as? Double ?? 3600
        let token = SpotifyTokens(accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(expiresIn))
        return token
    }

    static func getPlaybackState(accessToken: String) async throws -> SpotifyPlaybackState? {
        let (data, response) = try await authorizedRequest(path: "/me/player", method: "GET", accessToken: accessToken)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyServiceError.generic("Unable to reach Spotify")
        }
        if http.statusCode == 204 { return nil }
        guard (200...299).contains(http.statusCode) else {
            throw SpotifyServiceError.generic("Unable to load Spotify right now. Please try again.")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let json else { return nil }
        let isPlaying = (json["is_playing"] as? Bool) ?? false
        let item = json["item"] as? [String: Any]
        let track = item?["name"] as? String
        let artists = (item?["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ")
        let album = (item?["album"] as? [String: Any])?["name"] as? String
        let images = (item?["album"] as? [String: Any])?["images"] as? [[String: Any]]
        let cover = images?.first?["url"] as? String
        let device = json["device"] as? [String: Any]
        let state = SpotifyPlaybackState(
            isPlaying: isPlaying,
            trackName: track,
            artistName: artists,
            albumName: album,
            coverURL: cover.flatMap(URL.init(string:)),
            deviceId: device?["id"] as? String,
            deviceName: device?["name"] as? String
        )
        return state
    }

    static func getDevices(accessToken: String) async throws -> [SpotifyDevice] {
        let (data, response) = try await authorizedRequest(path: "/me/player/devices", method: "GET", accessToken: accessToken)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SpotifyServiceError.generic("We could not load your Spotify devices right now. Please try again.")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let devicesJSON = json?["devices"] as? [[String: Any]] ?? []
        return devicesJSON.map { item in
            SpotifyDevice(
                id: String(describing: item["id"] ?? ""),
                name: String(describing: item["name"] ?? "Device"),
                isActive: (item["is_active"] as? Bool) ?? false,
                isRestricted: (item["is_restricted"] as? Bool) ?? false,
                type: String(describing: item["type"] ?? "unknown")
            )
        }
    }

    static func transferPlayback(accessToken: String, deviceId: String) async throws {
        let body: [String: Any] = [
            "device_ids": [deviceId],
            "play": true,
        ]
        _ = try await authorizedRequest(path: "/me/player", method: "PUT", body: body, accessToken: accessToken)
    }

    static func resumePlayback(accessToken: String) async throws {
        _ = try await authorizedRequest(path: "/me/player/play", method: "PUT", body: [:], accessToken: accessToken)
    }

    static func pausePlayback(accessToken: String) async throws {
        _ = try await authorizedRequest(path: "/me/player/pause", method: "PUT", body: [:], accessToken: accessToken)
    }

    static func skipToNext(accessToken: String) async throws {
        _ = try await authorizedRequest(path: "/me/player/next", method: "POST", accessToken: accessToken)
    }

    static func skipToPrevious(accessToken: String) async throws {
        _ = try await authorizedRequest(path: "/me/player/previous", method: "POST", accessToken: accessToken)
    }

    private static func authorizedRequest(path: String, method: String, body: [String: Any]? = nil, accessToken: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1" + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return try await URLSession.shared.data(for: request)
    }

    private static func authorizedRequest(path: String, method: String, accessToken: String) async throws -> (Data, URLResponse) {
        try await authorizedRequest(path: path, method: method, body: nil, accessToken: accessToken)
    }

    static func codeChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return base64URL(Data(hash))
    }

    static func randomString(length: Int) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        var result = ""
        for _ in 0..<length {
            if let random = characters.randomElement() {
                result.append(random)
            }
        }
        return result
    }

    private static func base64URL(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
