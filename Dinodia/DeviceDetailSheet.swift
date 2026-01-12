import SwiftUI
import Combine

struct DeviceDetailSheet: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: TabRouter
    @Environment(\.dismiss) private var dismiss

    let device: UIDevice
    let haMode: HaMode
    let linkedSensors: [UIDevice]
    let relatedDevices: [UIDevice]?
    let allowSensorHistory: Bool
    let showControls: Bool
    let showStateText: Bool
    var onDeviceUpdated: (() -> Void)?

    @State private var isSending = false
    @State private var alertMessage: String?
    @State private var sensorHistory: [String: SensorHistoryState] = [:]
    @State private var brightnessValue: Double = 0
    @State private var blindPositionValue: Double = 0
    @State private var boilerTargetValue: Double = 0
    @State private var isAdjustingBoilerTarget: Bool = false
    @State private var cameraRefresh = Date()
    @State private var showEditSheet = false
    @State private var editName: String = ""
    @State private var editTravel: String = ""
    @State private var isSavingEdit = false
    @State private var editError: String?

    private var canShowSensorHistory: Bool {
        allowSensorHistory && session.user?.role == .ADMIN
    }

    private var canControlDevices: Bool {
        session.user?.role == .TENANT
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if showControls {
                        controls
                    }
                    if !linkedSensors.isEmpty {
                        sensorSection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(device.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if session.user?.role == .ADMIN {
                        Menu {
                            Button("Rename") {
                                editName = device.name
                                editTravel = device.blindTravelSeconds != nil ? "\(Int(device.blindTravelSeconds ?? 0))" : ""
                                showEditSheet = true
                            }
                            if getPrimaryLabel(for: device) == "Blind" {
                                Button("Set travel time") {
                                    editName = device.name
                                    editTravel = device.blindTravelSeconds != nil ? "\(Int(device.blindTravelSeconds ?? 0))" : ""
                                    showEditSheet = true
                                }
                            }
                        } label: {
                          Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .alert("Dinodia", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .onAppear {
                brightnessValue = Double(brightnessPercent(for: device) ?? 0)
                blindPositionValue = Double(blindPositionPercent(for: device) ?? 0)
                let initialBoiler = boilerSetpoint(from: device.attributes) ?? 20
                boilerTargetValue = Double(initialBoiler)
                linkedSensors.forEach { ensureHistoryState(for: $0) }
            }
            .onChange(of: linkedSensors.map(\.entityId)) { _, _ in
                linkedSensors.forEach { ensureHistoryState(for: $0) }
            }
            .onChange(of: device.attributes) { _, newAttrs in
                if !isAdjustingBoilerTarget {
                    let next = boilerSetpoint(from: newAttrs) ?? boilerTargetValue
                    boilerTargetValue = Double(next)
                }
            }
            .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in
                cameraRefresh = Date()
            }
            .sheet(isPresented: $showEditSheet) {
                NavigationStack {
                    Form {
                        Section("Display name") {
                            TextField("Device name", text: $editName)
                        }
                        if getPrimaryLabel(for: device) == "Blind" {
                            Section("Blind travel time (seconds)") {
                                TextField("Leave empty for default", text: $editTravel)
                                    .keyboardType(.numberPad)
                                if let err = editError {
                                    Text(err).foregroundColor(.red)
                                }
                            }
                        }
                    }
                    .navigationTitle("Edit device")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showEditSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(isSavingEdit ? "Saving…" : "Save") {
                                Task { await saveEdit() }
                            }
                            .disabled(isSavingEdit)
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(getPrimaryLabel(for: device))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Text(device.name)
                .font(.title2)
                .fontWeight(.bold)
            HStack {
                Text(device.areaName ?? "Unassigned area")
                    .foregroundColor(.secondary)
                Spacer()
                Label(haMode == .cloud ? "Cloud Mode" : "Home Mode", systemImage: "bolt.horizontal.circle")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            if showStateText {
                Text("State: \(device.state)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    @ViewBuilder
    private var controls: some View {
        let label = getPrimaryLabel(for: device)
        let allowControl = canControlDevices
        let controlDisabled = isSending || !allowControl
        switch label {
        case "Light":
            VStack(alignment: .leading, spacing: 16) {
                Button(action: { Task { await send(.lightToggle) } }) {
                    Text(device.state.lowercased() == "on" ? "Turn off" : "Turn on")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(controlDisabled)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Brightness \(Int(brightnessValue))%")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Slider(value: $brightnessValue, in: 0...100, step: 1) { editing in
                        if !editing {
                            let value = brightnessValue
                            Task { await send(.lightSetBrightness, value: value) }
                        }
                    }
                    .disabled(controlDisabled)
                }
            }
        case "Blind":
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button("Open") { Task { await send(.blindOpen) } }
                    Button("Close") { Task { await send(.blindClose) } }
                }
                .buttonStyle(.bordered)
                .disabled(controlDisabled)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Position \(Int(blindPositionValue))%")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Slider(value: $blindPositionValue, in: 0...100, step: 1) { editing in
                        if !editing {
                            let value = blindPositionValue
                            Task { await send(.blindSetPosition, value: value) }
                        }
                    }
                    .disabled(controlDisabled)
                }
            }
        case "Boiler":
            VStack(alignment: .leading, spacing: 12) {
                let target = boilerSetpoint(from: device.attributes)
                let currentTemp = boilerCurrentTemperature(from: device.attributes)
                if let currentTemp {
                    Text("Now \(Int(currentTemp))°")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Button {
                        Task { await send(.boilerTempDown) }
                    } label: {
                        Label("Temp", systemImage: "minus")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controlDisabled)
                    if let target {
                        VStack(spacing: 2) {
                            Text("Target")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(Int(target))°")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .frame(minWidth: 50)
                        }
                        .frame(minWidth: 70)
                    }
                    Button {
                        Task { await send(.boilerTempUp) }
                    } label: {
                        Label("Temp", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controlDisabled)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Set temperature \(Int(boilerTargetValue))°")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Slider(value: $boilerTargetValue, in: 10...35, step: 1) { editing in
                        isAdjustingBoilerTarget = editing
                        if !editing {
                            let value = boilerTargetValue
                            Task { await send(.boilerSetTemperature, value: value) }
                        }
                    }
                    .disabled(controlDisabled)
                }
            }
        case "Spotify":
            VStack(spacing: 12) {
                HStack {
                    Button(action: { Task { await send(.mediaPrevious) } }) { Text("Prev") }
                    Button(action: { Task { await send(.mediaPlayPause) } }) { Text(device.state.lowercased() == "playing" ? "Pause" : "Play") }
                    Button(action: { Task { await send(.mediaNext) } }) { Text("Next") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(controlDisabled)
                HStack {
                    Button("Vol -") { Task { await send(.mediaVolumeDown) } }
                    Button("Vol +") { Task { await send(.mediaVolumeUp) } }
                }
                .buttonStyle(.bordered)
                .disabled(controlDisabled)
            }
        case "TV", "Speaker":
            VStack(spacing: 12) {
                Button(action: { Task { await send(label == "TV" ? .tvTogglePower : .speakerTogglePower) } }) {
                    Text(device.state.lowercased() == "on" ? "Power off" : "Power on")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(controlDisabled)
                HStack {
                    Button("Vol -") { Task { await send(.mediaVolumeDown) } }
                    Button("Vol +") { Task { await send(.mediaVolumeUp) } }
                }
                .buttonStyle(.bordered)
                .disabled(controlDisabled)
            }
        case "Doorbell":
            cameraView(for: device)
        case "Home Security":
            securityCameraGrid
        default:
            attributesSection
        }
    }

    private var attributesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attributes")
                .font(.headline)
            ForEach(device.attributes.keys.sorted(), id: \.self) { key in
                if let value = device.attributes[key]?.anyValue {
                    Text("\(key): \(String(describing: value))")
                        .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func cameraView(for device: UIDevice) -> some View {
        Text("Camera view is not available in this app yet.")
            .foregroundColor(.secondary)
    }

    @ViewBuilder
    private var securityCameraGrid: some View {
        Text("Camera tiles are not available in this app yet.")
            .foregroundColor(.secondary)
    }

    private var sensorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Linked Sensors")
                .font(.headline)
            ForEach(linkedSensors, id: \.entityId) { sensor in
                let state = sensorHistory[sensor.entityId] ?? SensorHistoryState()
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        if canShowSensorHistory {
                            toggleHistory(for: sensor)
                        }
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            Circle()
                                .fill(Color.accentColor.opacity(0.2))
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sensor.name)
                                    .font(.subheadline)
                                Text(formatSensorValue(sensor))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if canShowSensorHistory {
                                HStack(spacing: 6) {
                                    if state.loading {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                    }
                                    Text(state.expanded ? "Hide" : "History")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    if canShowSensorHistory, state.expanded {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                ForEach(HistoryBucket.allCases, id: \.self) { bucket in
                                    let selected = state.bucket == bucket
                                    Button(bucketLabel(bucket)) {
                                        changeBucket(for: sensor, bucket: bucket)
                                    }
                                    .font(.caption)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(selected ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemBackground))
                                    .cornerRadius(999)
                                }
                            }
                            historyContent(for: sensor, state: state)
                        }
                        .padding()
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(12)
                    }
                }
            }
        }
    }

    private func cameraURL(for entityId: String, ha: HaConnectionLike) -> URL? {
        let ts = cameraRefresh.timeIntervalSince1970
        guard let encodedEntity = entityId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        let urlString = "\(ha.baseUrl)/api/camera_proxy/\(encodedEntity)?ts=\(ts)"
        return URL(string: urlString)
    }

    // MARK: - Bearer-backed image loader (avoids tokens in query strings)

    private struct BearerImage: View {
        let url: URL
        let token: String
        let cacheBust: Date

        @State private var phase: Phase = .loading

        private enum Phase {
            case loading
            case success(Image)
            case failure
        }

        var body: some View {
            Group {
                switch phase {
                case .loading:
                    ProgressView()
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .clipped()
                case .failure:
                    Text("Unavailable")
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .background(Color(.tertiarySystemBackground))
                        .foregroundColor(.secondary)
                }
            }
            .task(id: cacheBust) {
                await load()
            }
        }

        private func load() async {
            guard let request = makeRequest() else {
                phase = .failure
                return
            }
            let config = URLSessionConfiguration.ephemeral
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            let session = URLSession(configuration: config)
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let image = UIImage(data: data) else {
                    phase = .failure
                    return
                }
                phase = .success(Image(uiImage: image))
            } catch {
                phase = .failure
            }
        }

        private func makeRequest() -> URLRequest? {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 5
            return request
        }
    }

    private func formatSensorValue(_ sensor: UIDevice) -> String {
        let state = sensor.state.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = sensor.attributes["unit_of_measurement"]?.anyValue as? String ?? ""
        if state.isEmpty { return "—" }
        if state.lowercased() == "unavailable" { return "Unavailable" }
        if !unit.isEmpty { return "\(state) \(unit)".trimmingCharacters(in: .whitespaces) }
        return state.prefix(1).uppercased() + state.dropFirst()
    }

    private func bucketLabel(_ bucket: HistoryBucket) -> String {
        switch bucket {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    private func ensureHistoryState(for sensor: UIDevice) {
        guard sensorHistory[sensor.entityId] == nil else { return }
        sensorHistory[sensor.entityId] = SensorHistoryState()
    }

    private func toggleHistory(for sensor: UIDevice) {
        ensureHistoryState(for: sensor)
        let id = sensor.entityId
        let isExpanding = !(sensorHistory[id]?.expanded ?? false)
        sensorHistory[id]?.expanded.toggle()
        if isExpanding && (sensorHistory[id]?.points == nil) {
            Task { await loadHistory(for: sensor, bucket: sensorHistory[id]?.bucket ?? .daily) }
        }
    }

    private func changeBucket(for sensor: UIDevice, bucket: HistoryBucket) {
        ensureHistoryState(for: sensor)
        let id = sensor.entityId
        sensorHistory[id]?.bucket = bucket
        Task { await loadHistory(for: sensor, bucket: bucket) }
    }

    @ViewBuilder
    private func historyContent(for sensor: UIDevice, state: SensorHistoryState) -> some View {
        if state.loading {
            ProgressView("Loading history…")
        } else if let error = state.error {
            Text(error)
                .foregroundColor(.secondary)
                .font(.caption)
        } else if let points = state.points, points.isEmpty {
            Text("No history yet.")
                .foregroundColor(.secondary)
                .font(.caption)
        } else if let points = state.points {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(points) { point in
                    HStack {
                        Text(point.label)
                            .font(.footnote)
                        Spacer()
                        Text("\(String(format: "%.2f", point.value))\(state.unit.map { " \($0)" } ?? "")")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    private func loadHistory(for sensor: UIDevice, bucket: HistoryBucket) async {
        guard canShowSensorHistory, session.user != nil else { return }
        ensureHistoryState(for: sensor)
        let id = sensor.entityId
        await MainActor.run {
            sensorHistory[id]?.loading = true
            sensorHistory[id]?.error = nil
        }
        do {
            let result = try await MonitoringHistoryService.fetchHistory(
                entityId: sensor.entityId,
                bucket: bucket,
                role: session.user?.role
            )
            await MainActor.run {
                sensorHistory[id]?.points = result.points
                sensorHistory[id]?.unit = result.unit
                sensorHistory[id]?.loading = false
                sensorHistory[id]?.error = nil
            }
        } catch {
            await MainActor.run {
                if error.isCancellation { return }
                sensorHistory[id]?.points = []
                sensorHistory[id]?.unit = nil
                sensorHistory[id]?.loading = false
                sensorHistory[id]?.error = MonitoringHistoryError.unableToLoad.errorDescription
            }
        }
    }

    private func send(_ command: DeviceCommand, value: Double? = nil) async {
        guard canControlDevices else {
            alertMessage = "Device control is available to tenants only."
            return
        }
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            if haMode == .cloud {
                try await DeviceControlService.sendCloudCommand(
                    entityId: device.entityId,
                    command: command.rawValue,
                    value: value
                )
            } else {
                guard let ha = session.connection(for: .home) else {
                    alertMessage = "We cannot find your Dinodia Hub on the home Wi‑Fi. Switch to Dinodia Cloud to control your place."
                    return
                }
                try await HACommandHandler.handle(
                    ha: ha,
                    entityId: device.entityId,
                    command: command,
                    value: value,
                    blindTravelSeconds: device.blindTravelSeconds
                )
            }
        } catch {
            if error.isCancellation { return }
            alertMessage = error.localizedDescription
        }
    }

    private func saveEdit() async {
        guard session.user?.role == .ADMIN else { return }
        isSavingEdit = true
        editError = nil
        defer { isSavingEdit = false }

        let trimmedName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            editError = "Name is required."
            return
        }

        var travelSeconds: Double? = nil
        let trimmedTravel = editTravel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTravel.isEmpty {
            if let parsed = Double(trimmedTravel), parsed > 0 {
                travelSeconds = parsed
            } else {
                editError = "Enter a positive number of seconds."
                return
            }
        }

        do {
            try await DeviceAdminService.updateDevice(
                entityId: device.entityId,
                name: trimmedName,
                blindTravelSeconds: getPrimaryLabel(for: device) == "Blind" ? travelSeconds : nil
            )
            showEditSheet = false
            onDeviceUpdated?()
        } catch {
            if error.isCancellation { return }
            editError = error.localizedDescription
        }
    }

}

private struct SensorHistoryState {
    var expanded: Bool = false
    var bucket: HistoryBucket = .daily
    var loading: Bool = false
    var error: String?
    var unit: String?
    var points: [HistoryPoint]?
}
