import SwiftUI

struct ManageDevicesView: View {
    @StateObject private var store = ManageDevicesStore()
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        List {
            hero

            if let error = store.errorMessage {
                NoticeView(kind: .error, message: error)
            }

            if store.isLoading && store.devices.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading devices…")
                        .foregroundColor(.secondary)
                }
            }

            if !store.isLoading && store.devices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No devices yet")
                        .font(.headline)
                    Text("Add a device by signing in from that phone or tablet.")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
                .padding(.vertical, 8)
            }

            Section("Devices") {
                ForEach(store.devices) { device in
                    deviceCard(device)
                }
            }
        }
        .navigationTitle("Manage Devices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                ModeSwitchPrompt(
                    targetMode: session.haMode == .home ? .cloud : .home,
                    userId: session.user?.id,
                    onSwitched: { Task { await store.loadIfNeeded() } }
                )
                .environmentObject(session)
            }
            ToolbarItem(placement: .principal) {
                DinodiaNavBarLogo()
            }
        }
        .refreshable {
            await store.load()
            
        }
        .task {
            await store.loadIfNeeded()
            await session.updateHomeNetworkStatus()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Block stolen or lost devices instantly. Active devices can fetch hub secrets; stolen ones are locked out.")
                .foregroundColor(.secondary)
                .font(.subheadline)
            if session.haMode == .home {
                homeNetworkBadge
            } else {
                cloudBadge
            }
        }
        .padding(.vertical, 4)
    }

    private var homeNetworkBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: session.onHomeNetwork ? "wifi" : "wifi.slash")
                .foregroundColor(session.onHomeNetwork ? .green : .orange)
            Text(session.onHomeNetwork ? "On Home Network" : "Not on Home Network")
                .font(.caption2)
                .foregroundColor(.secondary)
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

    private func deviceCard(_ device: ManagedDevice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor(device.status))
                        .frame(width: 10, height: 10)
                    Text(displayName(device))
                        .font(.headline)
                }
                Spacer()
                Text(statusLabel(device.status))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text("ID: \(device.deviceId)")
                .font(.caption)
                .foregroundColor(.secondary)

            infoRow(label: "First seen", value: format(dateString: device.firstSeenAt))
            infoRow(label: "Last seen", value: format(dateString: device.lastSeenAt))
            if let revoked = device.revokedAt, !revoked.isEmpty {
                infoRow(label: "Revoked", value: format(dateString: revoked))
            }

            if device.status == .active {
                Button {
                    Task { await store.markStolen(deviceId: device.deviceId) }
                } label: {
                    Text(store.savingId == device.deviceId ? "Updating…" : "Mark as stolen")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(store.savingId != nil)
            } else {
                Button {
                    Task { await store.restore(deviceId: device.deviceId) }
                } label: {
                    Text(store.savingId == device.deviceId ? "Updating…" : "Restore device")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(store.savingId != nil)
            }
        }
        .padding(.vertical, 6)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
        }
    }

    private func displayName(_ device: ManagedDevice) -> String {
        if let label = device.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label
        }
        if let registry = device.registryLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !registry.isEmpty {
            return registry
        }
        let suffix = device.deviceId.suffix(6)
        return "Device \(suffix)"
    }

    private func statusLabel(_ status: ManagedDeviceStatus) -> String {
        switch status {
        case .active: return "Active"
        case .stolen: return "Stolen"
        case .blocked: return "Blocked"
        }
    }

    private func statusColor(_ status: ManagedDeviceStatus) -> Color {
        switch status {
        case .active: return .green
        case .stolen: return .red
        case .blocked: return .orange
        }
    }

    private func format(dateString: String?) -> String {
        guard let raw = dateString, !raw.isEmpty else { return "—" }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) {
            return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        if let date = formatter.date(from: raw) {
            return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        }
        return raw
    }

}
