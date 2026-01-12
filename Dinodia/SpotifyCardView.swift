import SwiftUI

struct SpotifyCardView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var spotifyStore: SpotifyStore

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 4) {
                    Text(spotifyStore.playback?.trackName ?? (spotifyStore.isLoggedIn ? "No track playing" : "Connect to Spotify"))
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                    if spotifyStore.isLoggedIn {
                        Button(action: { spotifyStore.showDevicePicker = true; Task { await spotifyStore.loadDevices() } }) {
                            Label(spotifyStore.playback?.deviceName ?? "Device", systemImage: "speaker.wave.2.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
                Spacer()
                if spotifyStore.isLoggingIn || spotifyStore.isLoadingPlayback {
                    ProgressView()
                        .tint(.white)
                }
                Button(action: { spotifyStore.isLoggedIn ? spotifyStore.openSpotifyApp() : spotifyStore.startLogin() }) {
                    Text(spotifyStore.isLoggedIn ? "Open" : "Login")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(16)
                }
                .foregroundColor(.white)
            }
            HStack(spacing: 24) {
                Button(action: { Task { await spotifyStore.skipPrevious() } }) {
                    Image(systemName: "backward.fill")
                }
                Button(action: { Task { await spotifyStore.togglePlayPause() } }) {
                    Image(systemName: spotifyStore.playback?.isPlaying == true ? "pause.fill" : "play.fill")
                        .padding()
                        .background(Color.white)
                        .foregroundColor(.black)
                        .clipShape(Circle())
                }
                Button(action: { Task { await spotifyStore.skipNext() } }) {
                    Image(systemName: "forward.fill")
                }
            }
            .font(.title2)
            .foregroundColor(.white)
        }
        .padding()
        .background(LinearGradient(colors: [Color.green.opacity(0.8), Color.black], startPoint: .topLeading, endPoint: .bottomTrailing))
        .cornerRadius(24)
        .sheet(isPresented: $spotifyStore.showDevicePicker) {
            NavigationStack {
                List(spotifyStore.devices) { device in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text(device.type)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if device.isActive {
                            Text("Active")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { Task { await spotifyStore.transfer(to: device) } }
                }
                .navigationTitle("Spotify Devices")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { spotifyStore.showDevicePicker = false }
                    }
                }
            }
        }
        .alert("Spotify", isPresented: Binding(get: { spotifyStore.errorMessage != nil }, set: { _ in spotifyStore.errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(spotifyStore.errorMessage ?? "")
        }
        .onChange(of: session.user?.id) { _, newValue in
            if newValue == nil {
                spotifyStore.showDevicePicker = false
                spotifyStore.errorMessage = nil
            }
        }
    }

    private var subtitle: String {
        if !spotifyStore.isLoggedIn {
            if !spotifyStore.isSpotifyInstalled {
                return "Spotify app is not installed."
            }
            return "Log in to control music from this device."
        }
        if let playback = spotifyStore.playback {
            if let artist = playback.artistName, let album = playback.albumName {
                return "\(artist) • \(album)"
            }
            return playback.artistName ?? playback.albumName ?? "Spotify"
        }
        return "Start playing music in Spotify."
    }

    private var artwork: some View {
        ZStack {
            if let url = spotifyStore.playback?.coverURL {
                AsyncImage(url: url) { image in
                    image.resizable()
                } placeholder: {
                    Color.white.opacity(0.2)
                }
            } else {
                Color.white.opacity(0.2)
                Text("♫")
                    .font(.title)
                    .foregroundColor(.white)
            }
        }
        .frame(width: 60, height: 60)
        .cornerRadius(12)
    }
}
