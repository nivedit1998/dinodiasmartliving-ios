import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemGray6), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Image("DinodiaLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                Text("Dinodia")
                    .font(.system(size: 26, weight: .semibold))
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.accentColor)
            }
            .padding(24)
        }
    }
}
