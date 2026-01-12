import Foundation
import Combine
import AuthenticationServices
import UIKit

@MainActor
final class SpotifyStore: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var playback: SpotifyPlaybackState?
    @Published var isLoggedIn = false
    @Published var errorMessage: String?
    @Published var isLoggingIn = false
    @Published var isLoggingOut = false
    @Published var isLoadingPlayback = false
    @Published var devices: [SpotifyDevice] = []
    @Published var showDevicePicker = false
    @Published var isSpotifyInstalled: Bool = false

    private var tokens: SpotifyTokens? {
        didSet {
            if let tokens { SpotifyTokenStore.save(tokens) } else { SpotifyTokenStore.clear() }
        }
    }
    private var authSession: ASWebAuthenticationSession?
    private var playbackTimer: Timer?
    private var currentCodeVerifier: String?
    private var currentState: String?
    override init() {
        super.init()
        tokens = SpotifyTokenStore.load()
        isLoggedIn = tokens != nil
        updateSpotifyInstalledFlag()
        if isLoggedIn {
            Task { await refreshPlayback() }
            startTimer()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    func startLogin() {
        guard !isLoggingIn else { return }
        isLoggingIn = true
        errorMessage = nil
        let verifier = SpotifyService.randomString(length: 64)
        let state = SpotifyService.randomString(length: 32)
        currentCodeVerifier = verifier
        currentState = state
        let challenge = SpotifyService.codeChallenge(for: verifier)
        guard let authURL = try? SpotifyService.authorizeURL(codeChallenge: challenge, state: state) else {
            isLoggingIn = false
            errorMessage = SpotifyServiceError.notConfigured.localizedDescription
            return
        }
        authSession = ASWebAuthenticationSession(url: authURL, callbackURLScheme: SpotifyService.redirectScheme) { [weak self] callbackURL, error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoggingIn = false
                if let error {
                    if error.isCancellation { return }
                    self.errorMessage = error.localizedDescription; return
                }
                guard let callbackURL = callbackURL, let code = self.extractCode(from: callbackURL) else {
                    self.errorMessage = "Spotify login was cancelled or failed."
                    return
                }
                await self.completeLogin(code: code)
            }
        }
        authSession?.presentationContextProvider = self
        authSession?.prefersEphemeralWebBrowserSession = true
        authSession?.start()
    }

    func logout() {
        guard !isLoggingOut else { return }
        isLoggingOut = true
        tokens = nil
        playback = nil
        isLoggedIn = false
        devices = []
        errorMessage = nil
        stopTimer()
        Task { @MainActor in
            isLoggingOut = false
        }
    }

    func refreshPlayback() async {
        guard isLoggedIn else { return }
        do {
            guard let token = try await ensureAccessToken() else { return }
            isLoadingPlayback = true
            let state = try await SpotifyService.getPlaybackState(accessToken: token)
            playback = state
            isLoadingPlayback = false
        } catch {
            isLoadingPlayback = false
            if error.isCancellation { return }
            if shouldForceLogout(for: error) {
                logout()
                // Optional: show a single message; the timer is stopped so it won't spam.
                errorMessage = "Spotify session expired. Please log in again."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func togglePlayPause() async {
        guard let token = try? await ensureAccessToken() else { return }
        do {
            if playback?.isPlaying == true {
                try await SpotifyService.pausePlayback(accessToken: token)
            } else {
                try await SpotifyService.resumePlayback(accessToken: token)
            }
            await refreshPlayback()
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    func skipNext() async {
        guard let token = try? await ensureAccessToken() else { return }
        do {
            try await SpotifyService.skipToNext(accessToken: token)
            await refreshPlayback()
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    func skipPrevious() async {
        guard let token = try? await ensureAccessToken() else { return }
        do {
            try await SpotifyService.skipToPrevious(accessToken: token)
            await refreshPlayback()
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadDevices() async {
        guard let token = try? await ensureAccessToken() else { return }
        do {
            devices = try await SpotifyService.getDevices(accessToken: token)
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    func transfer(to device: SpotifyDevice) async {
        guard let token = try? await ensureAccessToken() else { return }
        do {
            try await SpotifyService.transferPlayback(accessToken: token, deviceId: device.id)
            showDevicePicker = false
            await refreshPlayback()
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    func openSpotifyApp() {
        if let url = URL(string: "spotify:"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            errorMessage = "Spotify app is not installed on this device."
        }
    }

    private func ensureAccessToken() async throws -> String? {
        guard var tokens = tokens else { return nil }
        let now = Date()
        if tokens.expiresAt.timeIntervalSince(now) < 60 {
            guard let refresh = tokens.refreshToken else { throw SpotifyServiceError.generic("Spotify session expired.") }
            do {
                let refreshed = try await SpotifyService.refreshTokens(refreshToken: refresh)
                self.tokens = refreshed
                tokens = refreshed
            } catch {
                // If refresh token is revoked/invalid, force logout so we don't repeatedly alert.
                if shouldForceLogout(for: error) {
                    logout()
                }
                throw error
            }
        }
        isLoggedIn = true
        return tokens.accessToken
    }

    private func completeLogin(code: String) async {
        guard let verifier = currentCodeVerifier else {
            errorMessage = "We could not finish Spotify login. Please try again."
            return
        }
        do {
            let newTokens = try await SpotifyService.exchangeCodeForTokens(code: code, codeVerifier: verifier)
            tokens = newTokens
            isLoggedIn = true
            errorMessage = nil
            await refreshPlayback()
            startTimer()
        } catch {
            tokens = nil
            isLoggedIn = false
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func extractCode(from url: URL) -> String? {
        guard let expectedState = currentState else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if components.queryItems?.first(where: { $0.name == "state" })?.value != expectedState {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == "code" })?.value
    }

    private func startTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshPlayback() }
        }
    }

    private func stopTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func updateSpotifyInstalledFlag() {
        if let url = URL(string: "spotify:") {
            isSpotifyInstalled = UIApplication.shared.canOpenURL(url)
        } else {
            isSpotifyInstalled = false
        }
    }

    private func shouldForceLogout(for error: Error) -> Bool {
        // Spotify revocation errors come back as 400 with JSON body (invalid_grant / refresh token revoked).
        let msg = error.localizedDescription.lowercased()
        if msg.contains("invalid_grant") { return true }
        if msg.contains("refresh token revoked") { return true }
        if msg.contains("\"error\"") && msg.contains("invalid_grant") { return true }
        if (error as NSError).code == 401 { return true }
        return false
    }
}
