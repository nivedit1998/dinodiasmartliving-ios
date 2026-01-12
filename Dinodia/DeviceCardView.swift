import SwiftUI

struct DeviceCardView: View {
    @EnvironmentObject private var session: SessionStore
    let device: UIDevice
    let haMode: HaMode
    let onOpenDetails: () -> Void
    let onAfterCommand: () -> Void
    let showControls: Bool
    let kwhTotal: Double?
    let energyCost: Double?

    @State private var isSending = false
    @State private var pendingCommand: DeviceCommand?
    @State private var alertMessage: String?
    @State private var blindPositionValue: Double = 0

    var body: some View {
        let label = getPrimaryLabel(for: device)
        let allowControl = session.user?.role == .TENANT
        let preset = getDevicePreset(label: label)
        let active = isDeviceActive(label: label, device: device)
        let blindPosition = Double(blindPositionPercent(for: device) ?? 0)
        let backgroundStyle: AnyShapeStyle = {
            if active {
                return AnyShapeStyle(LinearGradient(colors: preset.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            } else {
                return AnyShapeStyle(preset.inactiveBackground)
            }
        }()
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(active ? .black : .gray)
                Spacer()
            }
            Text(device.name)
                .font(.headline)
                .foregroundColor(active ? .primary : .secondary)
            Text(secondaryText(for: device))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
            if let kwhTotal, kwhTotal.isFinite {
                Text("Energy (Total): \(String(format: "%.2f", kwhTotal)) kWh")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                if let energyCost, energyCost.isFinite {
                    Text("Cost:")
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Text("£\(String(format: "%.2f", energyCost))")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
            }
            if showControls {
                if label == "Boiler" {
                    boilerControls(active: active, accent: preset.iconActiveBackground, allowControl: allowControl)
                } else if label == "Blind" {
                    blindControls(active: active, accent: preset.iconActiveBackground, allowControl: allowControl)
                } else if let action = primaryAction(for: label, device: device) {
                    Button(action: { Task { await sendCommand(action) } }) {
                        HStack {
                            if isSending {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(primaryActionLabel(for: label, device: device))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .disabled(isSending || !allowControl)
                    .background(active ? preset.iconActiveBackground : Color.black)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(backgroundStyle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.black.opacity(0.05))
        )
        .onTapGesture { onOpenDetails() }
        .onAppear {
            if label == "Blind" {
                blindPositionValue = blindPosition
            }
        }
        .onChange(of: blindPosition) { _, newValue in
            guard label == "Blind", !isSending else { return }
            blindPositionValue = newValue
        }
        .alert("Dinodia", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func sendCommand(_ command: DeviceCommand, value: Double? = nil) async {
        guard session.user?.role == .TENANT else {
            alertMessage = "Device control is available to tenants only."
            return
        }
        guard !isSending else { return }
        isSending = true
        pendingCommand = command
        defer { isSending = false; pendingCommand = nil }
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
            await MainActor.run {
                onAfterCommand()
            }
        } catch {
            if error.isCancellation { return }
            alertMessage = error.localizedDescription
        }
    }

    private func boilerControls(active: Bool, accent: Color, allowControl: Bool) -> some View {
        let current = boilerSetpoint(from: device.attributes)
        return HStack(spacing: 8) {
            Button {
                Task { await sendCommand(.boilerTempDown) }
            } label: {
                HStack {
                    Image(systemName: "minus")
                    Text("Temp")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .disabled(isSending || !allowControl)
            .background(active ? accent : Color.black)
            .foregroundColor(.white)
            .cornerRadius(12)

            if let current {
                Text("\(Int(current))°")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .frame(minWidth: 44)
            }

            Button {
                Task { await sendCommand(.boilerTempUp) }
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Temp")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .disabled(isSending || !allowControl)
            .background(active ? accent : Color.black)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
    }

    private func blindControls(active: Bool, accent: Color, allowControl: Bool) -> some View {
        let state = device.state.lowercased()
        let isOpen = state == "open" || state == "opening" || state == "on"
        let showOpen = blindPositionValue <= 50 && !isOpen
        let actionCommand: DeviceCommand = showOpen ? .blindOpen : .blindClose
        return Button {
            Task { await sendCommand(actionCommand) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showOpen ? "arrow.up" : "arrow.down")
                Text(showOpen ? "Open" : "Close")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .disabled(isSending || !allowControl || (showOpen ? isOpen : (!isOpen && state != "closing")))
        .background(active ? accent : Color.black)
        .foregroundColor(.white)
        .cornerRadius(12)
    }
}
