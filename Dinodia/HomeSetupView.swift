import SwiftUI

struct HomeSetupView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var store = HomeSetupStore()
    @StateObject private var deviceStore: DeviceStore

    @State private var tenantUsername: String = ""
    @State private var tenantPassword: String = ""
    @State private var selectedNewAreas: Set<String> = []
    @State private var areaSelections: [Int: Set<String>] = [:]
    @State private var selectedCleanup: String? = nil
    @State private var showConfirmReset: Bool = false
    @State private var confirmResetMode: String?
    @State private var editingTenantId: Int? = nil
    @State private var viewTenantsExpanded = false
    @State private var addTenantExpanded = false

    init(userId: Int, mode: HaMode) {
        _deviceStore = StateObject(wrappedValue: DeviceStore(userId: userId, mode: mode))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if session.haMode == .home {
                    homeNetworkBadge
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    cloudBadge
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                tenantsSection
                addTenantSection
                sellingSection
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle("Home Setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                ModeSwitchPrompt(
                    targetMode: session.haMode == .home ? .cloud : .home,
                    userId: session.user?.id,
                    onSwitched: { Task { await reloadAll() } }
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
        .refreshable {
            await reloadAll()
            
            
        }
        .task {
            await reloadAll()
            await session.updateHomeNetworkStatus()
        }
        .confirmationDialog("Dinodia", isPresented: $showConfirmReset) {
            if confirmResetMode == "FULL_RESET" {
                Button("Deregister whole household", role: .destructive) {
                    Task { await performReset(mode: "FULL_RESET", cleanup: "device") }
                }
            } else if confirmResetMode == "OWNER_TRANSFER" {
                Button("Deregister yourself only", role: .destructive) {
                    Task { await performReset(mode: "OWNER_TRANSFER", cleanup: "platform") }
                }
            }
            Button("Cancel", role: .cancel) { confirmResetMode = nil }
        } message: {
            if confirmResetMode == "FULL_RESET" {
                Text("This removes homeowner and occupiers, devices, entities, and automations. You will be logged out.")
            } else if confirmResetMode == "OWNER_TRANSFER" {
                Text("This removes you as homeowner but keeps occupiers active. You will be logged out.")
            }
        }
    }

    // MARK: - Sections

    private var tenantsSection: some View {
        CollapsibleSection(title: "Home Setup - View Users", expanded: $viewTenantsExpanded) {
            if store.isLoadingTenants && store.tenants.isEmpty {
                ProgressView("Loading users…")
            }
            if let error = store.tenantError {
                NoticeView(kind: .error, message: error)
            }

            VStack(spacing: 12) {
                ForEach(store.tenants) { tenant in
                    TenantCard(
                        tenant: tenant,
                        areas: areaSelections[tenant.id] ?? Set(tenant.areas),
                        areaOptions: areaOptions,
                        isEditing: editingTenantId == tenant.id,
                        onEdit: { editingTenantId = tenant.id },
                        onCancel: {
                            areaSelections[tenant.id] = Set(tenant.areas)
                            editingTenantId = nil
                        },
                        onDelete: {
                            Task { await store.deleteTenant(id: tenant.id) }
                        },
                        onApply: { newAreas in
                            areaSelections[tenant.id] = newAreas
                            Task { await store.updateAreas(for: tenant.id, areas: Array(newAreas)) }
                            editingTenantId = nil
                        }
                    )
                }
            }
            .padding(.top, 4)
        }
    }

    private var addTenantSection: some View {
        CollapsibleSection(title: "Home Setup - Add User", expanded: $addTenantExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Username", text: $tenantUsername)
                SecureField("Password", text: $tenantPassword)
                areaChooser(title: "Areas", selection: $selectedNewAreas)
                Button {
                    let areas = Array(selectedNewAreas)
                    Task {
                        await store.addTenant(
                            username: tenantUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                            password: tenantPassword,
                            areas: areas
                        )
                        tenantUsername = ""
                        tenantPassword = ""
                        selectedNewAreas = []
                    }
                } label: {
                    Text("Add User")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(tenantUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || tenantPassword.isEmpty)
            }
            .padding(.top, 4)
        }
    }

    private var sellingSection: some View {
        SectionCard(title: "Deregister Property", tint: Color.yellow.opacity(0.15)) {
            if store.sellingLoading && store.sellingTargets == nil {
                ProgressView("Loading…")
            }
            if let error = store.sellingError {
                NoticeView(kind: .error, message: error)
            }
            if let targets = store.sellingTargets {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Devices to remove: \(targets.deviceIds.count)")
                    Text("Entities to remove: \(targets.entityIds.count)")
                    Text("Automations to remove: \(targets.automationIds.count)")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            if let claim = store.claimCode, !claim.isEmpty {
                Text("Claim code: \(claim)")
                    .font(.headline)
            }
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    confirmResetMode = "FULL_RESET"
                    showConfirmReset = true
                } label: {
                    Text(store.sellingLoading && selectedCleanup == "FULL_RESET" ? "Resetting…" : "Deregister whole household")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(store.sellingLoading)

                Button {
                    confirmResetMode = "OWNER_TRANSFER"
                    showConfirmReset = true
                } label: {
                    Text(store.sellingLoading && selectedCleanup == "OWNER_TRANSFER" ? "Preparing…" : "Deregister yourself (keep occupiers)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(store.sellingLoading)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Helpers

    private func areaChooser(title: String, selection: Binding<Set<String>>, onChange: ((Set<String>) -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            if areaOptions.isEmpty {
                Text("No areas available yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(areaOptions, id: \.self) { area in
                        let isSelected = selection.wrappedValue.contains(area)
                        Button {
                            var next = selection.wrappedValue
                            if isSelected {
                                next.remove(area)
                            } else {
                                next.insert(area)
                            }
                            selection.wrappedValue = next
                            onChange?(next)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isSelected ? .accentColor : .secondary)
                                Text(area)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var areaOptions: [String] {
        let names = deviceStore.devices.compactMap { device -> String? in
            let area = device.areaName ?? device.area
            let trimmed = area?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        return Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func reloadAll() async {
        await store.loadSellingTargets(mode: session.haMode)
        await store.loadTenants()
        await deviceStore.refresh(background: true)
        // sync tenant areaSelections to current data
        var next: [Int: Set<String>] = [:]
        for t in store.tenants {
            next[t.id] = Set(t.areas)
        }
        areaSelections = next
    }

    private func performReset(mode: String, cleanup: String) async {
        selectedCleanup = mode
        await store.resetProperty(mode: mode, cleanup: cleanup, haMode: session.haMode)
        if store.sellingError == nil {
            await session.resetApp()
        }
        confirmResetMode = nil
        showConfirmReset = false
    }

    private var homeNetworkBadge: some View {
        Group {
            if session.haMode == .home {
                HStack(spacing: 4) {
                    Image(systemName: session.onHomeNetwork ? "wifi" : "wifi.slash")
                        .foregroundColor(session.onHomeNetwork ? .green : .orange)
                    Text(session.onHomeNetwork ? "On Home Network" : "Not on Home Network")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var cloudBadge: some View {
        Group {
            if session.haMode == .cloud {
                HStack(spacing: 4) {
                    Image(systemName: session.cloudAvailable ? "cloud.fill" : "cloud.slash.fill")
                        .foregroundColor(session.cloudAvailable ? .green : .orange)
                    Text(session.cloudAvailable ? "Cloud Available" : "Cloud Unavailable")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Collapsible Section

    private struct CollapsibleSection<Content: View>: View {
        let title: String
        @Binding var expanded: Bool
        let content: () -> Content

        init(title: String, expanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
            self.title = title
            self._expanded = expanded
            self.content = content
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation { expanded.toggle() }
                } label: {
                    HStack {
                        Text(title)
                            .font(.headline)
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if expanded {
                    content()
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        }
    }

// MARK: - SectionCard

private struct SectionCard<Content: View>: View {
    let title: String
    var tint: Color = Color(.secondarySystemBackground)
    let content: () -> Content

    init(title: String, tint: Color = Color(.secondarySystemBackground), @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.tint = tint
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding()
        .background(tint)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

// MARK: - TenantCard

private struct TenantCard: View {
    let tenant: TenantRecord
    @State var areas: Set<String>
    let areaOptions: [String]
    let isEditing: Bool
    let onEdit: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    let onApply: (Set<String>) -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tenant.username)
                    .font(.headline)
                Spacer()
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }

            Text(areas.isEmpty ? "Areas: None" : "Areas: \(areas.sorted().joined(separator: ", "))")
                .font(.caption)
                .foregroundColor(.secondary)

            if isEditing {
                areaChips
                    .padding(.bottom, 6)
                HStack {
                    Button("Cancel") {
                        areas = Set(tenant.areas)
                        onCancel()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Apply changes") {
                        onApply(areas)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Button("Edit") { onEdit() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
        .confirmationDialog("Delete user?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var areaChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            if areaOptions.isEmpty {
                Text("No areas available yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(areaOptions, id: \.self) { area in
                        let selected = areas.contains(area)
                        Button {
                            if selected {
                                areas.remove(area)
                            } else {
                                areas.insert(area)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selected ? .accentColor : .secondary)
                                Text(area)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

}

}
