import Foundation

enum AutomationMode: String {
    case single
    case restart
    case queued
    case parallel
}

struct StateTrigger {
    let entityId: String
    let to: String?
    let from: String?
}

struct NumericDeltaTrigger {
    let entityId: String
    let attribute: String
    let direction: String // "increase" | "decrease"
}

struct PositionTrigger {
    let entityId: String
    let attribute: String
    let value: Double
}

struct TimeTrigger {
    let at: String // HH:mm
    let daysOfWeek: [String]?
}

enum AutomationTrigger {
    case state(StateTrigger)
    case numericDelta(NumericDeltaTrigger)
    case position(PositionTrigger)
    case time(TimeTrigger)
}

struct DeviceAction {
    let entityId: String
    let command: DeviceCommand
    let value: Double?
}

enum AutomationAction {
    case device(DeviceAction)
}

struct AutomationDraft {
    var id: String?
    var alias: String
    var description: String?
    var mode: AutomationMode?
    var triggers: [AutomationTrigger]
    var actions: [AutomationAction]
    var daysOfWeek: [String]?
    var triggerTime: String?
}
