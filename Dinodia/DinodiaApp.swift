import SwiftUI

@main
struct DinodiaApp: App {
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var spotifyStore = SpotifyStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPrivacyCover = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(sessionStore)
                    .environmentObject(spotifyStore)
                if showPrivacyCover {
                    PrivacyCoverView()
                }
            }
            .onChange(of: scenePhase) { _, next in
                showPrivacyCover = next != .active
            }
        }
    }
}

private struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                Image("DinodiaLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                Text("Dinodia")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .transition(.opacity)
    }
}
