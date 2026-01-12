import SwiftUI

struct AutomationDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: TabRouter

    let automation: AutomationSummary
    let mode: HaMode
    let haConnection: HaConnection?
    let devices: [UIDevice]
    let deviceOptions: [DeviceOption]
    let onChange: () -> Void

    @State private var isEnabled: Bool
    @State private var isWorking = false
    @State private var showDeleteConfirm = false
    @State private var alertMessage: String?
    @State private var showEditSheet = false
    @State private var editDraft: AutomationDraft?

    init(automation: AutomationSummary, mode: HaMode, haConnection: HaConnection?, devices: [UIDevice], deviceOptions: [DeviceOption], onChange: @escaping () -> Void) {
        self.automation = automation
        self.mode = mode
        self.haConnection = haConnection
        self.devices = devices
        self.deviceOptions = deviceOptions
        self.onChange = onChange
        _isEnabled = State(initialValue: automation.enabled)
    }

    var body: some View {
        Form {
            navSection

            Section("Status") {
                Toggle("Enabled", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, value in
                        Task { await setEnabled(value) }
                    }
                    .disabled(isWorking)
                if let modeStr = automation.mode {
                    HStack {
                        Text("Mode")
                        Spacer()
                        Text(modeStr.capitalized)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let desc = automation.description.isEmpty ? automation.basicSummary : automation.description, !desc.isEmpty {
                Section("Description") {
                    Text(desc)
                }
            }

            Section("When") {
                Text(automation.triggerSummary ?? "Unknown trigger")
            }

            Section("Then") {
                Text(automation.actionSummary ?? "Unknown action")
            }

            if let entities = automation.entities, !entities.isEmpty {
                Section("Entities") {
                    ForEach(entities, id: \.self) { entity in
                        Text(entity)
                    }
                }
            }

            Section("Info") {
                if automation.hasTemplates == true {
                    Label("Contains templates (view-only)", systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                }
                HStack {
                    Text("Automation ID")
                    Spacer()
                    Text(automation.id)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Section {
                Button("Delete Automation", role: .destructive) {
                    showDeleteConfirm = true
                }
                .disabled(isWorking)
            }
        }
        .navigationTitle(automation.alias.isEmpty ? automation.id : automation.alias)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Dinodia", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .toolbar {
            if automation.canEdit != false {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") { beginEdit() }
                        .disabled(isWorking)
                }
            }
        }
        .confirmationDialog("Delete automation?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task { await delete() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: session.user?.id) { _, newValue in
            guard newValue == nil else { return }
            showEditSheet = false
            showDeleteConfirm = false
            alertMessage = nil
            editDraft = nil
            isWorking = false
        }
        .sheet(isPresented: $showEditSheet) {
            NavigationStack {
                AutomationEditorView(
                    mode: mode,
                    devices: devices,
                    initialDraft: editDraft ?? AutomationsService.draftFromSummary(automation),
                    defaultEntityId: nil
                ) { draft in
                    Task { await updateAutomation(draft) }
                }
            }
        }
    }

    private var navSection: some View {
        Section {
            quickNav
            Label(mode == .cloud ? "Cloud Mode" : "Home Mode", systemImage: "bolt.horizontal.circle")
        }
    }

    private var quickNav: some View {
        let isAdmin = session.user?.role == .ADMIN
        return HStack(spacing: 8) {
            tabButton("Dashboard", active: isAdmin ? router.adminTab == .dashboard : router.tenantTab == .dashboard) {
                if isAdmin { router.adminTab = .dashboard } else { router.tenantTab = .dashboard }
            }
            tabButton("Automations", active: true) {}
            if isAdmin {
                tabButton("Home Setup", active: router.adminTab == .homeSetup) { router.adminTab = .homeSetup }
            } else {
                tabButton("Add Devices", active: router.tenantTab == .addDevices) { router.tenantTab = .addDevices }
            }
            tabButton("Settings", active: isAdmin ? router.adminTab == .settings : router.tenantTab == .settings) {
                if isAdmin { router.adminTab = .settings } else { router.tenantTab = .settings }
            }
        }
        .font(.footnote)
        .padding(.vertical, 4)
    }

    private func tabButton(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(active ? Color.accentColor.opacity(0.15) : Color(.systemGray5))
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func setEnabled(_ value: Bool) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await AutomationsService.setEnabled(id: automation.id, enabled: value, mode: mode, haConnection: haConnection)
            onChange()
        } catch {
            if error.isCancellation { return }
            alertMessage = error.localizedDescription
            isEnabled = !value
        }
    }

    private func beginEdit() {
        guard automation.canEdit != false else {
            alertMessage = "This automation uses templates and cannot be edited here."
            return
        }
        guard let draft = AutomationsService.draftFromSummary(automation) else {
            alertMessage = "This automation includes advanced options we can't edit yet."
            return
        }
        editDraft = draft
        showEditSheet = true
    }

    private func updateAutomation(_ draft: AutomationDraft) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await AutomationsService.update(id: automation.id, draft: draft, mode: mode, haConnection: haConnection)
            showEditSheet = false
            onChange()
        } catch {
            if error.isCancellation { return }
            alertMessage = error.localizedDescription
        }
    }

    private func delete() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await AutomationsService.delete(id: automation.id, mode: mode, haConnection: haConnection)
            onChange()
        } catch {
            if error.isCancellation { return }
            alertMessage = error.localizedDescription
        }
    }
}
