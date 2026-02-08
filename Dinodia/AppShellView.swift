import SwiftUI

struct AppShellView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var router = TabRouter()
    @State private var showHomeGate = false

    var body: some View {
        if let user = session.user {
            switch user.role {
            case .ADMIN:
                AdminTabView(showHomeGate: $showHomeGate)
                    .environmentObject(router)
            case .TENANT:
                TenantTabView(showHomeGate: $showHomeGate)
                    .environmentObject(router)
            }
        } else {
            ProgressView()
        }
    }
}

private struct AdminTabView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: TabRouter
    @Binding var showHomeGate: Bool

    var body: some View {
        TabView(selection: $router.adminTab) {
            NavigationStack {
                DashboardView(role: .ADMIN)
            }
            .tabItem {
                Label("Dashboard", systemImage: "house")
            }
            .tag(AdminTab.dashboard)

            NavigationStack {
                AutomationsView(mode: session.haMode, haConnection: session.haConnection, userId: session.user?.id ?? 0)
                    .id("admin-auto-\(session.haMode.rawValue)")
            }
            .tabItem {
                Label("Automations", systemImage: "switch.2")
            }
            .tag(AdminTab.automations)

            NavigationStack {
                if let userId = session.user?.id {
                    HomeSetupView(userId: userId, mode: session.haMode)
                        .environmentObject(session)
                } else {
                    ProgressView()
                }
            }
            .tabItem {
                Label("Home Setup", systemImage: "hammer")
            }
            .tag(AdminTab.homeSetup)

            NavigationStack {
                AdminSettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AdminTab.settings)
        }
        .modifier(HomeModeGateModifier(showGate: $showHomeGate))
    }
}

private struct TenantTabView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: TabRouter
    @Binding var showHomeGate: Bool

    var body: some View {
        TabView(selection: $router.tenantTab) {
            NavigationStack {
                DashboardView(role: .TENANT)
            }
            .tabItem {
                Label("Dashboard", systemImage: "house")
            }
            .tag(TenantTab.dashboard)

            NavigationStack {
                AutomationsView(mode: session.haMode, haConnection: session.haConnection, userId: session.user?.id ?? 0)
                    .id("tenant-auto-\(session.haMode.rawValue)")
            }
            .tabItem {
                Label("Automations", systemImage: "switch.2")
            }
            .tag(TenantTab.automations)

            NavigationStack {
                if let userId = session.user?.id {
                    AddDeviceView(store: AddDeviceStore(userId: userId))
                        .environmentObject(session)
                } else {
                    ProgressView()
                }
            }
            .tabItem {
                Label("Add Devices", systemImage: "plus.app")
            }
            .tag(TenantTab.addDevices)

            NavigationStack {
                TenantSettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(TenantTab.settings)
        }
        .modifier(HomeModeGateModifier(showGate: $showHomeGate))
    }
}

private struct HomeModeGateModifier: ViewModifier {
    @EnvironmentObject private var session: SessionStore
    @Binding var showGate: Bool
    @State private var showModeAlert = false
    @State private var modeResult: ModeSwitchResult?
    @State private var checkingCloud = false

    func body(content: Content) -> some View {
        ZStack {
            content
            if session.haMode == .home && session.user != nil && session.homeHubStatus == .unreachable {
                HomeModeGateView(
                    onRetry: {
                        Task {
                            await session.updateHomeNetworkStatus()
                        }
                    },
                    onSwitchToCloud: {
                        handleSwitchToCloud()
                    }
                )
                .alert("Move to Cloud Mode?", isPresented: $showModeAlert) {
                    if modeResult?.available == true {
                        Button("Switch") {
                            Task {
                                await ModeSwitchPrompt.performSwitch(
                                    targetMode: .cloud,
                                    userId: session.user?.id,
                                    session: session
                                )
                            }
                        }
                    }
                    Button("OK", role: .cancel) {}
                } message: {
                    if let result = modeResult {
                        HStack {
                            Image(systemName: result.available ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundColor(result.available ? .green : .red)
                            Text(result.message)
                        }
                    }
                }
            }
        }
    }

    private func handleSwitchToCloud() {
        if checkingCloud { return }
        checkingCloud = true
        Task {
            let res = await ModeSwitchPrompt.checkAvailability(targetMode: .cloud, session: session)
            await MainActor.run {
                modeResult = res
                showModeAlert = true
                checkingCloud = false
            }
        }
    }
}
