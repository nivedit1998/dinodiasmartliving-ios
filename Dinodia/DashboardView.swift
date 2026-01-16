import SwiftUI

private let allAreasKey = "ALL"
private let allAreasLabel = "All Areas"
private let sensorNameSuffixes = [
    "temperature",
    "humidity",
    "power",
    "voltage",
    "current",
    "illuminance",
    "pressure",
    "energy",
    "battery",
    "battery level",
    "consumption",
    "status",
]

struct DashboardView: View {
    @EnvironmentObject private var session: SessionStore
    let role: Role

    var body: some View {
        if let user = session.user {
            DashboardContentView(userId: user.id, role: role, haMode: session.haMode)
                .id("\(user.id)-\(session.haMode.rawValue)")
        } else {
            ProgressView()
        }
    }
}

private struct DashboardContentView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: TabRouter
    @StateObject private var store: DeviceStore

    let role: Role
    let userId: Int
    let haMode: HaMode

    @State private var selectedDevice: UIDevice?
    @State private var selectedArea: String = allAreasKey
    @State private var showAreaSheet = false
    @State private var areaPrefLoaded = false
    @State private var remoteStatus: RemoteAccessStatus = .checking
    @State private var alertMessage: String?
    @State private var kwhBaselines: [String: Double] = [:]
    @State private var pricePerKwh: Double? = nil

    init(userId: Int, role: Role, haMode: HaMode) {
        _store = StateObject(wrappedValue: DeviceStore(userId: userId, mode: haMode))
        self.userId = userId
        self.role = role
        self.haMode = haMode
    }

    var body: some View {
        GeometryReader { proxy in
            dashboardContent(proxy: proxy)
        }
    }

    private func dashboardContent(proxy: GeometryProxy) -> some View {
        let maxColumns = adaptiveColumns(width: proxy.size.width, height: proxy.size.height)
        let horizontalPadding: CGFloat = 16
        let availableWidth = proxy.size.width - (horizontalPadding * 2)

        let base = ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let error = store.errorMessage, store.devices.isEmpty {
                    NoticeView(kind: .error, message: error)
                }
                deviceGrid(maxColumns: maxColumns, availableWidth: availableWidth)
                if role == .TENANT {
                    spotifyCard
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())

        return base
            .refreshable {
                await store.refresh(background: false)
                await refreshKwhBaselinesIfNeeded()
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { dashboardToolbar }
            .sheet(item: $selectedDevice, content: deviceSheet)
            .onChange(of: session.user?.id) { _, newValue in
                handleUserChange(newValue)
            }
            .onAppear { loadAreaPreference() }
            .onChange(of: selectedArea) { _, newValue in
                saveAreaPreference(value: newValue)
            }
            .onChange(of: store.devices.map(\.entityId)) { _, _ in
                Task { await refreshKwhBaselinesIfNeeded() }
            }
            .onChange(of: store.lastUpdated) { _, _ in
                Task { await refreshKwhBaselinesIfNeeded() }
            }
            .onAppear {
                Task { await refreshRemoteStatus() }
                Task { await refreshKwhBaselinesIfNeeded() }
            }
            .alert("Dinodia", isPresented: isAlertPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .overlay { hubOverlay }
    }

    @ToolbarContentBuilder
    private var dashboardToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) { modePill }
        ToolbarItem(placement: .principal) { DinodiaNavBarLogo() }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button("Logout", role: .destructive) { session.logout() }
        }
    }

    private var isAlertPresented: Binding<Bool> {
        Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })
    }

    @ViewBuilder
    private func deviceSheet(device: UIDevice) -> some View {
        let sensors = linkedSensors(for: device)
        DeviceDetailSheet(
            device: device,
            haMode: haMode,
            linkedSensors: sensors,
            relatedDevices: relatedDevices(for: device),
            allowSensorHistory: (session.user?.role == .ADMIN) && !sensors.isEmpty,
            showControls: role == .TENANT,
            showStateText: role == .TENANT,
            onDeviceUpdated: {
                Task { await store.refresh(background: false) }
            }
        )
        .environmentObject(session)
        .environmentObject(router)
    }

    private func handleUserChange(_ newValue: Int?) {
        if newValue == nil {
            selectedDevice = nil
            alertMessage = nil
        }
    }

    @ViewBuilder
    private var hubOverlay: some View {
        if haMode == .home && session.isConfiguringHub {
            VStack(spacing: 12) {
                ProgressView()
                Text("Configuring your Dinodia Hub")
                    .font(.headline)
                if let err = session.hubConfiguringError {
                    Text(err).font(.footnote).multilineTextAlignment(.center)
                    HStack {
                        Button("Retry") {
                            Task { await session.ensureHomeModeSecretsReady() }
                        }
                        Button("Logout", role: .destructive) {
                            session.logout()
                        }
                    }
                } else {
                    Text("This can take a few minutes while your hub finishes syncing.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.35))
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button {
                    showAreaSheet = true
                } label: {
                    HStack {
                        Text(selectedArea == allAreasKey ? allAreasLabel : selectedArea)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.down")
                            .font(.subheadline)
                    }
                }
                Spacer()
                wifiStatus
            }
            if haMode == .cloud && remoteStatus == .locked {
                Text("Cloud access locked. Finish remote access setup.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            if store.isRefreshing {
                Text("Refreshing…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let last = store.lastUpdated {
                Text("Updated \(relativeDescription(for: last))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .confirmationDialog("Select area", isPresented: $showAreaSheet) {
            Button(allAreasLabel) { selectedArea = allAreasKey }
            ForEach(areaOptions, id: \.self) { area in
                Button(area) { selectedArea = area }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var wifiStatus: some View {
        Group {
            if haMode == .home {
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
            targetMode: haMode == .home ? .cloud : .home,
            userId: userId,
            onSwitched: { Task { await store.refresh(background: true) } }
        )
        .environmentObject(session)
    }

    private var filteredDevices: [UIDevice] {
        store.devices.filter { device in
            let areaName = (device.areaName ?? device.area)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !areaName.isEmpty else { return false }
            if selectedArea != allAreasKey, areaName != selectedArea { return false }
            guard isPrimaryDevice(device) else { return false }
            let hasLabel = !normalizeLabel(device.label).isEmpty
                || !(device.labels ?? []).isEmpty
                || LabelRegistry.canonical(from: device.labelCategory) != nil
            return hasLabel
        }
    }

    private func deviceGrid(maxColumns: Int, availableWidth: CGFloat) -> some View {
        let sections = buildDeviceSections(filteredDevices)
        let rows = buildSectionLayoutRows(sections, maxColumns: maxColumns)
        let spacing: CGFloat = 12
        let unitWidth = (availableWidth - spacing * CGFloat(maxColumns - 1)) / CGFloat(maxColumns)
        return VStack(spacing: 16) {
            if rows.isEmpty {
                Text(store.isRefreshing ? "Loading devices…" : "No devices available.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(row.sections) { section in
                            let width = unitWidth * CGFloat(section.span) + spacing * CGFloat(section.span - 1)
                            sectionView(section, maxColumns: maxColumns)
                                .frame(width: width, alignment: .topLeading)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: LayoutSection, maxColumns: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            if section.title == "Boiler" {
                let columns = max(1, section.span / 2)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 12) {
                    ForEach(section.devices, id: \.entityId) { device in
                        DeviceCardView(
                            device: device,
                            haMode: haMode,
                            onOpenDetails: { selectedDevice = device },
                            onAfterCommand: { Task { await store.refresh(background: true) } },
                            showControls: role == .TENANT,
                            kwhTotal: kwhTotalForDevice(device),
                            energyCost: energyCostForDevice(device)
                        )
                        .environmentObject(session)
                    }
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: min(section.span, maxColumns)), spacing: 12) {
                    ForEach(section.devices, id: \.entityId) { device in
                        DeviceCardView(
                            device: device,
                            haMode: haMode,
                            onOpenDetails: { selectedDevice = device },
                            onAfterCommand: { Task { await store.refresh(background: true) } },
                            showControls: role == .TENANT,
                            kwhTotal: kwhTotalForDevice(device),
                            energyCost: energyCostForDevice(device)
                        )
                        .environmentObject(session)
                    }
                }
            }
        }
    }

    private var spotifyCard: some View {
        SpotifyCardView()
    }

    private func adaptiveColumns(width: CGFloat, height: CGFloat) -> Int {
        let spacing: CGFloat = 12
        let minCardWidth: CGFloat = 170
        let maxColsAllowed = 4
        let calculated = Int((width + spacing) / (minCardWidth + spacing))
        return max(2, min(maxColsAllowed, calculated))
    }

    private var areaOptions: [String] {
        let names = Set(store.devices.compactMap { ($0.area ?? $0.areaName)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        return names.sorted()
    }

    private func refreshKwhBaselinesIfNeeded() async {
        guard role == .ADMIN else {
            await MainActor.run {
                kwhBaselines = [:]
                pricePerKwh = nil
            }
            return
        }
        let pairs = store.devices.compactMap { device -> (String, String)? in
            guard !isSensorDevice(device) else { return nil }
            guard let sensorId = kwhSensorId(for: device) else { return nil }
            return (device.entityId, sensorId)
        }
        let sensorIds = Array(Set(pairs.map { $0.1 }))
        if sensorIds.isEmpty {
            await MainActor.run {
                kwhBaselines = [:]
                pricePerKwh = nil
            }
            return
        }
        do {
            let result = try await MonitoringKwhTotalsService.fetchBaselines(entityIds: sensorIds)
            await MainActor.run {
                kwhBaselines = result.baselines
                pricePerKwh = result.pricePerKwh
            }
        } catch {
            await MainActor.run {
                kwhBaselines = [:]
                pricePerKwh = nil
            }
        }
    }

    private func loadAreaPreference() {
        guard role == .TENANT else { return }
        let key = "tenant_selected_area_\(userId)"
        if let stored = UserDefaults.standard.string(forKey: key), !stored.isEmpty {
            selectedArea = stored
        }
        areaPrefLoaded = true
    }

    private func saveAreaPreference(value: String) {
        guard role == .TENANT, areaPrefLoaded else { return }
        let key = "tenant_selected_area_\(userId)"
        UserDefaults.standard.set(value, forKey: key)
    }


    private func relativeDescription(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func linkedSensors(for device: UIDevice) -> [UIDevice] {
        guard let groupId = groupingId(for: device) else { return [] }
        return store.devices.filter {
            groupingId(for: $0) == groupId && $0.entityId != device.entityId && isSensorDevice($0)
        }
    }

    private func kwhSensorId(for device: UIDevice) -> String? {
        let sensors = linkedSensors(for: device)
        return sensors.first(where: { ($0.attributes["unit_of_measurement"]?.anyValue as? String) == "kWh" })?.entityId
    }

    private func kwhTotalForDevice(_ device: UIDevice) -> Double? {
        guard role == .ADMIN else { return nil }
        guard let sensorId = kwhSensorId(for: device) else { return nil }
        let baseline = kwhBaselines[sensorId]
        let current = currentKwhForSensor(sensorId)
        guard let base = baseline, let curr = current else { return nil }
        let delta = curr - base
        return delta > 0 ? delta : 0
    }

    private func energyCostForDevice(_ device: UIDevice) -> Double? {
        guard role == .ADMIN else { return nil }
        guard let price = pricePerKwh, price.isFinite, price >= 0 else { return nil }
        guard let usage = kwhTotalForDevice(device) else { return nil }
        let cost = usage * price
        return cost.isFinite ? cost : nil
    }

    private func currentKwhForSensor(_ sensorId: String) -> Double? {
        guard let sensor = store.devices.first(where: { $0.entityId == sensorId }) else { return nil }
        let val = Double(sensor.state)
        if let val, val.isFinite { return val }
        return nil
    }

    private func relatedDevices(for device: UIDevice) -> [UIDevice]? {
        let label = getPrimaryLabel(for: device)
        if label == "Home Security" {
            return store.devices.filter { getPrimaryLabel(for: $0) == "Home Security" }
        }
        return nil
    }

    private func refreshRemoteStatus() async {
        remoteStatus = .checking
        remoteStatus = await RemoteAccessService.checkRemoteAccessEnabled() ? .enabled : .locked
    }

}

private func groupingId(for device: UIDevice) -> String? {
    if let id = device.deviceId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
        return id
    }
    return buildFallbackDeviceId(
        entityId: device.entityId,
        name: device.name,
        areaName: device.area ?? device.areaName
    )
}

private func buildFallbackDeviceId(entityId: String, name: String?, areaName: String?) -> String? {
    let area = normalizeKey(areaName ?? "")
    guard !area.isEmpty else { return nil }
    let areaKey = area.replacingOccurrences(of: "\\s+", with: "_", options: .regularExpression)
    let objectId = entityId.split(separator: ".").dropFirst().first.map(String.init) ?? entityId
    let baseName = normalizeKey(name ?? objectId)
    guard !baseName.isEmpty else { return nil }
    let core = stripSensorSuffix(from: baseName)
    guard !core.isEmpty else { return nil }
    let coreKey = core.replacingOccurrences(of: "\\s+", with: "_", options: .regularExpression)
    return "fallback:\(areaKey):\(coreKey)"
}

private func stripSensorSuffix(from value: String) -> String {
    for suffix in sensorNameSuffixes {
        let pattern = "\\\\b\(suffix)$"
        if value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            let trimmed = value.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
    }
    return value
}

private func normalizeKey(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}


extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        var result: [[Element]] = []
        var index = startIndex
        while index < endIndex {
            let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[index..<end]))
            index = end
        }
        return result
    }
}
