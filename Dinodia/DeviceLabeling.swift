import Foundation

enum LabelCategory: String {
    case light = "Light"
    case blind = "Blind"
    case tv = "TV"
    case speaker = "Speaker"
    case boiler = "Boiler"
    case sockets = "Sockets"
    case security = "Security"
    case spotify = "Spotify"
    case `switch` = "Switch"
    case thermostat = "Thermostat"
    case media = "Media"
    case motionSensor = "Motion Sensor"
    case sensor = "Sensor"
    case vacuum = "Vacuum"
    case camera = "Camera"
    case other = "Other"
}

let LABEL_ORDER: [String] = LabelRegistry.orderedLabels
let OTHER_LABEL = LabelRegistry.other

func normalizeLabel(_ value: String?) -> String {
    value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func classifyDeviceByLabel(_ labels: [String]) -> String? {
    for label in labels {
        if let canonical = LabelRegistry.canonical(from: label) {
            return canonical
        }
    }
    return nil
}

func getPrimaryLabel(for device: UIDevice) -> String {
    let override = normalizeLabel(device.label)
    if !override.isEmpty {
        return LabelRegistry.canonical(from: override) ?? override
    }
    if let labels = device.labels, let first = labels.first {
        let normalized = normalizeLabel(first)
        if !normalized.isEmpty {
            return LabelRegistry.canonical(from: normalized) ?? normalized
        }
    }
    if let category = LabelRegistry.canonical(from: device.labelCategory) {
        return category
    }
    return OTHER_LABEL
}

func getGroupLabel(for device: UIDevice) -> String {
    let label = getPrimaryLabel(for: device)
    return LabelRegistry.groupLabel(for: label)
}

func sortLabels(_ labels: [String]) -> [String] {
    LabelRegistry.sortLabels(labels)
}
