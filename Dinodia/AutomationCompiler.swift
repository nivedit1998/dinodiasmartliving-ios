import Foundation

struct HaTrigger: Codable {
    let platform: String
    let entity_id: String?
    let to: String?
    let from: String?
    let attribute: String?
    let above: Double?
    let below: Double?
    let at: String?
    let weekday: [String]?
}

struct HaAction: Codable {
    let service: String
    let target: [String: [String]]?
    let data: [String: CodableValue]?
}

struct HaCondition: Codable {
    let condition: String
    let weekday: [String]?
    let after: String?
    let before: String?
    let value_template: String?
}

struct HaAutomationConfig: Codable {
    let id: String?
    let alias: String
    let description: String
    let trigger: [HaTrigger]
    let action: [HaAction]
    let mode: String?
    let condition: [HaCondition]?
}

@MainActor
enum AutomationCompiler {
    static func compile(_ draft: AutomationDraft) -> HaAutomationConfig {
        let triggers = draft.triggers.map(compileTrigger)
        let actions = draft.actions.compactMap { compileAction($0) }

        var conditions: [HaCondition] = []
        let hasDays = (draft.daysOfWeek?.isEmpty == false)
        let at = (draft.triggerTime ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if hasDays || !at.isEmpty {
            var condition = HaCondition(condition: "time", weekday: draft.daysOfWeek, after: nil, before: nil, value_template: nil)
            if !at.isEmpty {
                let parts = at.split(separator: ":")
                if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) {
                    let after = String(format: "%02d:%02d", h, m)
                    let minutes = h * 60 + m
                    let next = (minutes + 1) % (24 * 60)
                    let nextH = next / 60
                    let nextM = next % 60
                    let before = String(format: "%02d:%02d", nextH, nextM)
                    condition = HaCondition(condition: "time", weekday: draft.daysOfWeek, after: after, before: before, value_template: nil)
                }
            }
            conditions.append(condition)
        }

        for trigger in draft.triggers {
            if let deltaCondition = templateCondition(for: trigger) {
                conditions.append(deltaCondition)
            }
        }

        return HaAutomationConfig(
            id: draft.id,
            alias: draft.alias,
            description: draft.description ?? "",
            trigger: triggers,
            action: actions,
            mode: draft.mode?.rawValue ?? "single",
            condition: conditions.isEmpty ? nil : conditions
        )
    }

    private static func compileTrigger(_ trigger: AutomationTrigger) -> HaTrigger {
        switch trigger {
        case .state(let t):
            return HaTrigger(
                platform: "state",
                entity_id: t.entityId,
                to: t.to ?? nil,
                from: t.from ?? nil,
                attribute: nil,
                above: nil,
                below: nil,
                at: nil,
                weekday: nil
            )
        case .numericDelta(let t):
            return HaTrigger(
                platform: "state",
                entity_id: t.entityId,
                to: nil,
                from: nil,
                attribute: t.attribute,
                above: nil,
                below: nil,
                at: nil,
                weekday: nil
            )
        case .position(let t):
            return HaTrigger(
                platform: "numeric_state",
                entity_id: t.entityId,
                to: nil,
                from: nil,
                attribute: t.attribute,
                above: t.value - 0.01,
                below: t.value + 0.01,
                at: nil,
                weekday: nil
            )
        case .time(let t):
            return HaTrigger(
                platform: "time",
                entity_id: nil,
                to: nil,
                from: nil,
                attribute: nil,
                above: nil,
                below: nil,
                at: t.at,
                weekday: t.daysOfWeek
            )
        }
    }

    private static func templateCondition(for trigger: AutomationTrigger) -> HaCondition? {
        guard case .numericDelta(let t) = trigger else { return nil }
        let rawAttr = t.attribute.trimmingCharacters(in: .whitespacesAndNewlines)
        let attribute = rawAttr.isEmpty ? "state" : rawAttr
        let threshold: Double = attribute.lowercased().contains("temp") ? 1.0 : 0.01
        let path = attribute == "state" ? "state" : "attributes['\(attribute)']"
        let toValue = "(trigger.to_state.\(path) | float(0))"
        let fromValue = "(trigger.from_state.\(path) | float(0))"
        let isDecrease = t.direction.lowercased() == "decrease"
        let expr = isDecrease
            ? "{{ (\(fromValue) - \(toValue)) >= \(threshold) }}"
            : "{{ (\(toValue) - \(fromValue)) >= \(threshold) }}"
        return HaCondition(condition: "template", weekday: nil, after: nil, before: nil, value_template: expr)
    }

    private static func compileAction(_ action: AutomationAction) -> HaAction? {
        guard case .device(let deviceAction) = action else { return nil }
        let entityId = deviceAction.entityId
        let domain = entityId.split(separator: ".").first.map(String.init) ?? ""
        guard let mapping = mapCommandToService(command: deviceAction.command, value: deviceAction.value, domain: domain) else {
            return nil
        }
        let target: [String: [String]] = ["entity_id": [entityId]]
        let data = mapping.data.map { dict -> [String: CodableValue] in
            var result: [String: CodableValue] = [:]
            for (k, v) in dict {
                if let num = v as? Double {
                    result[k] = .double(num)
                } else if let intVal = v as? Int {
                    result[k] = .int(intVal)
                } else if let boolVal = v as? Bool {
                    result[k] = .bool(boolVal)
                } else if let str = v as? String {
                    result[k] = .string(str)
                }
            }
            return result
        }
        return HaAction(service: mapping.service, target: target, data: data)
    }

    private static func mapCommandToService(command: DeviceCommand, value: Double?, domain: String) -> (service: String, data: [String: Any]?)? {
        let lowerDomain = domain.lowercased()
        switch command {
        case .lightToggle:
            return lowerDomain == "light" ? ("light.turn_on", nil) : ("homeassistant.toggle", nil)
        case .lightTurnOn:
            return lowerDomain == "light" ? ("light.turn_on", nil) : ("homeassistant.turn_on", nil)
        case .lightTurnOff:
            return lowerDomain == "light" ? ("light.turn_off", nil) : ("homeassistant.turn_off", nil)
        case .lightSetBrightness:
            let pct = clamp(value ?? 0, min: 0, max: 100)
            if lowerDomain == "light" {
                return ("light.turn_on", ["brightness_pct": pct])
            }
            return ("homeassistant.turn_on", nil)
        case .blindOpen:
            return ("cover.set_cover_position", ["position": 100])
        case .blindClose:
            return ("cover.set_cover_position", ["position": 0])
        case .blindSetPosition:
            return ("cover.set_cover_position", ["position": clamp(value ?? 0, min: 0, max: 100)])
        case .mediaPlayPause:
            return ("media_player.media_play_pause", nil)
        case .mediaNext:
            return ("media_player.media_next_track", nil)
        case .mediaPrevious:
            return ("media_player.media_previous_track", nil)
        case .mediaVolumeUp:
            return ("media_player.volume_up", nil)
        case .mediaVolumeDown:
            return ("media_player.volume_down", nil)
        case .mediaVolumeSet:
            let pct = clamp((value ?? 0) / 100, min: 0, max: 1)
            return ("media_player.volume_set", ["volume_level": pct])
        case .boilerTempUp, .boilerTempDown:
            return nil // do not compile convenience dashboard taps into automations
        case .boilerSetTemperature:
            let targetTemp = value ?? 20
            return lowerDomain == "climate"
                ? ("climate.set_temperature", ["temperature": targetTemp])
                : ("homeassistant.turn_on", ["temperature": targetTemp])
        case .tvTogglePower, .speakerTogglePower:
            return ("media_player.toggle", nil)
        case .tvTurnOn, .speakerTurnOn:
            return ("media_player.turn_on", nil)
        case .tvTurnOff, .speakerTurnOff:
            return ("media_player.turn_off", nil)
        }
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        return Swift.max(min, Swift.min(max, value))
    }
}
