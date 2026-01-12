import Foundation

func isDetailDevice(state: String) -> Bool {
    let trimmed = state.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return false }
    if trimmed.lowercased() == "unavailable" { return true }
    return Double(trimmed) != nil
}

func isSensorDevice(_ device: UIDevice) -> Bool {
    let label = getPrimaryLabel(for: device)
    if LabelRegistry.isSensor(label: label) { return true }
    if isDetailDevice(state: device.state) { return true }
    return false
}

func isPrimaryDevice(_ device: UIDevice) -> Bool {
    let label = getPrimaryLabel(for: device)
    // Only show devices with kiosk-approved primary labels.
    guard LabelRegistry.isPrimary(label: label) else { return false }
    // Motion sensors should appear on the dashboard even though they are sensors.
    if label == "Motion Sensor" {
        return !isDetailDevice(state: device.state)
    }
    if isSensorDevice(device) { return false }
    if LabelRegistry.isDetailOnly(label: label) { return false }
    return !isDetailDevice(state: device.state)
}
