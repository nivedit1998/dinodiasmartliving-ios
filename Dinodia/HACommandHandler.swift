import Foundation

enum DeviceCommand: String, CaseIterable {
    case lightToggle = "light/toggle"
    case lightTurnOn = "light/turn_on"
    case lightTurnOff = "light/turn_off"
    case lightSetBrightness = "light/set_brightness"
    case blindOpen = "blind/open"
    case blindClose = "blind/close"
    case blindSetPosition = "blind/set_position"
    case mediaPlayPause = "media/play_pause"
    case mediaNext = "media/next"
    case mediaPrevious = "media/previous"
    case mediaVolumeUp = "media/volume_up"
    case mediaVolumeDown = "media/volume_down"
    case mediaVolumeSet = "media/volume_set"
    case boilerTempUp = "boiler/temp_up"
    case boilerTempDown = "boiler/temp_down"
    case boilerSetTemperature = "boiler/set_temperature"
    case tvTogglePower = "tv/toggle_power"
    case tvTurnOn = "tv/turn_on"
    case tvTurnOff = "tv/turn_off"
    case speakerTogglePower = "speaker/toggle_power"
    case speakerTurnOn = "speaker/turn_on"
    case speakerTurnOff = "speaker/turn_off"

    static var allCases: [DeviceCommand] {
        [
            .lightToggle,
            .lightTurnOn,
            .lightTurnOff,
            .lightSetBrightness,
            .blindOpen,
            .blindClose,
            .mediaPlayPause,
            .mediaNext,
            .mediaPrevious,
            .mediaVolumeUp,
            .mediaVolumeDown,
            .mediaVolumeSet,
            .boilerTempUp,
            .boilerTempDown,
            .boilerSetTemperature,
            .tvTogglePower,
            .tvTurnOn,
            .tvTurnOff,
            .speakerTogglePower,
            .speakerTurnOn,
            .speakerTurnOff,
        ]
    }
}

enum HACommandError: LocalizedError {
    case invalidValue
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .invalidValue:
            return "Command requires numeric value"
        case .unsupported(let command):
            return "Unsupported command \(command)"
        }
    }
}

struct HACommandHandler {
    static func handle(ha: HaConnectionLike, entityId: String, command: DeviceCommand, value: Double? = nil, blindTravelSeconds: Double? = nil) async throws {
        switch command {
        case .lightToggle:
            try await toggleLight(ha: ha, entityId: entityId)
        case .lightTurnOn:
            try await setLightPower(ha: ha, entityId: entityId, on: true)
        case .lightTurnOff:
            try await setLightPower(ha: ha, entityId: entityId, on: false)
        case .lightSetBrightness:
            guard let value else { throw HACommandError.invalidValue }
            try await setBrightness(ha: ha, entityId: entityId, value: value)
        case .blindOpen:
            try await sendBlind(ha: ha, entityId: entityId, targetPosition: 100, blindTravelSeconds: blindTravelSeconds)
        case .blindClose:
            try await sendBlind(ha: ha, entityId: entityId, targetPosition: 0, blindTravelSeconds: blindTravelSeconds)
        case .blindSetPosition:
            guard let value else { throw HACommandError.invalidValue }
            let target = clamp(value, min: 0, max: 100)
            try await sendBlind(ha: ha, entityId: entityId, targetPosition: target, blindTravelSeconds: blindTravelSeconds)
        case .mediaPlayPause:
            try await toggleMedia(ha: ha, entityId: entityId)
        case .mediaNext:
            try await HAService.callHaService(ha, domain: "media_player", service: "media_next_track", data: ["entity_id": entityId])
        case .mediaPrevious:
            try await HAService.callHaService(ha, domain: "media_player", service: "media_previous_track", data: ["entity_id": entityId])
        case .mediaVolumeUp:
            try await HAService.callHaService(ha, domain: "media_player", service: "volume_up", data: ["entity_id": entityId])
        case .mediaVolumeDown:
            try await HAService.callHaService(ha, domain: "media_player", service: "volume_down", data: ["entity_id": entityId])
        case .mediaVolumeSet:
            guard let value else { throw HACommandError.invalidValue }
            try await HAService.callHaService(ha, domain: "media_player", service: "volume_set", data: [
                "entity_id": entityId,
                "volume_level": max(0, min(1, value / 100))
            ])
        case .boilerTempUp, .boilerTempDown:
            try await adjustBoiler(ha: ha, entityId: entityId, increase: command == .boilerTempUp)
        case .boilerSetTemperature:
            guard let value else { throw HACommandError.invalidValue }
            try await setBoilerTemperature(ha: ha, entityId: entityId, value: value)
        case .tvTogglePower, .speakerTogglePower:
            try await toggleMediaPower(ha: ha, entityId: entityId)
        case .tvTurnOn, .speakerTurnOn:
            try await HAService.callHaService(ha, domain: "media_player", service: "turn_on", data: ["entity_id": entityId])
        case .tvTurnOff, .speakerTurnOff:
            try await HAService.callHaService(ha, domain: "media_player", service: "turn_off", data: ["entity_id": entityId])
        }
    }

    private static func toggleLight(ha: HaConnectionLike, entityId: String) async throws {
        let state = try await HAService.fetchState(ha, entityId: entityId)
        let domain = entityId.split(separator: ".").first.map(String.init) ?? ""
        if domain == "light" {
            let service = state.state.lowercased() == "on" ? "turn_off" : "turn_on"
            try await HAService.callHaService(ha, domain: "light", service: service, data: ["entity_id": entityId])
        } else {
            try await HAService.callHaService(ha, domain: "homeassistant", service: "toggle", data: ["entity_id": entityId])
        }
    }

    private static func setLightPower(ha: HaConnectionLike, entityId: String, on: Bool) async throws {
        let domain = entityId.split(separator: ".").first.map(String.init) ?? ""
        if domain == "light" {
            let service = on ? "turn_on" : "turn_off"
            try await HAService.callHaService(ha, domain: "light", service: service, data: ["entity_id": entityId])
        } else {
            let service = on ? "turn_on" : "turn_off"
            try await HAService.callHaService(ha, domain: "homeassistant", service: service, data: ["entity_id": entityId])
        }
    }

    private static func setBrightness(ha: HaConnectionLike, entityId: String, value: Double) async throws {
        let clamped = max(0, min(100, value))
        let domain = entityId.split(separator: ".").first.map(String.init) ?? ""
        guard domain == "light" else {
            throw HACommandError.unsupported("Brightness supported only for lights")
        }
        try await HAService.callHaService(ha, domain: "light", service: "turn_on", data: [
            "entity_id": entityId,
            "brightness_pct": clamped
        ])
    }

    private static func toggleMedia(ha: HaConnectionLike, entityId: String) async throws {
        let state = try await HAService.fetchState(ha, entityId: entityId)
        let isPlaying = state.state.lowercased() == "playing"
        try await HAService.callHaService(ha, domain: "media_player", service: isPlaying ? "media_pause" : "media_play", data: ["entity_id": entityId])
    }

    private static func toggleMediaPower(ha: HaConnectionLike, entityId: String) async throws {
        let state = try await HAService.fetchState(ha, entityId: entityId)
        let isOff = state.state.lowercased() == "off" || state.state.lowercased() == "standby"
        try await HAService.callHaService(ha, domain: "media_player", service: isOff ? "turn_on" : "turn_off", data: ["entity_id": entityId])
    }

    private static func adjustBoiler(ha: HaConnectionLike, entityId: String, increase: Bool) async throws {
        let state = try await HAService.fetchState(ha, entityId: entityId)
        let attrs = state.attributes
        let currentSetpoint = boilerSetpoint(from: attrs)
        guard let currentSetpoint else {
            throw HACommandError.unsupported("Boiler setpoint unavailable")
        }
        let next = increase ? currentSetpoint + 1 : currentSetpoint - 1
        try await HAService.callHaService(ha, domain: "climate", service: "set_temperature", data: [
            "entity_id": entityId,
            "temperature": next
        ])
    }

    private static func setBoilerTemperature(ha: HaConnectionLike, entityId: String, value: Double) async throws {
        try await HAService.callHaService(ha, domain: "climate", service: "set_temperature", data: [
            "entity_id": entityId,
            "temperature": value
        ])
    }

    private static func sendBlind(ha: HaConnectionLike, entityId: String, targetPosition: Double, blindTravelSeconds: Double?) async throws {
        let defaultTravel = 22.0
        let hasOverride = (blindTravelSeconds ?? 0) > 0
        let travelRaw = hasOverride ? blindTravelSeconds ?? defaultTravel : defaultTravel
        let travel = clamp(travelRaw, min: 5, max: 90)
        try await HAService.callHaService(
            ha,
            domain: "script",
            service: "global_blind_controller",
            data: [
                "target_cover": entityId,
                "target_position": Int(round(targetPosition)),
                "travel_seconds": travel
            ],
            timeout: 40.0
        )
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        return Swift.max(min, Swift.min(max, value))
    }
}
