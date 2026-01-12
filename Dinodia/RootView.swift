import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            if session.isLoading {
                SplashView()
            } else if session.user == nil {
                LoginView()
            } else {
                AppShellView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.isLoading)
        .animation(.easeInOut(duration: 0.2), value: session.user?.id)
    }
}
