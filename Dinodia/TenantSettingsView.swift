import SwiftUI

struct TenantSettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: TabRouter
    @State private var alertMessage: String?

    var body: some View {
        Form {
            statusSection
            Section("Account") {
                Text("Logged in as \(session.user?.username ?? "")")
                Button(role: .destructive) {
                    session.logout()
                } label: {
                    Text("Logout")
                }
            }
            Section("Security") {
                NavigationLink("Manage Devices") {
                    ManageDevicesView()
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                ModeSwitchPrompt(
                    targetMode: session.haMode == .home ? .cloud : .home,
                    userId: session.user?.id,
                    onSwitched: { Task { await refreshStatus() } }
                )
                .environmentObject(session)
            }
            ToolbarItem(placement: .principal) {
                DinodiaNavBarLogo()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Logout", role: .destructive) {
                    session.logout()
                }
            }
        }
        .task {
            await refreshStatus()
        }
        .alert("Dinodia", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var statusSection: some View {
        Section {
            HStack {
                Text(session.haMode == .home ? "Home Mode" : "Cloud Mode")
                Spacer()
                modeStatusBadge
            }
        }
    }

    private var modeStatusBadge: some View {
        HStack(spacing: 4) {
            if session.haMode == .home {
                Image(systemName: session.onHomeNetwork ? "wifi" : "wifi.slash")
                    .foregroundColor(session.onHomeNetwork ? .green : .orange)
                Text(homeNetworkText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: session.cloudAvailable ? "cloud.fill" : "cloud.slash.fill")
                    .foregroundColor(session.cloudAvailable ? .green : .orange)
                Text(session.cloudAvailable ? "Cloud Available" : "Cloud Unavailable")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var homeNetworkText: String {
        if session.homeHubStatus == .reachable {
            return "On Home Network"
        } else if session.homeHubStatus == .unreachable {
            return "Not on Home Network"
        }
        return session.onHomeNetwork ? "On Home Network" : "Not on Home Network"
    }

    private func refreshStatus() async {
        await session.updateHomeNetworkStatus()
        await session.updateCloudAvailability()
    }
}
