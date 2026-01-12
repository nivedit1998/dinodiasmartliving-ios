import SwiftUI

struct HomeModeGateView: View {
    @EnvironmentObject private var session: SessionStore
    let onRetry: (() -> Void)?
    let onSwitchToCloud: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.bottom, 4)
            Text("Unable to reach your Dinodia Hub")
                .font(.title3.weight(.semibold))
            Text("Connect to your home Wi‑Fi or switch to Dinodia Cloud to keep going.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: 12) {
                Button {
                    onRetry?()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)

                Button {
                    onSwitchToCloud?()
                } label: {
                    HStack {
                        Image(systemName: "cloud")
                        Text("Switch to Cloud Mode")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).opacity(0.94))
        .ignoresSafeArea()
    }
}
