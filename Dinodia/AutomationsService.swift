import Foundation

struct AutomationSummary {
    let id: String
    let alias: String
    let description: String
    let enabled: Bool
    let basicSummary: String?
    let triggerSummary: String?
    let actionSummary: String?
    let hasDeviceAction: Bool?
    let draft: AutomationDraft?
    let entities: [String]?
    let targetDeviceIds: [String]?
    let hasTemplates: Bool?
    let canEdit: Bool?
    let mode: String?
    let raw: Any?
}

enum AutomationsServiceError: LocalizedError {
    case notConfigured
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Dinodia Hub connection is not configured."
        case .server(let msg):
            return msg
        }
    }
}

enum AutomationsService {
    struct PlatformResponse<T: Decodable>: Decodable {
        let ok: Bool?
        let automations: [T]?
        let id: String?
        let error: String?
    }

    private struct HaConn {
        let baseUrl: String
        let token: String
    }

    // MARK: - Draft extraction (for editing)

    static func draftFromSummary(_ automation: AutomationSummary) -> AutomationDraft? {
        if let draft = automation.draft {
            return draft
        }
        guard let raw = automation.raw else { return nil }
        if let dict = raw as? [String: Any] {
            return draft(from: dict, id: automation.id, aliasFallback: automation.alias, descriptionFallback: automation.description, modeFallback: automation.mode)
        }
        if let wrapper = raw as? AnyCodable, let dict = wrapper.value as? [String: Any] {
            return draft(from: dict, id: automation.id, aliasFallback: automation.alias, descriptionFallback: automation.description, modeFallback: automation.mode)
        }
        return nil
    }

    private static func draft(from dict: [String: Any], id: String, aliasFallback: String, descriptionFallback: String, modeFallback: String?) -> AutomationDraft? {
        let alias = (dict["alias"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = (dict["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let modeString = (dict["mode"] as? String) ?? modeFallback ?? "single"
        let draftMode = AutomationMode(rawValue: modeString) ?? .single

        var triggers: [AutomationTrigger] = []
        var daysOfWeek: [String]? = nil
        var triggerTime: String? = nil

        let triggerField = dict["trigger"] ?? dict["triggers"] ?? dict["Trigger"]
        let triggerList: [Any] = {
            if let arr = triggerField as? [Any] { return arr }
            if let single = triggerField { return [single] }
            return []
        }()
        if let firstTrigger = triggerList.first, let parsed = parseTrigger(firstTrigger) {
            triggers.append(parsed.trigger)
            daysOfWeek = parsed.days ?? daysOfWeek
            triggerTime = parsed.time ?? triggerTime
        }

        let actionField = dict["action"] ?? dict["actions"] ?? dict["Action"]
        let actionList: [Any] = {
            if let arr = actionField as? [Any] { return arr }
            if let single = actionField { return [single] }
            return []
        }()
        guard let firstAction = actionList.first, let parsedAction = parseAction(firstAction) else {
            return nil
        }

        let cleanedAlias = (alias?.isEmpty == false ? alias! : aliasFallback).trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedDescription = (description?.isEmpty == false ? description! : descriptionFallback).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !triggers.isEmpty else { return nil }

        return AutomationDraft(
            id: id,
            alias: cleanedAlias,
            description: cleanedDescription.isEmpty ? nil : cleanedDescription,
            mode: draftMode,
            triggers: triggers,
            actions: [parsedAction],
            daysOfWeek: daysOfWeek,
            triggerTime: triggerTime
        )
    }

    private static func parseTrigger(_ value: Any) -> (trigger: AutomationTrigger, days: [String]?, time: String?)? {
        guard let dict = value as? [String: Any] else { return nil }
        if let type = dict["type"] as? String {
            if type == "device" {
                let mode = (dict["mode"] as? String) ?? (dict["kind"] as? String) ?? ""
                let entityId = (dict["entityId"] as? String) ?? (dict["entity_id"] as? String) ?? ""
                switch mode {
                case "state_equals":
                    let to = dict["to"] as? String
                    let from = dict["from"] as? String
                    guard !entityId.isEmpty else { return nil }
                    return (.state(StateTrigger(entityId: entityId, to: to, from: from)), nil, nil)
                case "attribute_delta":
                    guard let attribute = dict["attribute"] as? String, !entityId.isEmpty else { return nil }
                    let directionRaw = (dict["direction"] as? String) ?? ""
                    let direction = directionRaw.lowercased().contains("decrease") ? "decrease" : "increase"
                    return (.numericDelta(NumericDeltaTrigger(entityId: entityId, attribute: attribute, direction: direction)), nil, nil)
                case "position_equals":
                    guard let attribute = dict["attribute"] as? String, let value = number(dict["to"]), !entityId.isEmpty else { return nil }
                    return (.position(PositionTrigger(entityId: entityId, attribute: attribute, value: value)), nil, nil)
                default:
                    break
                }
            } else if type == "schedule" {
                let at = (dict["at"] as? String) ?? (dict["time"] as? String)
                let days = dict["weekdays"] as? [String]
                if let at {
                    return (.time(TimeTrigger(at: at, daysOfWeek: days)), days, at)
                }
            }
        }

        if let platform = dict["platform"] as? String {
            switch platform {
            case "state":
                guard let entityId = dict["entity_id"] as? String else { return nil }
                let to = dict["to"] as? String ?? dict["to_state"] as? String
                let from = dict["from"] as? String ?? dict["from_state"] as? String
                return (.state(StateTrigger(entityId: entityId, to: to, from: from)), nil, nil)
            case "time":
                let at = dict["at"] as? String ?? dict["time"] as? String
                let days = (dict["weekday"] as? [String]) ?? (dict["daysOfWeek"] as? [String])
                if let at {
                    return (.time(TimeTrigger(at: at, daysOfWeek: days)), days, at)
                }
            case "numeric_state":
                guard let entityId = dict["entity_id"] as? String else { return nil }
                let attribute = dict["attribute"] as? String ?? ""
                let above = number(dict["above"])
                let below = number(dict["below"])
                if let above, let below {
                    let midpoint = (above + below) / 2
                    return (.position(PositionTrigger(entityId: entityId, attribute: attribute, value: midpoint)), nil, nil)
                }
            default:
                break
            }
        }

        return nil
    }

    private static func parseAction(_ value: Any) -> AutomationAction? {
        guard let dict = value as? [String: Any] else { return nil }
        if let type = dict["type"] as? String, type == "device_command" {
            guard let entityId = (dict["entityId"] as? String) ?? (dict["entity_id"] as? String), !entityId.isEmpty else {
                return nil
            }
            guard let commandStr = dict["command"] as? String, let command = DeviceCommand(rawValue: commandStr) else {
                return nil
            }
            let value = number(dict["value"])
            return .device(DeviceAction(entityId: entityId, command: command, value: value))
        }

        if let service = dict["service"] as? String {
            let entityId = extractEntityId(from: dict)
            guard let entityId, !entityId.isEmpty else { return nil }
            let data = dict["data"] as? [String: Any]
            switch service {
            case "light.turn_on" where data?["brightness_pct"] != nil:
                if let brightness = number(data?["brightness_pct"]) {
                    return .device(DeviceAction(entityId: entityId, command: .lightSetBrightness, value: brightness))
                }
            case "light.turn_on":
                return .device(DeviceAction(entityId: entityId, command: .lightTurnOn, value: nil))
            case "light.turn_off":
                return .device(DeviceAction(entityId: entityId, command: .lightTurnOff, value: nil))
            case "homeassistant.turn_on":
                return .device(DeviceAction(entityId: entityId, command: .lightTurnOn, value: nil))
            case "homeassistant.turn_off":
                return .device(DeviceAction(entityId: entityId, command: .lightTurnOff, value: nil))
            case "homeassistant.toggle":
                return .device(DeviceAction(entityId: entityId, command: .lightToggle, value: nil))
            case "cover.open_cover":
                return .device(DeviceAction(entityId: entityId, command: .blindOpen, value: nil))
            case "cover.close_cover":
                return .device(DeviceAction(entityId: entityId, command: .blindClose, value: nil))
            case "cover.set_cover_position":
                if let pos = number(data?["position"]) {
                    if pos >= 100 {
                        return .device(DeviceAction(entityId: entityId, command: .blindOpen, value: nil))
                    } else if pos <= 0 {
                        return .device(DeviceAction(entityId: entityId, command: .blindClose, value: nil))
                    } else {
                        return .device(DeviceAction(entityId: entityId, command: .blindSetPosition, value: pos))
                    }
                }
            case "media_player.media_play_pause":
                return .device(DeviceAction(entityId: entityId, command: .mediaPlayPause, value: nil))
            case "media_player.media_next_track":
                return .device(DeviceAction(entityId: entityId, command: .mediaNext, value: nil))
            case "media_player.media_previous_track":
                return .device(DeviceAction(entityId: entityId, command: .mediaPrevious, value: nil))
            case "media_player.volume_up":
                return .device(DeviceAction(entityId: entityId, command: .mediaVolumeUp, value: nil))
            case "media_player.volume_down":
                return .device(DeviceAction(entityId: entityId, command: .mediaVolumeDown, value: nil))
            case "media_player.volume_set":
                if let level = number(data?["volume_level"]) {
                    return .device(DeviceAction(entityId: entityId, command: .mediaVolumeSet, value: level * 100))
                }
            case "media_player.turn_on":
                return .device(DeviceAction(entityId: entityId, command: .tvTurnOn, value: nil))
            case "media_player.turn_off":
                return .device(DeviceAction(entityId: entityId, command: .tvTurnOff, value: nil))
            case "media_player.toggle":
                return .device(DeviceAction(entityId: entityId, command: .tvTogglePower, value: nil))
            case "climate.set_temperature":
                if let temp = number(data?["temperature"]) {
                    return .device(DeviceAction(entityId: entityId, command: .boilerSetTemperature, value: temp))
                }
            default:
                break
            }
        }

        return nil
    }

    private static func extractEntityId(from dict: [String: Any]) -> String? {
        if let target = dict["target"] as? [String: Any] {
            if let entityId = target["entity_id"] as? String { return entityId }
            if let list = target["entity_id"] as? [Any], let first = list.first as? String { return first }
        }
        if let entity = dict["entity_id"] as? String { return entity }
        if let list = dict["entity_id"] as? [Any], let first = list.first as? String { return first }
        if let data = dict["data"] as? [String: Any] {
            if let entity = data["entity_id"] as? String { return entity }
            if let list = data["entity_id"] as? [Any], let first = list.first as? String { return first }
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let dbl = value as? Double { return dbl }
        if let intVal = value as? Int { return Double(intVal) }
        if let num = value as? NSNumber { return num.doubleValue }
        if let str = value as? String { return Double(str) }
        return nil
    }

    // MARK: - Public API

    static func list(mode: HaMode, haConnection: HaConnection?) async throws -> [AutomationSummary] {
        if mode == .cloud {
            let result: PlatformFetchResult<PlatformResponse<[String: AnyCodable]>> = try await PlatformFetch.request("/api/automations?mode=cloud", method: "GET")
            if result.data.ok == false {
                throw AutomationsServiceError.server(result.data.error ?? "Unable to load automations.")
            }
            let list = (result.data.automations ?? []).map(mapPlatformAutomationToSummary)
            return filterAutomations(list)
        }

        let ha = try await resolveHa()
        let haLike = HaConnectionLike(baseUrl: ha.baseUrl, longLivedToken: ha.token)
        let states: [HAState] = try await HAService.callAPI(haLike, path: "/api/states")
        let autos = states
            .filter { $0.entity_id.hasPrefix("automation.") }
            .map { state -> AutomationSummary in
                let id = state.attributes["id"]?.anyValue as? String ?? state.entity_id.replacingOccurrences(of: "automation.", with: "")
                let alias = state.attributes["friendly_name"]?.anyValue as? String ?? state.entity_id
                let enabled = (state.state.lowercased() != "off")
                let modeValue = state.attributes["mode"]?.anyValue as? String
                return AutomationSummary(
                    id: id,
                    alias: alias,
                    description: (state.attributes["description"]?.anyValue as? String) ?? "",
                    enabled: enabled,
                    basicSummary: nil,
                    triggerSummary: nil,
                    actionSummary: nil,
                    hasDeviceAction: nil,
                    draft: nil,
                    entities: [],
                    targetDeviceIds: nil,
                    hasTemplates: nil,
                    canEdit: nil,
                    mode: modeValue,
                    raw: nil
                )
            }

        let enriched = try await enrichAutomationsWithHaDetails(list: autos, ha: ha)
        return filterAutomations(enriched)
    }

    static func create(draft: AutomationDraft, mode: HaMode, haConnection: HaConnection?) async throws {
        if mode == .cloud {
            let payload = toPlatformAutomationPayload(draft: draft)
            let body = try JSONSerialization.data(withJSONObject: payload)
            let result: PlatformFetchResult<PlatformResponse<Empty>> = try await PlatformFetch.request("/api/automations?mode=cloud", method: "POST", body: body)
            if result.data.ok == false {
                throw AutomationsServiceError.server(result.data.error ?? "Unable to save automation.")
            }
            return
        }

        let ha = try await resolveHa()
        var haConfig = AutomationCompiler.compile(draft)
        let sanitizedId = sanitizeAutomationId(haConfig.id ?? makeAutomationId())
        haConfig = HaAutomationConfig(
            id: sanitizedId,
            alias: haConfig.alias,
            description: haConfig.description,
            trigger: haConfig.trigger,
            action: haConfig.action,
            mode: haConfig.mode,
            condition: haConfig.condition
        )
        let payload = try JSONEncoder().encode(haConfig)
        _ = try await haFetch(ha: ha, path: "/api/config/automation/config/\(encodePathComponent(sanitizedId))", method: "POST", body: payload)
        _ = try? await PlatformFetch.request("/api/automations?recordOnly=1", method: "POST", body: try JSONSerialization.data(withJSONObject: ["automationId": sanitizedId])) as PlatformFetchResult<Empty>
    }

    static func update(id: String, draft: AutomationDraft, mode: HaMode, haConnection: HaConnection?) async throws {
        if mode == .cloud {
            var merged = draft
            merged.id = id
            let payload = toPlatformAutomationPayload(draft: merged)
            let body = try JSONSerialization.data(withJSONObject: payload)
            let result: PlatformFetchResult<PlatformResponse<Empty>> = try await PlatformFetch.request("/api/automations/\(encodePathComponent(id))?mode=cloud", method: "PATCH", body: body)
            if result.data.ok == false {
                throw AutomationsServiceError.server(result.data.error ?? "Unable to update automation.")
            }
            return
        }

        let ha = try await resolveHa()
        var merged = draft
        merged.id = id
        let haConfig = AutomationCompiler.compile(merged)
        let payload = try JSONEncoder().encode(haConfig)
        _ = try await haFetch(ha: ha, path: "/api/config/automation/config/\(encodePathComponent(id))", method: "POST", body: payload)
    }

    static func delete(id: String, mode: HaMode, haConnection: HaConnection?) async throws {
        if mode == .cloud {
            let result: PlatformFetchResult<PlatformResponse<Empty>> = try await PlatformFetch.request("/api/automations/\(encodePathComponent(id))?mode=cloud", method: "DELETE")
            if result.data.ok == false {
                throw AutomationsServiceError.server(result.data.error ?? "Unable to delete automation.")
            }
            return
        }

        let ha = try await resolveHa()
        _ = try? await haFetch(ha: ha, path: "/api/config/automation/config/\(encodePathComponent(id))", method: "DELETE", body: nil)
        _ = try? await PlatformFetch.request("/api/automations/\(encodePathComponent(id))?recordOnly=1", method: "DELETE") as PlatformFetchResult<Empty>
    }

    static func setEnabled(id: String, enabled: Bool, mode: HaMode, haConnection: HaConnection?) async throws {
        if mode == .cloud {
            let body = try JSONSerialization.data(withJSONObject: ["enabled": enabled])
            let result: PlatformFetchResult<PlatformResponse<Empty>> = try await PlatformFetch.request("/api/automations/\(encodePathComponent(id))/enabled?mode=cloud", method: "POST", body: body)
            if result.data.ok == false {
                throw AutomationsServiceError.server(result.data.error ?? "Unable to update automation state.")
            }
            return
        }

        let ha = try await resolveHa()
        let service = enabled ? "turn_on" : "turn_off"
        let body = try JSONSerialization.data(withJSONObject: ["entity_id": "automation.\(id)"])
        _ = try await haFetch(ha: ha, path: "/api/services/automation/\(service)", method: "POST", body: body)
    }

    // MARK: - Helpers

    private static func resolveHa() async throws -> HaConn {
        let secrets = try await HomeModeSecretsStore.fetch()
        return HaConn(baseUrl: secrets.baseUrl.replacingOccurrences(of: "/+$", with: "", options: .regularExpression), token: secrets.longLivedToken)
    }

    private static func haFetch(ha: HaConn, path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let url = URL(string: path, relativeTo: URL(string: ha.baseUrl + (path.hasPrefix("/") ? "" : "/"))) else {
            throw AutomationsServiceError.server("Invalid Dinodia Hub URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 10
        request.setValue("Bearer \(ha.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw AutomationsServiceError.server(text.isEmpty ? "Dinodia Hub request failed." : text)
        }
        return data
    }

    private static func haFetchJSON(ha: HaConn, path: String) async throws -> Any? {
        let data = try await haFetch(ha: ha, path: path, method: "GET", body: nil)
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func enrichAutomationsWithHaDetails(list: [AutomationSummary], ha: HaConn) async throws -> [AutomationSummary] {
        if list.isEmpty { return list }
        var cachedConfigs: [Any]? = nil

        func ensureConfigs() async -> [Any]? {
            if let cachedConfigs { return cachedConfigs }
            if let all = try? await haFetchJSON(ha: ha, path: "/api/config/automation") as? [Any] {
                cachedConfigs = all
                return all
            }
            return nil
        }

        return try await withThrowingTaskGroup(of: AutomationSummary.self) { group in
            for item in list {
                group.addTask {
                    var config = try? await haFetchJSON(ha: ha, path: "/api/config/automation/config/\(encodePathComponent(item.id))")
                    if config == nil {
                        if let allConfigs = await ensureConfigs() {
                            config = findMatchingConfig(item: item, configs: allConfigs)
                        }
                    }
                    guard let cfg = config as? [String: Any] else { return item }
                    let triggers = (cfg["trigger"] as? [Any]) ?? []
                    let actions = (cfg["action"] as? [Any]) ?? []
                    let triggerSummary = summarizeTriggers(triggers: triggers)
                    let actionSummary = summarizeActions(actions: actions)
                    let hasDeviceAction = actions.isEmpty ? false : actions.contains { actionTargetsDevice(action: $0) }
                    let targets = extractActionTargets(actions: actions)
                    let templates = hasTemplates(node: cfg["condition"]) || hasTemplates(node: triggers) || hasTemplates(node: actions)
                    return AutomationSummary(
                        id: item.id,
                        alias: item.alias,
                        description: !item.description.isEmpty ? item.description : (cfg["description"] as? String ?? ""),
                        enabled: item.enabled,
                        basicSummary: item.basicSummary ?? (cfg["description"] as? String ?? cfg["alias"] as? String ?? item.alias),
                        triggerSummary: item.triggerSummary ?? triggerSummary,
                        actionSummary: item.actionSummary ?? actionSummary,
                        hasDeviceAction: item.hasDeviceAction ?? hasDeviceAction,
                        draft: item.draft,
                        entities: targets.entityIds,
                        targetDeviceIds: targets.deviceIds,
                        hasTemplates: templates,
                        canEdit: templates ? false : true,
                        mode: (cfg["mode"] as? String) ?? item.mode ?? "single",
                        raw: cfg
                    )
                }
            }

            var results: [AutomationSummary] = []
            for try await item in group {
                results.append(item)
            }
            return results
        }
    }

    nonisolated private static func summarizeTrigger(trigger: Any) -> String? {
        guard let dict = trigger as? [String: Any] else { return nil }
        let platform = (dict["platform"] as? String) ?? (dict["kind"] as? String) ?? ""
        switch platform {
        case "state":
            let entityId = dict["entity_id"] as? String ?? dict["entityId"] as? String
            let from = dict["from"] ?? dict["from_state"]
            let to = dict["to"] ?? dict["to_state"]
            if let entityId, let from = from, let to = to {
                return "\(entityId): \(from) → \(to)"
            }
            if let entityId, let to = to {
                return "\(entityId) → \(to)"
            }
            if let entityId, let from = from {
                return "\(entityId) from \(from)"
            }
            return entityId ?? "State change"
        case "numeric_state":
            let entityId = dict["entity_id"] as? String ?? dict["entityId"] as? String
            let attribute = dict["attribute"] as? String
            let above = dict["above"]
            let below = dict["below"]
            var bounds: [String] = []
            if let above { bounds.append(">\(above)") }
            if let below { bounds.append("<\(below)") }
            let label = [entityId ?? "Value", attribute.map { " (\($0))" } ?? ""].joined()
            return "\(label) \(bounds.joined(separator: " "))".trimmingCharacters(in: .whitespaces)
        case "numeric_delta":
            let entityId = dict["entityId"] as? String ?? dict["entity_id"] as? String
            let attribute = dict["attribute"] as? String
            let dir = (dict["direction"] as? String) == "decrease" ? "decreases" : "increases"
            let label = [entityId ?? "Value", attribute.map { " (\($0))" } ?? ""].joined()
            return "\(label) \(dir)"
        case "position_equals":
            let entityId = dict["entityId"] as? String ?? dict["entity_id"] as? String
            let attribute = dict["attribute"] as? String
            let val = dict["value"]
            let label = [entityId ?? "Position", attribute.map { " (\($0))" } ?? ""].joined()
            return "\(label) =\(val ?? "")"
        case "time":
            let at = dict["at"] as? String ?? dict["time"] as? String ?? ""
            let daysArr = (dict["weekday"] as? [String]) ?? (dict["daysOfWeek"] as? [String]) ?? []
            let days = daysArr.joined(separator: ", ")
            if !at.isEmpty && !days.isEmpty { return "\(days) @ \(at)" }
            if !at.isEmpty { return "At \(at)" }
            if !days.isEmpty { return "On \(days)" }
            return "Scheduled time"
        default:
            return platform.isEmpty ? nil : platform
        }
    }

    nonisolated private static func summarizeTriggers(triggers: [Any]) -> String? {
        let parts = triggers.compactMap { summarizeTrigger(trigger: $0) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    nonisolated private static func summarizeAction(action: Any) -> String? {
        guard let dict = action as? [String: Any] else { return nil }
        if let kind = dict["kind"] as? String, kind == "device_command" {
            let target = dict["entityId"] as? String ?? dict["entity_id"] as? String
            if let command = dict["command"] as? String {
                return target != nil ? "\(command) → \(target!)" : command
            }
        }
        if let service = dict["service"] as? String {
            let targetVal = entityIdFromTarget(target: dict["target"]) ??
                (dict["entity_id"] as? String) ??
                (dict["data"] as? [String: Any])?["entity_id"] as? String
            return targetVal != nil ? "\(service) → \(targetVal!)" : service
        }
        if let type = dict["type"] as? String {
            let target = entityIdFromTarget(target: dict["target"])
            return target != nil ? "\(type) → \(target!)" : type
        }
        if let sequence = dict["sequence"] as? [Any], let first = sequence.first {
            let nested = summarizeAction(action: first)
            return nested != nil ? "Sequence: \(nested!)" : "Sequence"
        }
        if let choose = dict["choose"] as? [Any], !choose.isEmpty {
            return "Choice action"
        }
        return nil
    }

    nonisolated private static func summarizeActions(actions: [Any]) -> String? {
        let parts = actions.compactMap { summarizeAction(action: $0) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    nonisolated private static func hasTemplates(node: Any?) -> Bool {
        guard let node else { return false }
        if let str = node as? String {
            if str.contains("trigger.to_state") && str.contains("trigger.from_state") {
                return false
            }
            return str.contains("{{")
        }
        if let arr = node as? [Any] { return arr.contains(where: { hasTemplates(node: $0) }) }
        if let dict = node as? [String: Any] { return dict.values.contains(where: { hasTemplates(node: $0) }) }
        return false
    }

    nonisolated private static func entityIdFromTarget(target: Any?) -> String? {
        if let str = target as? String, !str.isEmpty { return str }
        if let dict = target as? [String: Any] {
            if let entity = dict["entity_id"] as? String, !entity.isEmpty { return entity }
            if let device = dict["device_id"] as? String, !device.isEmpty { return device }
            if let area = dict["area_id"] as? String, !area.isEmpty { return area }
            if let entityList = dict["entity_id"] as? [String], let first = entityList.first, !first.isEmpty { return first }
        }
        if let array = target as? [Any], let first = array.first { return entityIdFromTarget(target: first) }
        return nil
    }

    nonisolated private static func actionTargetsDevice(action: Any) -> Bool {
        guard let dict = action as? [String: Any] else { return false }
        if let deviceId = dict["device_id"] as? String, !deviceId.isEmpty { return true }
        if entityIdFromTarget(target: dict["target"]) != nil { return true }
        if let entityId = dict["entity_id"] as? String, !entityId.isEmpty { return true }
        if let entityArr = dict["entity_id"] as? [String], !entityArr.isEmpty { return true }
        if let choose = dict["choose"] as? [Any] {
            return choose.contains { branch in
                if let branchDict = branch as? [String: Any] {
                    if let sequence = branchDict["sequence"] as? [Any], sequence.contains(where: actionTargetsDevice) { return true }
                    if let conditions = branchDict["conditions"] as? [Any], conditions.contains(where: actionTargetsDevice) { return true }
                }
                return false
            }
        }
        if let sequence = dict["sequence"] as? [Any] {
            return sequence.contains { actionTargetsDevice(action: $0) }
        }
        return false
    }

    nonisolated private static func extractActionTargets(actions: [Any]) -> (entityIds: [String], deviceIds: [String]) {
        var entitySet = Set<String>()
        var deviceSet = Set<String>()

        func addEntity(_ value: Any?) {
            if let str = value as? String { entitySet.insert(str) }
            if let arr = value as? [String] { arr.forEach { entitySet.insert($0) } }
        }

        func addDevice(_ value: Any?) {
            if let str = value as? String { deviceSet.insert(str) }
            if let arr = value as? [String] { arr.forEach { deviceSet.insert($0) } }
        }

        func visit(_ node: Any) {
            guard let dict = node as? [String: Any] else { return }
            addEntity(entityIdFromTarget(target: dict["target"]))
            addEntity(dict["entity_id"])
            if let data = dict["data"] as? [String: Any] {
                addEntity(data["entity_id"])
            }
            addDevice(dict["device_id"])
            if let target = dict["target"] as? [String: Any] {
                addDevice(target["device_id"])
            }

            if let sequence = dict["sequence"] as? [Any] {
                sequence.forEach { visit($0) }
            }
            if let choose = dict["choose"] as? [Any] {
                choose.forEach { branch in
                    if let branchDict = branch as? [String: Any] {
                        if let seq = branchDict["sequence"] as? [Any] {
                            seq.forEach { visit($0) }
                        }
                        if let cond = branchDict["conditions"] as? [Any] {
                            cond.forEach { visit($0) }
                        }
                    }
                }
            }
        }

        actions.forEach { visit($0) }

        return (Array(entitySet), Array(deviceSet))
    }

    nonisolated private static func findMatchingConfig(item: AutomationSummary, configs: [Any]) -> [String: Any]? {
        func normalize(_ val: String?) -> String {
            return (val ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let targets = [item.id, "automation.\(item.id)"].map(normalize)
        let targetAlias = normalize(item.alias)
        for cfg in configs {
            guard let dict = cfg as? [String: Any] else { continue }
            let cfgId = normalize(dict["id"] as? String)
            let cfgAlias = normalize(dict["alias"] as? String)
            let cfgEntity = normalize(dict["entity_id"] as? String)
            if targets.contains(cfgId) || targets.contains(cfgEntity) || (!cfgAlias.isEmpty && cfgAlias == targetAlias) {
                return dict
            }
        }
        return nil
    }

    private static func filterAutomations(_ list: [AutomationSummary]) -> [AutomationSummary] {
        return list.filter { item in
            let alias = item.alias.lowercased()
            let description = item.description.lowercased()
            return !(alias.contains("default") || description.contains("default"))
        }
    }

    private static func mapPlatformAutomationToSummary(_ auto: [String: AnyCodable]) -> AutomationSummary {
        let raw = auto["raw"]?.value
        let hasTemplatesFlag = (auto["hasTemplates"]?.value as? Bool) ?? false
        return AutomationSummary(
            id: (auto["id"]?.value as? String)?.replacingOccurrences(of: "^automation\\.", with: "", options: .regularExpression) ?? "",
            alias: (auto["alias"]?.value as? String) ?? "Automation",
            description: (auto["description"]?.value as? String) ?? "",
            enabled: (auto["enabled"]?.value as? Bool) ?? true,
            basicSummary: auto["basicSummary"]?.value as? String,
            triggerSummary: auto["triggerSummary"]?.value as? String,
            actionSummary: auto["actionSummary"]?.value as? String,
            hasDeviceAction: auto["hasDeviceAction"]?.value as? Bool,
            draft: nil,
            entities: auto["entities"]?.value as? [String],
            targetDeviceIds: auto["actionDeviceIds"]?.value as? [String],
            hasTemplates: hasTemplatesFlag,
            canEdit: (auto["canEdit"]?.value as? Bool) ?? (!hasTemplatesFlag),
            mode: (auto["mode"]?.value as? String) ?? "single",
            raw: raw
        )
    }

    private static func toPlatformAutomationPayload(draft: AutomationDraft) -> [String: Any] {
        let trigger = draft.triggers.first
        let action = draft.actions.first
        var payload: [String: Any] = [
            "alias": draft.alias,
            "description": draft.description ?? "",
            "mode": draft.mode?.rawValue ?? "single",
            "enabled": true
        ]
        if case .state(let t)? = trigger {
            payload["trigger"] = [
                "type": "device",
                "entityId": t.entityId,
                "mode": "state_equals",
                "to": t.to as Any
            ]
        } else if case .numericDelta(let t)? = trigger {
            payload["trigger"] = [
                "type": "device",
                "entityId": t.entityId,
                "mode": "attribute_delta",
                "attribute": t.attribute,
                "direction": t.direction == "decrease" ? "decreased" : "increased"
            ]
        } else if case .position(let t)? = trigger {
            payload["trigger"] = [
                "type": "device",
                "entityId": t.entityId,
                "mode": "position_equals",
                "attribute": t.attribute,
                "to": t.value
            ]
        } else if case .time(let t)? = trigger {
            payload["trigger"] = [
                "type": "schedule",
                "scheduleType": "weekly",
                "at": t.at,
                "weekdays": t.daysOfWeek ?? draft.daysOfWeek ?? []
            ]
        }

        if case .device(let a)? = action {
            payload["action"] = [
                "type": "device_command",
                "entityId": a.entityId,
                "command": a.command.rawValue,
                "value": a.value as Any
            ]
        }
        return payload
    }

    private static func sanitizeAutomationId(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: "[^a-zA-Z0-9_]", with: "_", options: .regularExpression)
        return cleaned.lowercased()
    }

    private static func makeAutomationId() -> String {
        let random = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let timeHex = String(Int(Date().timeIntervalSince1970), radix: 16)
        return sanitizeAutomationId("dinodia_\(timeHex)\(random)")
    }

    private static func encodePathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}
