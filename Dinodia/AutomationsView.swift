import SwiftUI

private enum TriggerKind: String, CaseIterable, Identifiable {
    case state = "State change"
    case time = "Time schedule"
    case numericDelta = "Numeric delta"
    case position = "Position equals"
    var id: String { rawValue }
}

struct AutomationsView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var store: AutomationsStore
    @StateObject private var deviceStore: DeviceStore

    @State private var showCreateSheet = false
    @State private var showDeviceFilter = false
    @State private var selectedEntityId: String?
    @State private var remoteStatus: String = "enabled"
    @State private var alertMessage: String?
    private var isAdmin: Bool { session.user?.role == .ADMIN }

    init(mode: HaMode, haConnection: HaConnection?, userId: Int) {
        _store = StateObject(wrappedValue: AutomationsStore(mode: mode, haConnection: haConnection))
        _deviceStore = StateObject(wrappedValue: DeviceStore(userId: userId, mode: mode))
    }

    var body: some View {
        List {
            header
            deviceFilter

            if let error = store.errorMessage {
                NoticeView(kind: .error, message: error)
            }

            if store.automations.isEmpty && store.isLoading {
                HStack {
                    ProgressView()
                    Text("Loading automations…")
                        .foregroundColor(.secondary)
                }
            }

            ForEach(filteredAutomations, id: \.id) { item in
                automationRow(item)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Automations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                modePill
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
            await store.load()
        }
        .task {
            await refreshRemoteStatus()
        }
        .alert("Dinodia", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .onChange(of: session.user?.id) { _, newValue in
            if newValue == nil {
                showCreateSheet = false
                showDeviceFilter = false
                alertMessage = nil
                selectedEntityId = nil
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            if !isAdmin {
                NavigationStack {
                    AutomationEditorView(
                        mode: store.mode,
                        devices: deviceStore.devices,
                        initialDraft: nil,
                        defaultEntityId: selectedEntityId
                    ) { draft in
                        Task {
                            await store.create(draft: draft)
                            showCreateSheet = false
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scenes that keep your place effortless.")
                .foregroundColor(.secondary)
                .font(.subheadline)
            Text(store.mode == .cloud ? "Remote automations via Dinodia Cloud." : "Automations from your Dinodia Hub.")
                .foregroundColor(.secondary)
                .font(.subheadline)
            if store.isSaving {
                ProgressView()
                    .scaleEffect(0.9)
            }
            wifiStatus
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var deviceFilter: some View {
        Group {
            if deviceOptions.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("All Automations")
                            .font(.headline)
                        Spacer()
                        if !isAdmin {
                            Button {
                                showCreateSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                    Text("Add Automation")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.isSaving)
                        }
                    }
                    Button {
                        showDeviceFilter = true
                    } label: {
                        HStack {
                            Text(selectedEntityLabel)
                                .foregroundColor(.primary)
                            Spacer()
                            if deviceStore.isRefreshing {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Image(systemName: "chevron.down")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                    if isAdmin {
                        Text("Homeowners can view automations but cannot create or delete.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .sheet(isPresented: $showDeviceFilter) {
                    NavigationStack {
                        List {
                            Button {
                                selectedEntityId = nil
                                showDeviceFilter = false
                            } label: {
                                HStack {
                                    Text("All Automations")
                                    if selectedEntityId == nil {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                            ForEach(deviceOptions, id: \.id) { option in
                                Button {
                                    selectedEntityId = option.id
                                    showDeviceFilter = false
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(option.label)
                                            Text(option.id)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        if selectedEntityId == option.id {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                }
                            }
                        }
                        .navigationTitle("Select device")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { showDeviceFilter = false }
                            }
                        }
                    }
                }
            }
        }
    }

    private var filteredAutomations: [AutomationSummary] {
        guard let entity = selectedEntityId, !entity.isEmpty else { return store.automations }
        let selectedDeviceId = deviceId(for: entity)
        return store.automations.filter { automation in
            let targets = actionTargets(for: automation)
            if targets.entityIds.contains(entity) { return true }
            if let selectedDeviceId, !selectedDeviceId.isEmpty {
                if targets.deviceIds.contains(selectedDeviceId) { return true }
                if targets.entityIds.contains(where: { deviceId(for: $0) == selectedDeviceId }) {
                    return true
                }
            }
            return false
        }
    }

    private var deviceOptions: [DeviceOption] {
        AutomationCapabilities.eligibleDevices(deviceStore.devices).map { device in
            let primary = getPrimaryLabel(for: device)
            let name = normalizeLabel(device.label).isEmpty ? device.name : normalizeLabel(device.label)
            let area = device.areaName ?? device.area
            let parts = [primary, name, area].compactMap { part -> String? in
                guard let trimmed = part?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
                return trimmed
            }
            let label = parts.joined(separator: " • ")
            return DeviceOption(id: device.entityId, label: label.isEmpty ? device.entityId : label)
        }
        .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    private var selectedEntityLabel: String {
        guard let id = selectedEntityId else { return "All Automations" }
        return deviceOptions.first(where: { $0.id == id })?.label ?? id
    }

    private func automationRow(_ item: AutomationSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.alias.isEmpty ? item.id : item.alias)
                        .font(.headline)
                    if let basic = item.basicSummary, !basic.isEmpty {
                        Text(basic)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else if !item.description.isEmpty {
                        Text(item.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if !isAdmin {
                    Button {
                        Task { await store.delete(id: item.id) }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .padding(8)
                            .background(Circle().fill(Color.red.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isSaving)
                }
            }

            let details = automationDetails(for: item)
            summaryLine(title: "Target", value: details.target)
            summaryLine(title: "Trigger", value: details.trigger)
            summaryLine(title: "Action", value: details.action)
        }
        .padding(.vertical, 8)
    }

    private func automationDetails(for item: AutomationSummary) -> (target: String, trigger: String, action: String) {
        var target = targetLabel(for: item) ?? "—"
        var triggerText = item.triggerSummary ?? "—"
        var actionText = item.actionSummary ?? "—"

        if let draft = AutomationsService.draftFromSummary(item) {
            if case .device(let action)? = draft.actions.first {
                target = deviceLabel(for: action.entityId) ?? action.entityId
                actionText = actionSummary(action)
            }
            if let trig = draft.triggers.first {
                triggerText = triggerSummary(trig, days: draft.daysOfWeek, explicitTime: draft.triggerTime)
            }
        } else if let raw = unwrapRaw(item.raw) {
            let summary = summarizeAutomation(raw)
            if let primaryName = summary.primaryName { target = primaryName }
            triggerText = summary.triggerSummary
            actionText = summary.actionSummary
        }

        return (target, triggerText, actionText)
    }

    private func targetEntity(for item: AutomationSummary) -> String? {
        let targets = actionTargets(for: item)
        if let first = targets.entityIds.first { return first }
        if let deviceId = targets.deviceIds.first {
            return deviceStore.devices.first(where: { $0.deviceId == deviceId })?.entityId
        }
        return nil
    }

    private func targetLabel(for item: AutomationSummary) -> String? {
        guard let entityId = targetEntity(for: item) else { return nil }
        return deviceLabel(for: entityId) ?? entityId
    }

    private func deviceLabel(for entityId: String) -> String? {
        guard let device = deviceStore.devices.first(where: { $0.entityId == entityId }) else { return nil }
        let primary = getPrimaryLabel(for: device)
        let name = normalizeLabel(device.label).isEmpty ? device.name : normalizeLabel(device.label)
        let area = device.areaName ?? device.area
        let parts = [primary, name, area].compactMap { part -> String? in
            guard let trimmed = part?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
            return trimmed
        }
        return parts.joined(separator: " • ")
    }

    private func deviceId(for entityId: String) -> String? {
        return deviceStore.devices.first(where: { $0.entityId == entityId })?.deviceId
    }

    private func actionTargets(for item: AutomationSummary) -> (entityIds: [String], deviceIds: [String]) {
        var entityIds = item.entities ?? []
        var deviceIds = item.targetDeviceIds ?? []

        if let draft = AutomationsService.draftFromSummary(item) {
            if case .device(let action)? = draft.actions.first {
                entityIds.append(action.entityId)
            }
        } else if let raw = unwrapRaw(item.raw) {
            let targets = extractActionTargets(from: raw)
            entityIds.append(contentsOf: targets.entityIds)
            deviceIds.append(contentsOf: targets.deviceIds)
        }

        return (Array(Set(entityIds)), Array(Set(deviceIds)))
    }

    private func summaryLine(title: String, value: String) -> some View {
        Text("\(title): \(value)")
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private func extractActionTargets(from raw: [String: Any]) -> (entityIds: [String], deviceIds: [String]) {
        var entityIds = Set<String>()
        var deviceIds = Set<String>()

        func addEntity(_ value: Any?) {
            if let str = value as? String { entityIds.insert(str) }
            if let arr = value as? [String] { arr.forEach { entityIds.insert($0) } }
        }

        func addDevice(_ value: Any?) {
            if let str = value as? String { deviceIds.insert(str) }
            if let arr = value as? [String] { arr.forEach { deviceIds.insert($0) } }
        }

        func visit(_ node: Any) {
            guard let dict = node as? [String: Any] else { return }
            addEntity(dict["entity_id"])
            if let data = dict["data"] as? [String: Any] {
                addEntity(data["entity_id"])
            }
            if let target = dict["target"] as? [String: Any] {
                addEntity(target["entity_id"])
                addDevice(target["device_id"])
            }
            addDevice(dict["device_id"])

            if let sequence = dict["sequence"] as? [Any] {
                sequence.forEach { visit($0) }
            }
            if let choose = dict["choose"] as? [Any] {
                choose.forEach { branch in
                    if let branchDict = branch as? [String: Any] {
                        if let seq = branchDict["sequence"] as? [Any] {
                            seq.forEach { visit($0) }
                        }
                        if let cond = branchDict["conditions"] as? [Any] {
                            cond.forEach { visit($0) }
                        }
                    }
                }
            }
        }

        let actions = toArray(raw["actions"] ?? raw["action"])
        actions.forEach { visit($0) }

        return (Array(entityIds), Array(deviceIds))
    }

    private func summarizeAutomation(_ raw: [String: Any]) -> (triggerSummary: String, actionSummary: String, primaryName: String?) {
        let triggers = toArray(raw["triggers"] ?? raw["trigger"])
        let actions = toArray(raw["actions"] ?? raw["action"])
        let triggerSummary = triggers.first.flatMap { summarizeTrigger($0) } ?? "—"
        let actionSummary = actions.first.flatMap { summarizeAction($0).summary } ?? "—"
        let primaryName = actions.first.flatMap { summarizeAction($0).primaryName }
        return (triggerSummary, actionSummary, primaryName)
    }

    private func summarizeTrigger(_ value: Any) -> String? {
        guard let dict = value as? [String: Any] else { return nil }
        let platform = (dict["platform"] as? String) ?? (dict["kind"] as? String) ?? ""
        if platform == "time" {
            if let at = dict["at"] as? String, !at.isEmpty {
                return "At \(at)"
            }
            return "Time schedule"
        }
        if platform == "state" {
            let entityId = dict["entity_id"] as? String ?? dict["entityId"] as? String
            let from = dict["from"] ?? dict["from_state"]
            let to = dict["to"] ?? dict["to_state"]
            let label = entityId.flatMap { deviceLabel(for: $0) } ?? entityId ?? "Device"
            if let from, let to {
                return "\(label): \(from) → \(to)"
            }
            if let to {
                return "\(label) → \(to)"
            }
            if let from {
                return "\(label) from \(from)"
            }
            return "\(label) changes"
        }
        if platform == "numeric_state" || platform == "numeric_delta" || platform == "position_equals" {
            let entityId = dict["entity_id"] as? String ?? dict["entityId"] as? String
            let label = entityId.flatMap { deviceLabel(for: $0) } ?? entityId ?? "Value"
            if platform == "numeric_delta" {
                let attribute = dict["attribute"] as? String
                let dir = (dict["direction"] as? String)?.lowercased() == "decrease" ? "decreases" : "increases"
                let suffix = attribute.map { " (\($0))" } ?? ""
                return "\(label)\(suffix) \(dir)"
            }
            if platform == "position_equals" {
                let attribute = dict["attribute"] as? String
                let value = dict["to"] ?? dict["value"]
                let suffix = attribute.map { " (\($0))" } ?? ""
                return "\(label)\(suffix) = \(value ?? "")"
            }
            let attribute = dict["attribute"] as? String
            let above = dict["above"]
            let below = dict["below"]
            var bounds: [String] = []
            if let above { bounds.append(">\(above)") }
            if let below { bounds.append("<\(below)") }
            let suffix = attribute.map { " (\($0))" } ?? ""
            if bounds.isEmpty { return "\(label)\(suffix)" }
            return "\(label)\(suffix) \(bounds.joined(separator: " "))"
        }
        return nil
    }

    private func summarizeAction(_ value: Any) -> (summary: String?, primaryName: String?) {
        guard let dict = value as? [String: Any] else { return (nil, nil) }
        let entityId = extractEntityId(from: dict)
        let label = entityId.flatMap { deviceLabel(for: $0) } ?? entityId ?? "Device"
        if let service = dict["service"] as? String {
            return ("\(service) on \(label)", label)
        }
        if let type = dict["type"] as? String {
            return ("\(type) on \(label)", label)
        }
        if let command = dict["command"] as? String {
            return ("\(command) on \(label)", label)
        }
        return ("Custom action on \(label)", label)
    }

    private func extractEntityId(from dict: [String: Any]) -> String? {
        if let entity = dict["entity_id"] as? String { return entity }
        if let entity = dict["entityId"] as? String { return entity }
        if let target = dict["target"] as? [String: Any] {
            if let entity = target["entity_id"] as? String { return entity }
            if let list = target["entity_id"] as? [Any], let first = list.first as? String { return first }
        }
        if let data = dict["data"] as? [String: Any] {
            if let entity = data["entity_id"] as? String { return entity }
            if let list = data["entity_id"] as? [Any], let first = list.first as? String { return first }
        }
        return nil
    }

    private func toArray(_ value: Any?) -> [Any] {
        if let arr = value as? [Any] { return arr }
        if let single = value { return [single] }
        return []
    }

    private func unwrapRaw(_ raw: Any?) -> [String: Any]? {
        if let dict = raw as? [String: Any] { return dict }
        if let wrapper = raw as? AnyCodable, let dict = wrapper.value as? [String: Any] { return dict }
        return nil
    }

    private func triggerSummary(_ trigger: AutomationTrigger, days: [String]?, explicitTime: String?) -> String {
        switch trigger {
        case .time(let t):
            let dayList = (t.daysOfWeek ?? days)?.map { $0.capitalized }.joined(separator: ", ")
            if let dayList, !dayList.isEmpty {
                return "At \(t.at) on \(dayList)"
            }
            return "At \(t.at)"
        case .state(let t):
            let label = deviceLabel(for: t.entityId) ?? t.entityId
            if let to = t.to, let from = t.from, !from.isEmpty {
                return "\(label): \(from) → \(to)"
            }
            if let to = t.to, !to.isEmpty {
                return "\(label) → \(to)"
            }
            if let from = t.from, !from.isEmpty {
                return "\(label) from \(from)"
            }
            return "\(label) changes"
        case .numericDelta(let t):
            let label = deviceLabel(for: t.entityId) ?? t.entityId
            let attr = t.attribute.isEmpty ? "" : " (\(t.attribute))"
            let dir = t.direction == "decrease" ? "decreases" : "increases"
            return "\(label)\(attr) \(dir)"
        case .position(let t):
            let label = deviceLabel(for: t.entityId) ?? t.entityId
            let attr = t.attribute.isEmpty ? "" : " (\(t.attribute))"
            let value = Int(t.value.rounded())
            return "\(label)\(attr) = \(value)"
        }
    }

    private func actionSummary(_ action: DeviceAction) -> String {
        let label = deviceLabel(for: action.entityId) ?? action.entityId
        let valueText: String? = {
            guard let val = action.value else { return nil }
            let rounded = val.rounded() == val ? String(Int(val)) : String(format: "%.1f", val)
            return rounded
        }()

        switch action.command {
        case .lightToggle: return "\(label): Toggle"
        case .lightTurnOn: return "\(label): Turn on"
        case .lightTurnOff: return "\(label): Turn off"
        case .lightSetBrightness:
            return "\(label): Brightness \(valueText ?? "")%"
        case .blindOpen: return "\(label): Open"
        case .blindClose: return "\(label): Close"
        case .blindSetPosition:
            return "\(label): Position \(valueText ?? "")%"
        case .mediaPlayPause: return "\(label): Play/Pause"
        case .mediaNext: return "\(label): Next"
        case .mediaPrevious: return "\(label): Previous"
        case .mediaVolumeUp: return "\(label): Volume up"
        case .mediaVolumeDown: return "\(label): Volume down"
        case .mediaVolumeSet:
            return "\(label): Volume \(valueText ?? "")%"
        case .boilerTempUp: return "\(label): Temp up"
        case .boilerTempDown: return "\(label): Temp down"
        case .boilerSetTemperature:
            return "\(label): Set temp \(valueText ?? "")"
        case .tvTogglePower: return "\(label): Power toggle"
        case .tvTurnOn: return "\(label): Power on"
        case .tvTurnOff: return "\(label): Power off"
        case .speakerTogglePower: return "\(label): Power toggle"
        case .speakerTurnOn: return "\(label): Power on"
        case .speakerTurnOff: return "\(label): Power off"
        }
    }

    private func refreshRemoteStatus() async {
        remoteStatus = "enabled"
    }

    private var wifiStatus: some View {
        Group {
            if store.mode == .home {
                HStack(spacing: 4) {
                    Image(systemName: session.onHomeNetwork ? "wifi" : "wifi.slash")
                        .foregroundColor(session.onHomeNetwork ? .green : .orange)
                    Text(session.onHomeNetwork ? "On Home Network" : "Not on Home Network")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
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

    private var modePill: some View {
        ModeSwitchPrompt(
            targetMode: store.mode == .home ? .cloud : .home,
            userId: session.user?.id,
            onSwitched: { Task { await store.load() } }
        )
        .environmentObject(session)
    }
}

struct QuickAutomationForm: View {
    let mode: HaMode
    let initialDraft: AutomationDraft?
    fileprivate let deviceOptions: [DeviceOption]
    let defaultEntityId: String?
    let onSave: (AutomationDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var alias: String
    @State private var description: String
    @State private var triggerKind: TriggerKind
    @State private var triggerEntityId: String
    @State private var triggerToState: String
    @State private var triggerFromState: String
    @State private var triggerTime: String
    @State private var selectedDays: Set<String>
    @State private var numericAttribute: String
    @State private var numericDirection: String
    @State private var positionAttribute: String
    @State private var positionValue: String
    @State private var actionEntityId: String
    @State private var selectedCommand: DeviceCommand
    @State private var actionValue: String
    @State private var selectedMode: AutomationMode

    private let days = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

    init(
        mode: HaMode,
        initialDraft: AutomationDraft? = nil,
        deviceOptions: [DeviceOption] = [],
        defaultEntityId: String? = nil,
        onSave: @escaping (AutomationDraft) -> Void
    ) {
        self.mode = mode
        self.initialDraft = initialDraft
        self.deviceOptions = deviceOptions
        self.defaultEntityId = defaultEntityId
        self.onSave = onSave

        let defaultEntity = defaultEntityId ?? ""

        _alias = State(initialValue: initialDraft?.alias ?? "")
        _description = State(initialValue: initialDraft?.description ?? "")
        _triggerKind = State(initialValue: QuickAutomationForm.initialTriggerKind(from: initialDraft))
        _triggerEntityId = State(initialValue: QuickAutomationForm.initialTriggerEntity(from: initialDraft, fallback: defaultEntity))
        _triggerToState = State(initialValue: QuickAutomationForm.initialToState(from: initialDraft))
        _triggerFromState = State(initialValue: QuickAutomationForm.initialFromState(from: initialDraft))
        _triggerTime = State(initialValue: QuickAutomationForm.initialTime(from: initialDraft))
        _selectedDays = State(initialValue: Set(initialDraft?.daysOfWeek ?? []))
        _numericAttribute = State(initialValue: QuickAutomationForm.initialNumericAttribute(from: initialDraft))
        _numericDirection = State(initialValue: QuickAutomationForm.initialNumericDirection(from: initialDraft))
        _positionAttribute = State(initialValue: QuickAutomationForm.initialPositionAttribute(from: initialDraft))
        _positionValue = State(initialValue: QuickAutomationForm.initialPositionValue(from: initialDraft))
        _actionEntityId = State(initialValue: QuickAutomationForm.initialActionEntity(from: initialDraft, fallback: defaultEntity))
        _selectedCommand = State(initialValue: QuickAutomationForm.initialCommand(from: initialDraft))
        _actionValue = State(initialValue: QuickAutomationForm.initialActionValue(from: initialDraft))
        _selectedMode = State(initialValue: initialDraft?.mode ?? .single)
    }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $alias)
                TextField("Description (optional)", text: $description)
                Picker("Mode", selection: $selectedMode) {
                    ForEach([AutomationMode.single, .restart, .queued, .parallel], id: \.self) { mode in
                        Text(modeLabel(mode)).tag(mode)
                    }
                }
            }

            Section("Trigger") {
                Picker("Type", selection: $triggerKind) {
                    ForEach(TriggerKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                switch triggerKind {
                case .state:
                    TextField("Entity ID (e.g. binary_sensor.door)", text: $triggerEntityId)
                    devicePicker(title: "Select entity", binding: $triggerEntityId)
                    TextField("To state (e.g. on)", text: $triggerToState)
                    TextField("From state (optional)", text: $triggerFromState)
                case .time:
                    TextField("Time (HH:mm)", text: $triggerTime)
                        .keyboardType(.numbersAndPunctuation)
                    daysPicker
                case .numericDelta:
                    TextField("Entity ID (e.g. sensor.temperature)", text: $triggerEntityId)
                    devicePicker(title: "Select entity", binding: $triggerEntityId)
                    TextField("Attribute (e.g. temperature)", text: $numericAttribute)
                    Picker("Direction", selection: $numericDirection) {
                        Text("Increases").tag("increase")
                        Text("Decreases").tag("decrease")
                    }
                case .position:
                    TextField("Entity ID (e.g. cover.living_room)", text: $triggerEntityId)
                    devicePicker(title: "Select entity", binding: $triggerEntityId)
                    TextField("Attribute (e.g. position)", text: $positionAttribute)
                    TextField("Value (number)", text: $positionValue)
                        .keyboardType(.decimalPad)
                }
            }

            Section("Action") {
                TextField("Target entity (e.g. light.living_room)", text: $actionEntityId)
                devicePicker(title: "Select target", binding: $actionEntityId)
                Picker("Command", selection: $selectedCommand) {
                    ForEach(DeviceCommand.allCases, id: \.self) { cmd in
                        Text(label(for: cmd)).tag(cmd)
                    }
                }
                if requiresValue(selectedCommand) {
                    TextField("Value (e.g. brightness 0-100)", text: $actionValue)
                        .keyboardType(.decimalPad)
                }
            }
        }
        .navigationTitle(isEditing ? "Edit Automation" : "New Automation")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
    }

    private var isEditing: Bool {
        initialDraft != nil
    }

    private var canSave: Bool {
        !alias.trimmingCharacters(in: .whitespaces).isEmpty && isValidAction && isValidTrigger
    }

    private var isValidAction: Bool {
        let entityOk = !actionEntityId.trimmingCharacters(in: .whitespaces).isEmpty
        if requiresValue(selectedCommand) {
            return entityOk && actionValueNumber != nil
        }
        return entityOk
    }

    private var isValidTrigger: Bool {
        let id = triggerEntityId.trimmingCharacters(in: .whitespacesAndNewlines)
        switch triggerKind {
        case .state:
            return !id.isEmpty && (!triggerToState.trimmingCharacters(in: .whitespaces).isEmpty || !triggerFromState.trimmingCharacters(in: .whitespaces).isEmpty)
        case .time:
            return !triggerTime.trimmingCharacters(in: .whitespaces).isEmpty
        case .numericDelta:
            return !id.isEmpty && !numericAttribute.trimmingCharacters(in: .whitespaces).isEmpty
        case .position:
            return !id.isEmpty && !positionAttribute.trimmingCharacters(in: .whitespaces).isEmpty && number(from: positionValue) != nil
        }
    }

    private var actionValueNumber: Double? {
        number(from: actionValue)
    }

    private var daysPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(days, id: \.self) { day in
                    let isSelected = selectedDays.contains(day)
                    Button {
                        if isSelected {
                            selectedDays.remove(day)
                        } else {
                            selectedDays.insert(day)
                        }
                    } label: {
                        Text(day.uppercased())
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray5))
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func save() {
        let cleanedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        var triggers: [AutomationTrigger] = []
        switch triggerKind {
        case .state:
            let trigger = StateTrigger(
                entityId: triggerEntityId.trimmingCharacters(in: .whitespacesAndNewlines),
                to: triggerToState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : triggerToState.trimmingCharacters(in: .whitespacesAndNewlines),
                from: triggerFromState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : triggerFromState.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            triggers.append(.state(trigger))
        case .time:
            let time = triggerTime.trimmingCharacters(in: .whitespacesAndNewlines)
            let trigger = TimeTrigger(at: time, daysOfWeek: selectedDays.isEmpty ? nil : Array(selectedDays))
            triggers.append(.time(trigger))
        case .numericDelta:
            let trigger = NumericDeltaTrigger(
                entityId: triggerEntityId.trimmingCharacters(in: .whitespacesAndNewlines),
                attribute: numericAttribute.trimmingCharacters(in: .whitespacesAndNewlines),
                direction: numericDirection
            )
            triggers.append(.numericDelta(trigger))
        case .position:
            let trigger = PositionTrigger(
                entityId: triggerEntityId.trimmingCharacters(in: .whitespacesAndNewlines),
                attribute: positionAttribute.trimmingCharacters(in: .whitespacesAndNewlines),
                value: number(from: positionValue) ?? 0
            )
            triggers.append(.position(trigger))
        }

        var actions: [AutomationAction] = []
        let value = actionValueNumber
        let action = DeviceAction(
            entityId: actionEntityId.trimmingCharacters(in: .whitespacesAndNewlines),
            command: selectedCommand,
            value: value
        )
        actions.append(.device(action))

        let draft = AutomationDraft(
            id: initialDraft?.id,
            alias: cleanedAlias,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description,
            mode: selectedMode,
            triggers: triggers,
            actions: actions,
            daysOfWeek: selectedDays.isEmpty ? nil : Array(selectedDays),
            triggerTime: triggerKind == .time ? triggerTime : nil
        )
        onSave(draft)
    }

    private func number(from value: String) -> Double? {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func devicePicker(title: String, binding: Binding<String>) -> some View {
        Group {
            if deviceOptions.isEmpty {
                EmptyView()
            } else {
                Menu {
                    ForEach(deviceOptions) { option in
                        Button {
                            binding.wrappedValue = option.id
                        } label: {
                            VStack(alignment: .leading) {
                                Text(option.label)
                                Text(option.id)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(title)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func label(for command: DeviceCommand) -> String {
        switch command {
        case .lightToggle: return "Light toggle"
        case .lightTurnOn: return "Light turn on"
        case .lightTurnOff: return "Light turn off"
        case .lightSetBrightness: return "Light set brightness"
        case .blindOpen: return "Blinds open"
        case .blindClose: return "Blinds close"
        case .blindSetPosition: return "Blinds position"
        case .mediaPlayPause: return "Media play/pause"
        case .mediaNext: return "Media next"
        case .mediaPrevious: return "Media previous"
        case .mediaVolumeUp: return "Media volume up"
        case .mediaVolumeDown: return "Media volume down"
        case .mediaVolumeSet: return "Media volume set"
        case .boilerTempUp: return "Boiler temp up"
        case .boilerTempDown: return "Boiler temp down"
        case .boilerSetTemperature: return "Boiler set temperature"
        case .tvTogglePower: return "TV power toggle"
        case .tvTurnOn: return "TV turn on"
        case .tvTurnOff: return "TV turn off"
        case .speakerTogglePower: return "Speaker power toggle"
        case .speakerTurnOn: return "Speaker turn on"
        case .speakerTurnOff: return "Speaker turn off"
        }
    }

    private func modeLabel(_ mode: AutomationMode) -> String {
        switch mode {
        case .single: return "Single"
        case .restart: return "Restart"
        case .queued: return "Queued"
        case .parallel: return "Parallel"
        }
    }

    private func requiresValue(_ command: DeviceCommand) -> Bool {
        switch command {
        case .lightSetBrightness, .mediaVolumeSet, .blindSetPosition, .boilerSetTemperature:
            return true
        default:
            return false
        }
    }

    // MARK: - Initial value helpers

    private static func initialTriggerKind(from draft: AutomationDraft?) -> TriggerKind {
        guard let trigger = draft?.triggers.first else { return .state }
        switch trigger {
        case .state: return .state
        case .time: return .time
        case .numericDelta: return .numericDelta
        case .position: return .position
        }
    }

    private static func initialTriggerEntity(from draft: AutomationDraft?, fallback: String) -> String {
        guard let trigger = draft?.triggers.first else { return fallback }
        switch trigger {
        case .state(let t): return t.entityId
        case .time: return fallback
        case .numericDelta(let t): return t.entityId
        case .position(let t): return t.entityId
        }
    }

    private static func initialToState(from draft: AutomationDraft?) -> String {
        if case .state(let t)? = draft?.triggers.first {
            return t.to ?? ""
        }
        return ""
    }

    private static func initialFromState(from draft: AutomationDraft?) -> String {
        if case .state(let t)? = draft?.triggers.first {
            return t.from ?? ""
        }
        return ""
    }

    private static func initialTime(from draft: AutomationDraft?) -> String {
        if case .time(let t)? = draft?.triggers.first {
            return t.at
        }
        return draft?.triggerTime ?? "07:00"
    }

    private static func initialNumericAttribute(from draft: AutomationDraft?) -> String {
        if case .numericDelta(let t)? = draft?.triggers.first {
            return t.attribute
        }
        return ""
    }

    private static func initialNumericDirection(from draft: AutomationDraft?) -> String {
        if case .numericDelta(let t)? = draft?.triggers.first {
            return t.direction
        }
        return "increase"
    }

    private static func initialPositionAttribute(from draft: AutomationDraft?) -> String {
        if case .position(let t)? = draft?.triggers.first {
            return t.attribute
        }
        return ""
    }

    private static func initialPositionValue(from draft: AutomationDraft?) -> String {
        if case .position(let t)? = draft?.triggers.first {
            return String(t.value)
        }
        return ""
    }

    private static func initialActionEntity(from draft: AutomationDraft?, fallback: String) -> String {
        if case .device(let action)? = draft?.actions.first {
            return action.entityId
        }
        return fallback
    }

    private static func initialCommand(from draft: AutomationDraft?) -> DeviceCommand {
        if case .device(let action)? = draft?.actions.first {
            return action.command
        }
        return .lightToggle
    }

    private static func initialActionValue(from draft: AutomationDraft?) -> String {
        if case .device(let action)? = draft?.actions.first, let value = action.value {
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        }
        return ""
    }
}

struct DeviceOption: Identifiable {
    let id: String
    let label: String
}

private struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(8)
    }
}
