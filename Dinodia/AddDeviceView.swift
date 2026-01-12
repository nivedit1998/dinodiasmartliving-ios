import SwiftUI

struct AddDeviceView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: TabRouter
    @StateObject var store: AddDeviceStore

    @State private var selectedArea: String = ""
    @State private var customName: String = ""
    @State private var pairingCode: String = ""
    @State private var selectedHaLabelId: String?
    @State private var selectedType: String?
    @State private var haLabels: [HaLabel] = []
    @State private var labelsLoading = false
    @State private var showScanner = false
    @State private var stepIndex: Int = 0
    @State private var showMatterFlow = false
    @State private var formError: String?
    @State private var remoteStatus: RemoteAccessStatus = .checking

    var body: some View {
        List {
            statusSection

            if session.haMode == .cloud {
                Section {
                    Text("Add Devices is available in Home Mode on the same Wi‑Fi as your Dinodia Hub.")
                        .foregroundColor(.secondary)
                    Button("Switch to Home Mode") {
                        session.setHaMode(.home)
                        Task { await initialize() }
                    }
                }
            } else {
                deviceTypeSection
                if showMatterFlow {
                    headerSection
                    targetSection
                    overrideSection
                    matterSection
                    discoverySection
                    setupSection
                }
            }
        }
        .navigationTitle("Add devices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                ModeSwitchPrompt(
                    targetMode: session.haMode == .home ? .cloud : .home,
                    userId: session.user?.id,
                    onSwitched: { Task { await initialize(force: true) } }
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
        .onAppear {
            Task { await initialize() }
        }
        .refreshable {
            await initialize(force: true)
        }
        .alert("Dinodia", isPresented: Binding(get: { formError != nil }, set: { _ in formError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(formError ?? "")
        }
        .onChange(of: session.user?.id) { _, newValue in
            if newValue == nil {
                showScanner = false
                showMatterFlow = false
                formError = nil
            }
        }
        .sheet(isPresented: $showScanner) {
            NavigationStack {
                ZStack {
                    QRScannerView { code in
                        pairingCode = code
                        showScanner = false
                        stepIndex = 1
                    }
                    VStack {
                        HStack {
                            Button("Close") { showScanner = false }
                                .padding()
                            Spacer()
                        }
                        Spacer()
                        Text("Align the QR / Matter code in the frame. Camera access is required to scan.")
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .padding(.bottom, 20)
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    private var deviceTypeSection: some View {
        Section("Device types") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Add Matter device")
                    .font(.headline)
                Text("Walk through pairing a Matter‑over‑Wi‑Fi device.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Button(showMatterFlow ? "Restart flow" : "Start") {
                    stepIndex = 0
                    showMatterFlow = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isWorking)
            }
            .padding(.vertical, 4)
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Add Matter device")
                        .font(.headline)
                    Spacer()
                    Button("Back to device types") {
                        showMatterFlow = false
                        stepIndex = 0
                    }
                    .font(.caption)
                }
                Text("Choose how you want to add a device.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if !pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Pairing code set for Matter flow.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                stepChips
            }
        }
    }

    private var stepChips: some View {
        let steps = ["Area", "Pairing code", "Metadata", "Discovery"]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(steps.indices, id: \.self) { idx in
                    let active = idx == stepIndex
                    let done = idx < stepIndex
                    HStack(spacing: 6) {
                        Text("\(idx + 1)")
                            .font(.caption)
                            .padding(6)
                            .background(done ? Color.green.opacity(0.2) : (active ? Color.accentColor.opacity(0.2) : Color(.systemGray5)))
                            .cornerRadius(10)
                        Text(steps[idx])
                            .font(.caption)
                            .foregroundColor(active ? .primary : .secondary)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(active ? Color.accentColor.opacity(0.12) : (done ? Color.green.opacity(0.12) : Color(.systemGray6)))
                    .cornerRadius(12)
                }
            }
        }
        .padding(.top, 4)
    }

    private func statusRow(_ session: CommissionSession) -> some View {
        let statusText: String
        switch session.status {
        case .succeeded: statusText = "Succeeded"
        case .failed: statusText = "Failed"
        case .canceled: statusText = "Canceled"
        case .needsInput: statusText = "Needs input"
        case .inProgress: statusText = "In progress"
        case .unknown: statusText = "In progress"
        }
        return HStack {
            Text("Status")
            Spacer()
            Text(statusText)
                .fontWeight(.semibold)
        }
    }

    private var statusSection: some View {
        Section("Status") {
            HStack {
                Text(session.haMode == .cloud ? "Cloud Mode" : "Home Mode")
                Spacer()
                wifiStatus
            }
            if let active = store.activeSession {
                Text(statusMessage(for: active))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Waiting to start commissioning...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if session.haMode == .cloud {
                Text("Switch to Home Mode to add devices.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            if session.haMode == .cloud && remoteStatus == .locked {
                Text("Cloud access locked. Finish remote access setup to use cloud.")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }

    private var targetSection: some View {
        Section("Target area") {
            Text("Choose where this device should appear. You can only place devices in areas you have access to.")
                .font(.caption)
                .foregroundColor(.secondary)
            if store.areas.isEmpty {
                Text("No areas available for your account.")
                    .foregroundColor(.secondary)
            } else {
                Picker("Area", selection: $selectedArea) {
                    ForEach(store.areas, id: \.self) { area in
                        Text(area).tag(area)
                    }
                }
            }
            TextField("Optional name", text: $customName)
            TextField("Pairing code", text: $pairingCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button {
                showScanner = true
                stepIndex = 1
            } label: {
                Label("Scan QR code", systemImage: "qrcode.viewfinder")
            }
            .disabled(session.haMode != .home)
        }
    }

    private var overrideSection: some View {
        Section("Overrides (optional)") {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    Task { await loadHaLabels() }
                    stepIndex = 2
                } label: {
                    HStack {
                        Text(selectedLabelName)
                        Spacer()
                        if labelsLoading { ProgressView().scaleEffect(0.8) }
                        Image(systemName: "chevron.down")
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(session.haMode != .home)
                Text("Dinodia Hub label for new device entities.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text("Dinodia device type override")
                .font(.subheadline)
            Picker("Dinodia device type override", selection: Binding(
                get: { selectedType ?? "" },
                set: { selectedType = $0.isEmpty ? nil : $0 }
            )) {
                Text("None").tag("")
                ForEach(LabelRegistry.orderedLabels, id: \.self) { label in
                    Text(label).tag(label)
                }
            }
            Text("This controls how the device tile behaves in the dashboard.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var matterSection: some View {
        Section("Pairing code") {
            Text("Enter the Matter pairing code. You can find it on the device or its packaging.")
                .font(.caption)
                .foregroundColor(.secondary)
            Button {
                showScanner = true
                stepIndex = 1
            } label: {
                Label("Scan QR code", systemImage: "qrcode.viewfinder")
            }
            .disabled(session.haMode != .home)
            if !pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Pairing code: \(pairingCode)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var discoverySection: some View {
        Section("Discovered devices") {
            if store.isLoading {
                HStack {
                    ProgressView()
                    Text("Searching for devices on your network...")
                        .foregroundColor(.secondary)
                }
            } else if let error = store.errorMessage, store.flows.isEmpty {
                NoticeView(kind: .error, message: error)
            } else if store.flows.isEmpty {
                Text("No devices discovered right now. Make sure the device is in pairing mode and on the same network.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(store.flows) { flow in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(flow.title)
                                    .font(.headline)
                                Text(flow.description ?? "")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                if let source = flow.source {
                                    Text("Source: \(source)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button {
                                Task {
                                    await store.start(
                                        flowId: flow.flowId,
                                        area: selectedArea,
                                        name: customName,
                                        haLabelId: selectedHaLabelId,
                                        dinodiaType: selectedType,
                                        pairingCode: pairingCode
                                    )
                                }
                            } label: {
                                Text("Start")
                            }
                            .disabled(selectedArea.isEmpty || store.isWorking)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var setupSection: some View {
        Group {
            if let session = store.activeSession {
                Section("Setup status") {
                    Text("We’re sending the pairing request to your Dinodia Hub. Keep this page open until it finishes.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    statusRow(session)
                    if let error = session.error, !error.isEmpty {
                        NoticeView(kind: .error, message: error)
                    }
                    if !store.warnings.isEmpty {
                        ForEach(store.warnings, id: \.self) { warn in
                            Text(warn)
                                .foregroundColor(.orange)
                                .font(.footnote)
                        }
                    }
                    if let devices = session.newDeviceIds, !devices.isEmpty {
                        Text("New devices: \(devices.joined(separator: ", "))")
                            .font(.caption)
                    }
                    if let entities = session.newEntityIds, !entities.isEmpty {
                        Text("New entities: \(entities.joined(separator: ", "))")
                            .font(.caption)
                    }
                    if let type = session.requestedDinodiaType, !type.isEmpty {
                        Text("Type override: \(type)")
                            .font(.caption)
                    }
                    if let label = session.requestedHaLabelId, !label.isEmpty {
                        Text("Hub label: \(label)")
                            .font(.caption)
                    }
                    if let fields = session.lastHaStep?.dataSchema, !fields.isEmpty, session.isFinal != true {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(fields) { field in
                                fieldInput(field)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    HStack {
                        if session.isFinal != true {
                            Button("Continue") {
                                if validateRequiredFields() {
                                    Task { await store.step(sessionId: session.id) }
                                } else {
                                    formError = "Please fill in required fields."
                                }
                            }
                            .disabled(store.isWorking)
                            Button("Reset") {
                                store.resetSession()
                            }
                            .disabled(store.isWorking)
                        }
                        Button("Cancel", role: .destructive) {
                            Task { await store.cancel(sessionId: session.id) }
                        }
                        .disabled(store.isWorking || session.isFinal == true)
                    }
                }
            }
        }
    }

    private func fieldInput(_ field: SchemaField) -> some View {
        let type = field.type?.lowercased() ?? ""
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(field.name)
                    .font(.subheadline)
                if field.required == true {
                    Text("*").foregroundColor(.red)
                }
            }
            if let options = field.options, !options.isEmpty {
                Picker(field.name, selection: Binding(
                    get: { store.userInput[field.name] ?? options.first ?? "" },
                    set: { store.userInput[field.name] = $0 }
                )) {
                    ForEach(options, id: \.self) { opt in
                        Text(opt).tag(opt)
                    }
                }
                .pickerStyle(.menu)
            } else if type == "boolean" || type == "bool" {
                Toggle(isOn: Binding(
                    get: { (store.userInput[field.name] ?? "false").lowercased() == "true" },
                    set: { store.userInput[field.name] = $0 ? "true" : "false" }
                )) {
                    Text("Enable")
                }
            } else {
                TextField("Enter \(field.name)", text: Binding(
                    get: { store.userInput[field.name] ?? "" },
                    set: { store.userInput[field.name] = $0 }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }
        }
    }

    private func validateRequiredFields() -> Bool {
        guard let fields = store.activeSession?.lastHaStep?.dataSchema else { return true }
        for field in fields where field.required == true {
            let value = store.userInput[field.name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if value.isEmpty {
                return false
            }
        }
        return true
    }

    private func initialize() async {
        guard session.user?.id != nil else { return }
        if session.haMode == .cloud { return }
        await store.loadAreas()
        if selectedArea.isEmpty, let first = store.areas.first {
            selectedArea = first
        }
        await store.loadFlows()
        await refreshRemoteStatus()
    }

    private func initialize(force: Bool) async {
        if force {
            await store.loadFlows()
        }
        await initialize()
    }

    private func loadHaLabels() async {
        guard session.haMode == .home, let ha = session.connection(for: .home) else { return }
        labelsLoading = true
        defer { labelsLoading = false }
        do {
            haLabels = try await HAService.listLabels(ha)
        } catch {
            formError = error.localizedDescription
        }
    }

    private func refreshRemoteStatus() async {
        remoteStatus = await RemoteAccessService.checkRemoteAccessEnabled() ? .enabled : .locked
    }

    private var wifiStatus: some View {
        HStack(spacing: 6) {
            if session.haMode == .home {
                Image(systemName: session.onHomeNetwork ? "wifi" : "wifi.slash")
                    .foregroundColor(session.onHomeNetwork ? .green : .orange)
                Text(session.onHomeNetwork ? "On Home Network" : "Not on Home Network")
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

    private var selectedLabelName: String {
        guard let id = selectedHaLabelId, !id.isEmpty else { return "Hub label: None" }
        if let found = haLabels.first(where: { $0.label_id == id }) {
            return "Hub label: \(found.name)"
        }
        return "Hub label: \(id)"
    }

    private func statusMessage(for session: CommissionSession) -> String {
        switch session.status {
        case .succeeded:
            return "Commissioning completed."
        case .failed:
            return session.error ?? "Commissioning failed."
        case .canceled:
            return "Commissioning was canceled."
        case .needsInput:
            return "Waiting for pairing details..."
        case .inProgress, .unknown:
            if session.lastHaStep?.type == "progress" {
                return "Commissioning in progress..."
            }
            return "Contacting your Dinodia Hub..."
        }
    }

}
