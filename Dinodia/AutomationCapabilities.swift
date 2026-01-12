import Foundation

enum AutomationActionKind {
    case button
    case fixed
    case slider
}

struct AutomationActionSpec: Identifiable {
    let id: String
    let label: String
    let kind: AutomationActionKind
    let command: DeviceCommand
    let value: Double?
    let min: Double?
    let max: Double?
    let step: Double?
}

enum AutomationTriggerKind {
    case state
    case attributeDelta
    case position
}

struct AutomationTriggerSpec: Identifiable {
    let id: String
    let label: String
    let kind: AutomationTriggerKind
    let entityState: String?
    let attribute: String?
    let direction: String?
    let equals: Double?
    let attributes: [String]?
}

struct AutomationCapability {
    let actions: [AutomationActionSpec]
    let triggers: [AutomationTriggerSpec]
    let excludeFromAutomations: Bool
}

enum AutomationCapabilities {
    static func actions(for device: UIDevice) -> [AutomationActionSpec] {
        let label = getPrimaryLabel(for: device)
        return capability(for: label)?.actions ?? []
    }

    static func triggers(for device: UIDevice) -> [AutomationTriggerSpec] {
        let label = getPrimaryLabel(for: device)
        return capability(for: label)?.triggers ?? []
    }

    static func eligibleDevices(_ devices: [UIDevice]) -> [UIDevice] {
        devices.filter { device in
            guard isPrimaryDevice(device) else { return false }
            let label = getPrimaryLabel(for: device)
            guard let caps = capability(for: label), !caps.excludeFromAutomations else { return false }
            return !caps.actions.isEmpty || !caps.triggers.isEmpty
        }
    }

    private static func capability(for label: String) -> AutomationCapability? {
        switch label {
        case "Light":
            return AutomationCapability(
                actions: [
                    AutomationActionSpec(id: "light-on", label: "Turn on", kind: .button, command: .lightTurnOn, value: nil, min: nil, max: nil, step: nil),
                    AutomationActionSpec(id: "light-off", label: "Turn off", kind: .button, command: .lightTurnOff, value: nil, min: nil, max: nil, step: nil),
                    AutomationActionSpec(id: "light-brightness", label: "Brightness", kind: .slider, command: .lightSetBrightness, value: nil, min: 0, max: 100, step: 1),
                ],
                triggers: [
                    AutomationTriggerSpec(id: "light-on", label: "Turns on", kind: .state, entityState: "on", attribute: nil, direction: nil, equals: nil, attributes: nil),
                    AutomationTriggerSpec(id: "light-off", label: "Turns off", kind: .state, entityState: "off", attribute: nil, direction: nil, equals: nil, attributes: nil),
                    AutomationTriggerSpec(id: "brightness-increase", label: "Brightness increases", kind: .attributeDelta, entityState: nil, attribute: "brightness", direction: "increase", equals: nil, attributes: nil),
                    AutomationTriggerSpec(id: "brightness-decrease", label: "Brightness decreases", kind: .attributeDelta, entityState: nil, attribute: "brightness", direction: "decrease", equals: nil, attributes: nil),
                ],
                excludeFromAutomations: false
            )
        case "Blind":
            return AutomationCapability(
                actions: [
                    AutomationActionSpec(id: "blind-open", label: "Open", kind: .fixed, command: .blindOpen, value: 100, min: nil, max: nil, step: nil),
                    AutomationActionSpec(id: "blind-close", label: "Close", kind: .fixed, command: .blindClose, value: 0, min: nil, max: nil, step: nil),
                ],
                triggers: [
                    AutomationTriggerSpec(id: "blind-opened", label: "Opened", kind: .position, entityState: nil, attribute: nil, direction: nil, equals: 100, attributes: ["current_position", "position"]),
                    AutomationTriggerSpec(id: "blind-closed", label: "Closed", kind: .position, entityState: nil, attribute: nil, direction: nil, equals: 0, attributes: ["current_position", "position"]),
                ],
                excludeFromAutomations: false
            )
        case "TV":
            return AutomationCapability(
                actions: [
                    AutomationActionSpec(id: "tv-on", label: "Turn on", kind: .button, command: .tvTurnOn, value: nil, min: nil, max: nil, step: nil),
                    AutomationActionSpec(id: "tv-off", label: "Turn off", kind: .button, command: .tvTurnOff, value: nil, min: nil, max: nil, step: nil),
                    AutomationActionSpec(id: "tv-volume", label: "Volume", kind: .slider, command: .mediaVolumeSet, value: nil, min: 0, max: 100, step: 1),
                ],
                triggers: [
                    AutomationTriggerSpec(id: "tv-on", label: "Turns on", kind: .state, entityState: "on", attribute: nil, direction: nil, equals: nil, attributes: nil),
                    AutomationTriggerSpec(id: "tv-off", label: "Turns off", kind: .state, entityState: "off", attribute: nil, direction: nil, equals: nil, attributes: nil),
                ],
                excludeFromAutomations: false
            )
        case "Speaker":
            return AutomationCapability(
                actions: [
                    AutomationActionSpec(id: "speaker-on", label: "Turn on", kind: .button, command: .speakerTurnOn, value: nil, min: nil, max: nil, step: nil),
                    AutomationActionSpec(id: "speaker-off", label: "Turn off", kind: .button, command: .speakerTurnOff, value: nil, min: nil, max: nil, step: nil),
                    AutomationActionSpec(id: "speaker-volume", label: "Volume", kind: .slider, command: .mediaVolumeSet, value: nil, min: 0, max: 100, step: 1),
                ],
                triggers: [
                    AutomationTriggerSpec(id: "speaker-on", label: "Turns on", kind: .state, entityState: "on", attribute: nil, direction: nil, equals: nil, attributes: nil),
                    AutomationTriggerSpec(id: "speaker-off", label: "Turns off", kind: .state, entityState: "off", attribute: nil, direction: nil, equals: nil, attributes: nil),
                ],
                excludeFromAutomations: false
            )
        case "Boiler":
            return AutomationCapability(
                actions: [
                    AutomationActionSpec(id: "boiler-set-temp", label: "Set temperature", kind: .slider, command: .boilerSetTemperature, value: nil, min: 10, max: 35, step: 1),
                ],
                triggers: [
                    AutomationTriggerSpec(id: "boiler-temp-increase", label: "Temperature increases", kind: .attributeDelta, entityState: nil, attribute: "current_temperature", direction: "increase", equals: nil, attributes: nil),
                    AutomationTriggerSpec(id: "boiler-temp-decrease", label: "Temperature decreases", kind: .attributeDelta, entityState: nil, attribute: "current_temperature", direction: "decrease", equals: nil, attributes: nil),
                ],
                excludeFromAutomations: false
            )
        case "Spotify":
            return AutomationCapability(actions: [], triggers: [], excludeFromAutomations: true)
        default:
            return nil
        }
    }
}
