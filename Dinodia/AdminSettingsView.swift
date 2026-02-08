import SwiftUI

struct AdminSettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var alertMessage: String?
    @State private var showingReachabilityAlert = false
    @State private var reachabilityMessage: String = ""
    @State private var reachabilitySuccess = false
    @State private var navigateToRemoteAccess = false

    var body: some View {
        Form {
            Section("Account") {
                Text("Logged in as \(session.user?.username ?? "")")
                if session.haMode == .cloud {
                    cloudBadge
                } else {
                    homeBadge
                }
                Button(role: .destructive) {
                    session.logout()
                } label: {
                    Text("Logout")
                }
            }
            Section("Security") {
                NavigationLink("Manage Devices") { ManageDevicesView() }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Dinodia", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .alert("Remote Access Setup", isPresented: $showingReachabilityAlert) {
            if reachabilitySuccess {
                Button("Continue") { navigateToRemoteAccess = true }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            HStack {
                Image(systemName: reachabilitySuccess ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundColor(reachabilitySuccess ? .green : .red)
                Text(reachabilityMessage)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                ModeSwitchPrompt(
                    targetMode: session.haMode == .home ? .cloud : .home,
                    userId: session.user?.id,
                    onSwitched: nil
                )
                .environmentObject(session)
            }
            ToolbarItem(placement: .principal) {
                DinodiaNavBarLogo()
            }
        }
    }

    private var cloudBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: session.cloudAvailable ? "cloud.fill" : "cloud.slash.fill")
                .foregroundColor(session.cloudAvailable ? .green : .orange)
            Text(session.cloudAvailable ? "Cloud Available" : "Cloud Unavailable")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var homeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: session.onHomeNetwork ? "wifi" : "wifi.slash")
                .foregroundColor(session.onHomeNetwork ? .green : .orange)
            Text(homeNetworkText)
                .font(.caption2)
                .foregroundColor(.secondary)
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

}
