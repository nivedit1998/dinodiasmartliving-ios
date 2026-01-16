import SwiftUI

struct TenantSettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: TabRouter
    @State private var alertMessage: String?
    @State private var alexaLinked = false
    @State private var checkingAlexa = false
    @State private var remoteReady = false
    @State private var showAlexa = false

    var body: some View {
        Form {
            statusSection
            if session.haMode == .cloud {
                alexaSection
            }
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
            await refreshAlexaStatusIfNeeded()
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

    private var alexaSection: some View {
        Section("Alexa") {
            if !remoteReady {
                NoticeView(kind: .warning, message: "Enable Cloud Mode remote access to link Alexa.")
            }
            NavigationLink {
                AlexaSetupView(initiallyLinked: alexaLinked) { linked in
                    alexaLinked = linked
                }
            } label: {
                HStack {
                    Text("Alexa")
                    Spacer()
                    if checkingAlexa {
                        ProgressView().scaleEffect(0.8)
                    } else if alexaLinked {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }
            .disabled(!remoteReady)
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

    private func refreshAlexaStatusIfNeeded() async {
        guard session.haMode == .cloud else {
            await MainActor.run {
                remoteReady = false
                alexaLinked = false
                checkingAlexa = false
            }
            return
        }
        checkingAlexa = true
        let ready = await RemoteAccessService.checkRemoteAccessEnabled()
        let linked = ready ? await AlexaLinkService.checkLinked() : false
        await MainActor.run {
            remoteReady = ready
            alexaLinked = linked
            checkingAlexa = false
        }
    }
}
