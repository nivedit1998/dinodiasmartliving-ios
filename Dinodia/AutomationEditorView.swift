import SwiftUI
import UIKit

struct AutomationEditorView: View {
    let mode: HaMode
    let devices: [UIDevice]
    let initialDraft: AutomationDraft?
    let defaultEntityId: String?
    let onSave: (AutomationDraft) -> Void

    @State private var alias: String
    @State private var description: String
    @State private var anyTime: Bool
    @State private var selectedDays: Set<String>
    @State private var selectedTime: Date
    @State private var triggerDeviceId: String?
    @State private var selectedTriggerId: String?
    @State private var actionDeviceId: String?
    @State private var selectedActionId: String?
    @State private var actionValue: Double?
    @State private var alertMessage: String?
    @State private var pendingTrigger: AutomationTrigger?
    @State private var pendingAction: DeviceAction?
    @State private var prefillApplied = false
    @State private var isSubmitting = false
    @FocusState private var focusedField: Field?

    private static let weekdays = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    private enum Field {
        case alias
        case description
    }

    init(
        mode: HaMode,
        devices: [UIDevice],
        initialDraft: AutomationDraft?,
        defaultEntityId: String?,
        onSave: @escaping (AutomationDraft) -> Void
    ) {
        self.mode = mode
        self.devices = devices
        self.initialDraft = initialDraft
        self.defaultEntityId = defaultEntityId
        self.onSave = onSave

        let trigger = initialDraft?.triggers.first
        let hasTimeTrigger: Bool
        if case .time = trigger {
            hasTimeTrigger = true
        } else {
            hasTimeTrigger = false
        }
        _alias = State(initialValue: initialDraft?.alias ?? "")
        _description = State(initialValue: initialDraft?.description ?? "")
        _anyTime = State(initialValue: !hasTimeTrigger)
        let draftDays = initialDraft?.daysOfWeek ?? []
        let initialDays = draftDays.isEmpty ? AutomationEditorView.weekdays : draftDays
        _selectedDays = State(initialValue: Set(initialDays))
        _selectedTime = State(initialValue: AutomationEditorView.parseTime(initialDraft?.triggerTime) ?? AutomationEditorView.defaultTime())
        _triggerDeviceId = State(initialValue: AutomationEditorView.initialTriggerDeviceId(trigger: trigger, defaultEntityId: defaultEntityId, anyTime: !hasTimeTrigger))
        _selectedTriggerId = State(initialValue: nil)
        _actionDeviceId = State(initialValue: AutomationEditorView.initialActionDeviceId(devices: devices, initialDraft: initialDraft, defaultEntityId: defaultEntityId))
        _selectedActionId = State(initialValue: nil)
        _actionValue = State(initialValue: AutomationEditorView.initialActionValue(from: initialDraft))
        _pendingTrigger = State(initialValue: trigger)
        _pendingAction = State(initialValue: AutomationEditorView.initialAction(from: initialDraft))
    }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $alias)
                    .focused($focusedField, equals: .alias)
                TextField("Description", text: $description, axis: .vertical)
                    .focused($focusedField, equals: .description)
            }

            Section("Trigger") {
                timePicker
                if anyTime {
                    triggerDevicePicker
                    triggerConditionPicker
                }
            }

            Section("Action") {
                actionDevicePicker
                actionConditionPicker
                actionValuePicker
                Button(isEditing ? "Save changes" : "Create automation") {
                    save()
                }
                .frame(maxWidth: .infinity)
                .disabled(alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .navigationTitle(isEditing ? "Edit Automation" : "Create Automation")
        .alert("Dinodia", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .onAppear { applyPrefillIfNeeded() }
        .onChange(of: anyTime) { _, newValue in
            dismissKeyboard()
            if !newValue {
                triggerDeviceId = nil
                selectedTriggerId = nil
            }
        }
        .onChange(of: selectedTime) { _, _ in
            if anyTime {
                anyTime = false
            }
            dismissKeyboard()
        }
        .onChange(of: eligibleDeviceIds) { _, _ in
            ensureActionSelection()
        }
        .onChange(of: triggerDeviceId) { _, _ in
            ensureTriggerSelection()
        }
        .onChange(of: actionDeviceId) { _, _ in
            ensureActionSelection()
        }
        .onChange(of: selectedActionId) { _, _ in
            actionValue = nil
        }
    }

    private var isEditing: Bool {
        initialDraft?.id != nil
    }

    private var eligibleDevices: [UIDevice] {
        AutomationCapabilities.eligibleDevices(devices)
    }

    private var eligibleTriggerDevices: [UIDevice] {
        sortedDevices(eligibleDevices.filter { !AutomationCapabilities.triggers(for: $0).isEmpty })
    }

    private var eligibleActionDevices: [UIDevice] {
        sortedDevices(eligibleDevices.filter { !AutomationCapabilities.actions(for: $0).isEmpty })
    }

    private var eligibleDeviceIds: [String] {
        eligibleActionDevices.map { $0.entityId }
    }

    private var triggerDevice: UIDevice? {
        guard let id = triggerDeviceId else { return nil }
        return eligibleTriggerDevices.first { $0.entityId == id }
    }

    private var actionDevice: UIDevice? {
        guard let id = actionDeviceId else { return nil }
        return eligibleActionDevices.first { $0.entityId == id }
    }

    private var triggerSpecs: [AutomationTriggerSpec] {
        guard let device = triggerDevice else { return [] }
        return AutomationCapabilities.triggers(for: device)
    }

    private var actionSpecs: [AutomationActionSpec] {
        guard let device = actionDevice else { return [] }
        return AutomationCapabilities.actions(for: device)
    }

    private var selectedTriggerSpec: AutomationTriggerSpec? {
        guard let id = selectedTriggerId else { return nil }
        return triggerSpecs.first { $0.id == id }
    }

    private var selectedActionSpec: AutomationActionSpec? {
        guard let id = selectedActionId else { return nil }
        return actionSpecs.first { $0.id == id }
    }

    private var timePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schedule")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 10) {
                modeChip(title: "Specific time", isSelected: !anyTime) {
                    anyTime = false
                }
                modeChip(title: "Any Time", isSelected: anyTime) {
                    anyTime = true
                }
            }

            if !anyTime {
                DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                daysChips
            }
        }
    }

    private var daysChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Days")
                .font(.caption)
                .foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AutomationEditorView.weekdays, id: \.self) { day in
                        let isSelected = selectedDays.contains(day)
                        Button {
                            if isSelected {
                                selectedDays.remove(day)
                            } else {
                                selectedDays.insert(day)
                            }
                            dismissKeyboard()
                        } label: {
                            Text(day.uppercased())
                                .font(.caption2)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(isSelected ? Color.accentColor.opacity(0.2) : Color(.systemGray5))
                                .foregroundColor(isSelected ? .accentColor : .primary)
                                .cornerRadius(10)
                        }
                    }
                }
            }
        }
    }

    private var triggerDevicePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trigger device")
                .font(.caption)
                .foregroundColor(.secondary)
            if eligibleTriggerDevices.isEmpty {
                Text("No eligible devices for automations.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Menu {
                    ForEach(eligibleTriggerDevices, id: \.entityId) { device in
                        Button {
                            triggerDeviceId = device.entityId
                        } label: {
                            Text(deviceLabel(for: device))
                        }
                    }
                } label: {
                    selectionRow(title: selectedTriggerDeviceLabel)
                }
            }
        }
    }

    private var triggerConditionPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trigger condition")
                .font(.caption)
                .foregroundColor(.secondary)
            if triggerDevice == nil {
                Text("Select a trigger device to continue.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if triggerSpecs.isEmpty {
                Text("No triggers available for this device.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(triggerSpecs) { spec in
                    let selected = spec.id == selectedTriggerId
                    Button {
                        selectedTriggerId = spec.id
                    } label: {
                        HStack {
                            Text(spec.label)
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding()
                        .background(selected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var actionDevicePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Action device")
                .font(.caption)
                .foregroundColor(.secondary)
            if eligibleActionDevices.isEmpty {
                Text("No eligible devices for automations.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Menu {
                    ForEach(eligibleActionDevices, id: \.entityId) { device in
                        Button {
                            actionDeviceId = device.entityId
                        } label: {
                            Text(deviceLabel(for: device))
                        }
                    }
                } label: {
                    selectionRow(title: selectedActionDeviceLabel)
                }
            }
        }
    }

    private var actionConditionPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Action to perform")
                .font(.caption)
                .foregroundColor(.secondary)
            if actionDevice == nil {
                Text("Select an action device to continue.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if actionSpecs.isEmpty {
                Text("No actions available for this device.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(actionSpecs) { spec in
                    let selected = spec.id == selectedActionId
                    Button {
                        selectedActionId = spec.id
                    } label: {
                        HStack {
                            Text(spec.label)
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding()
                        .background(selected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var actionValuePicker: some View {
        if let spec = selectedActionSpec, spec.kind == .slider, let device = actionDevice {
            let min = spec.min ?? 0
            let max = spec.max ?? 100
            let step = spec.step ?? 1
            let defaultValue = actionValue ?? defaultActionValue(for: device, spec: spec)
            VStack(alignment: .leading, spacing: 8) {
                Text("\(spec.label) \(Int(defaultValue))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Slider(
                    value: Binding(
                        get: { actionValue ?? defaultValue },
                        set: { actionValue = $0 }
                    ),
                    in: min...max,
                    step: step
                )
            }
        }
    }

    private func selectionRow(title: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.primary)
            Spacer()
            Image(systemName: "chevron.down")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private var selectedTriggerDeviceLabel: String {
        guard let device = triggerDevice else { return "Select device" }
        return deviceLabel(for: device)
    }

    private var selectedActionDeviceLabel: String {
        guard let device = actionDevice else { return "Select device" }
        return deviceLabel(for: device)
    }

    private func modeChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            dismissKeyboard()
            action()
        }) {
            Text(title)
                .font(.caption)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color(.systemGray5))
                .foregroundColor(isSelected ? .accentColor : .primary)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func deviceLabel(for device: UIDevice) -> String {
        let primary = getPrimaryLabel(for: device)
        let name = normalizeLabel(device.label).isEmpty ? device.name : normalizeLabel(device.label)
        let area = device.areaName ?? device.area
        let parts = [primary, name, area].compactMap { part -> String? in
            guard let trimmed = part?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
            return trimmed
        }
        let label = parts.joined(separator: " • ")
        return label.isEmpty ? device.entityId : label
    }

    private func sortedDevices(_ devices: [UIDevice]) -> [UIDevice] {
        devices.sorted { lhs, rhs in
            deviceLabel(for: lhs).localizedCaseInsensitiveCompare(deviceLabel(for: rhs)) == .orderedAscending
        }
    }

    private func save() {
        guard !isSubmitting else { return }
        dismissKeyboard()
        let cleanedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedAlias.isEmpty {
            alertMessage = "Please enter a name for this automation."
            return
        }

        guard let actionDevice, let actionSpec = selectedActionSpec else {
            alertMessage = "Choose an action device and action."
            return
        }

        var triggers: [AutomationTrigger] = []
        if anyTime {
            guard let triggerDevice, let triggerSpec = selectedTriggerSpec else {
                alertMessage = "Choose a trigger device and condition."
                return
            }
            triggers.append(toTriggerDraft(spec: triggerSpec, device: triggerDevice))
        } else {
            let days = orderedDays(from: selectedDays)
            if days.isEmpty {
                alertMessage = "Select at least one day for the time trigger."
                return
            }
            let timeValue = AutomationEditorView.formatTime(from: selectedTime)
            triggers.append(.time(TimeTrigger(at: timeValue, daysOfWeek: days)))
        }

        let action = toActionDraft(spec: actionSpec, device: actionDevice, value: actionValue)
        let days = anyTime ? nil : orderedDays(from: selectedDays)
        let triggerTime = anyTime ? nil : AutomationEditorView.formatTime(from: selectedTime)
        let draft = AutomationDraft(
            id: initialDraft?.id,
            alias: cleanedAlias,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description.trimmingCharacters(in: .whitespacesAndNewlines),
            mode: .single,
            triggers: triggers,
            actions: [action],
            daysOfWeek: days,
            triggerTime: triggerTime
        )
        isSubmitting = true
        onSave(draft)
        // onSave is async upstream; keep button disabled until caller dismisses.
    }

    private func toActionDraft(spec: AutomationActionSpec, device: UIDevice, value: Double?) -> AutomationAction {
        switch spec.kind {
        case .fixed:
            return .device(DeviceAction(entityId: device.entityId, command: spec.command, value: spec.value))
        case .button:
            return .device(DeviceAction(entityId: device.entityId, command: spec.command, value: value ?? spec.value))
        case .slider:
            return .device(DeviceAction(entityId: device.entityId, command: spec.command, value: value ?? defaultActionValue(for: device, spec: spec)))
        }
    }

    private func toTriggerDraft(spec: AutomationTriggerSpec, device: UIDevice) -> AutomationTrigger {
        switch spec.kind {
        case .state:
            return .state(StateTrigger(entityId: device.entityId, to: spec.entityState, from: nil))
        case .attributeDelta:
            return .numericDelta(NumericDeltaTrigger(entityId: device.entityId, attribute: spec.attribute ?? "state", direction: spec.direction ?? "increase"))
        case .position:
            let attribute = spec.attributes?.first ?? "position"
            return .position(PositionTrigger(entityId: device.entityId, attribute: attribute, value: spec.equals ?? 0))
        }
    }

    private func ensureTriggerSelection() {
        guard anyTime else { return }
        if let pendingTrigger {
            if let match = matchTriggerSpec(pendingTrigger, in: triggerSpecs) {
                selectedTriggerId = match.id
            }
            self.pendingTrigger = nil
            return
        }
        if selectedTriggerId == nil || !triggerSpecs.contains(where: { $0.id == selectedTriggerId }) {
            selectedTriggerId = triggerSpecs.first?.id
        }
    }

    private func ensureActionSelection() {
        if actionDeviceId == nil || !eligibleActionDevices.contains(where: { $0.entityId == actionDeviceId }) {
            actionDeviceId = eligibleActionDevices.first?.entityId
        }
        if let pendingAction {
            if let match = matchActionSpec(pendingAction, in: actionSpecs) {
                selectedActionId = match.id
            }
            self.pendingAction = nil
            return
        }
        if selectedActionId == nil || !actionSpecs.contains(where: { $0.id == selectedActionId }) {
            selectedActionId = actionSpecs.first?.id
        }
    }

    private func applyPrefillIfNeeded() {
        guard !prefillApplied else { return }
        prefillApplied = true
        ensureActionSelection()
        ensureTriggerSelection()
    }

    private func matchTriggerSpec(_ trigger: AutomationTrigger, in specs: [AutomationTriggerSpec]) -> AutomationTriggerSpec? {
        switch trigger {
        case .state(let t):
            return specs.first { $0.kind == .state && $0.entityState == t.to }
        case .numericDelta(let t):
            return specs.first { $0.kind == .attributeDelta && $0.attribute == t.attribute && $0.direction == t.direction }
        case .position(let t):
            return specs.first { $0.kind == .position && $0.equals == t.value }
        case .time(_):
            return nil
        }
    }

    private func matchActionSpec(_ action: DeviceAction, in specs: [AutomationActionSpec]) -> AutomationActionSpec? {
        let command = action.command
        return specs.first(where: { spec in
            if spec.command == command { return true }
            if matchesMediaPower(spec.command, command) { return true }
            if matchesLightPower(spec.command, command) { return true }
            return false
        })
    }

    private func matchesMediaPower(_ a: DeviceCommand, _ b: DeviceCommand) -> Bool {
        let onCommands: Set<DeviceCommand> = [.tvTurnOn, .speakerTurnOn]
        let offCommands: Set<DeviceCommand> = [.tvTurnOff, .speakerTurnOff]
        return (onCommands.contains(a) && onCommands.contains(b)) || (offCommands.contains(a) && offCommands.contains(b))
    }

    private func matchesLightPower(_ a: DeviceCommand, _ b: DeviceCommand) -> Bool {
        let onCommands: Set<DeviceCommand> = [.lightTurnOn, .lightToggle]
        let offCommands: Set<DeviceCommand> = [.lightTurnOff]
        return (onCommands.contains(a) && onCommands.contains(b)) || (offCommands.contains(a) && offCommands.contains(b))
    }

    private func defaultActionValue(for device: UIDevice, spec: AutomationActionSpec) -> Double {
        let label = getPrimaryLabel(for: device)
        let rawValue: Double
        if label == "Light" {
            rawValue = Double(brightnessPercent(for: device) ?? 50)
        } else if label == "Blind" {
            rawValue = Double(blindPositionPercent(for: device) ?? 0)
        } else if label == "TV" || label == "Speaker" {
            rawValue = volumePercent(for: device)
        } else if label == "Boiler" {
            rawValue = (device.attributes["temperature"]?.anyValue as? Double)
                ?? (device.attributes["current_temperature"]?.anyValue as? Double)
                ?? 20
        } else {
            rawValue = spec.value ?? 0
        }
        if let min = spec.min, let max = spec.max {
            return Swift.max(min, Swift.min(max, rawValue))
        }
        return rawValue
    }

    private func orderedDays(from set: Set<String>) -> [String] {
        AutomationEditorView.weekdays.filter { set.contains($0) }
    }

    private static func defaultTime() -> Date {
        Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private static func formatTime(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return String(format: "%02d:%02d", hour, minute)
    }

    private static func parseTime(_ raw: String?) -> Date? {
        guard let raw, raw.contains(":") else { return nil }
        let parts = raw.split(separator: ":")
        guard parts.count >= 2 else { return nil }
        let hour = Int(parts[0]) ?? 0
        let minute = Int(parts[1]) ?? 0
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())
    }

    private static func initialTriggerDeviceId(trigger: AutomationTrigger?, defaultEntityId: String?, anyTime: Bool) -> String? {
        guard anyTime else { return nil }
        switch trigger {
        case .state(let t):
            return t.entityId
        case .numericDelta(let t):
            return t.entityId
        case .position(let t):
            return t.entityId
        case .time(_):
            return nil
        case .none:
            return defaultEntityId
        }
    }

    private static func initialActionDeviceId(devices: [UIDevice], initialDraft: AutomationDraft?, defaultEntityId: String?) -> String? {
        if case .device(let action)? = initialDraft?.actions.first {
            return action.entityId
        }
        if let defaultEntityId {
            return defaultEntityId
        }
        return AutomationCapabilities.eligibleDevices(devices).first?.entityId
    }

    private static func initialActionValue(from draft: AutomationDraft?) -> Double? {
        if case .device(let action)? = draft?.actions.first {
            return action.value
        }
        return nil
    }

    private static func initialAction(from draft: AutomationDraft?) -> DeviceAction? {
        if case .device(let action)? = draft?.actions.first {
            return action
        }
        return nil
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
