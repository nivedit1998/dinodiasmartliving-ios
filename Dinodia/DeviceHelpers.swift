import Foundation

func brightnessPercent(for device: UIDevice) -> Int? {
    if let value = device.attributes["brightness_pct"]?.anyValue as? Double {
        return Int(round(value))
    }
    if let value = device.attributes["brightness"]?.anyValue as? Double {
        return Int(round((value / 255.0) * 100))
    }
    return nil
}

func blindPositionPercent(for device: UIDevice) -> Int? {
    let keys = ["blind_position", "position", "current_position", "position_percent"]
    for key in keys {
        if let value = device.attributes[key]?.anyValue as? Double, value.isFinite {
            return Int(round(value))
        }
        if let value = device.attributes[key]?.anyValue as? Int {
            return value
        }
        if let value = device.attributes[key]?.anyValue as? String, let num = Double(value) {
            return Int(round(num))
        }
    }
    return nil
}

func secondaryText(for device: UIDevice) -> String {
    let state = device.state
    let label = getPrimaryLabel(for: device)
    switch label {
    case "Light":
        if let pct = brightnessPercent(for: device) {
            return "\(pct)% brightness"
        }
        return state == "on" ? "On" : "Off"
    case "Spotify", "TV", "Speaker":
        if let title = device.attributes["media_title"]?.anyValue as? String, !title.isEmpty {
            return title
        }
        if state.lowercased() == "playing" { return "Playing" }
        if state.lowercased() == "paused" { return "Paused" }
        return state
    case "Boiler":
        let target = boilerSetpoint(from: device.attributes)
        let current = boilerCurrentTemperature(from: device.attributes) ?? (Double(device.state) ?? Double(device.state) ?? nil)
        if let t = target, let c = current {
            return "Target \(Int(t))° • Now \(Int(c))°"
        }
        if let t = target {
            return "Target \(Int(t))°"
        }
        if let c = current {
            return "Now \(Int(c))°"
        }
        return state.isEmpty ? "Boiler" : state
    case "Blind":
        if let pos = blindPositionPercent(for: device) {
            return "Position \(pos)%"
        }
        let s = state.lowercased()
        if s == "stop" || s == "stopped" { return "" }
        return state.isEmpty ? "Idle" : state.capitalized
    case "Motion Sensor":
        let active = ["on", "motion", "detected", "open"].contains(state.lowercased())
        return active ? "Motion detected" : "No motion"
    default:
        return state.isEmpty ? "Unknown" : state
    }
}

func primaryAction(for label: String, device: UIDevice) -> DeviceCommand? {
    switch label {
    case "Light":
        return .lightToggle
    case "Blind":
        let normalized = device.state.lowercased()
        let isOpen = normalized == "open" || normalized == "opening" || normalized == "on"
        return isOpen ? .blindClose : .blindOpen
    case "Spotify":
        return .mediaPlayPause
    case "TV":
        return .tvTogglePower
    case "Speaker":
        return .speakerTogglePower
    case "Boiler":
        return nil // handled via inline +/– controls
    default:
        return nil
    }
}

func primaryActionLabel(for label: String, device: UIDevice) -> String {
    switch label {
    case "Light":
        return "Toggle light"
    case "Blind":
        let state = device.state.lowercased()
        let isOpen = state == "open" || state == "opening" || state == "on"
        return isOpen ? "Close blinds" : "Open blinds"
    case "Spotify":
        return device.state.lowercased() == "playing" ? "Pause" : "Play"
    case "TV":
        return device.state.lowercased() == "on" ? "Turn off TV" : "Turn on TV"
    case "Speaker":
        let state = device.state.lowercased()
        let isOn = state == "on" || state == "playing"
        return isOn ? "Turn off speaker" : "Turn on speaker"
    default:
        return "Action"
    }
}

func volumePercent(for device: UIDevice) -> Double {
    if let level = device.attributes["volume_level"]?.anyValue as? Double {
        return level * 100
    }
    return 0
}

// MARK: - Boiler helpers

func boilerSetpoint(from attrs: [String: CodableValue]) -> Double? {
    let keys = ["temperature", "target_temperature", "target_temp", "target_temp_low", "target_temp_high"]
    for key in keys {
        if let val = attrs[key]?.anyValue {
            if let d = val as? Double { return d }
            if let i = val as? Int { return Double(i) }
            if let s = val as? String, let d = Double(s) { return d }
        }
    }
    return nil
}

func boilerCurrentTemperature(from attrs: [String: CodableValue]) -> Double? {
    let keys = ["current_temperature", "temperature", "temp"]
    for key in keys {
        if let val = attrs[key]?.anyValue {
            if let d = val as? Double { return d }
            if let i = val as? Int { return Double(i) }
            if let s = val as? String, let d = Double(s) { return d }
        }
    }
    return nil
}
