import SwiftUI

struct DeviceVisualPreset {
    let gradient: [Color]
    let inactiveBackground: Color
    let icon: String
    let iconActiveBackground: Color
    let iconInactiveBackground: Color
    let accent: [Color]
}

private let defaultPreset = DeviceVisualPreset(
    gradient: [Color(hex: "#f2f2f7"), Color(hex: "#e5e7eb")],
    inactiveBackground: Color(hex: "#f7f7fa"),
    icon: "•",
    iconActiveBackground: Color(hex: "#d1d5db"),
    iconInactiveBackground: Color(hex: "#e5e7eb"),
    accent: [Color(hex: "#e5e7eb"), Color(hex: "#f3f4f6")]
)

private let presets: [String: DeviceVisualPreset] = {
    func color(_ hex: String) -> Color { Color(hex: hex) }
    return [
        "Light": DeviceVisualPreset(
            gradient: [color("#fef3c7"), color("#fcd34d")],
            inactiveBackground: color("#fdf6e3"),
            icon: "💡",
            iconActiveBackground: color("#f59e0b"),
            iconInactiveBackground: color("#fcd34d"),
            accent: [color("#f59e0b"), color("#fcd34d")]
        ),
        "Blind": DeviceVisualPreset(
            gradient: [color("#cffafe"), color("#22d3ee")],
            inactiveBackground: color("#ecfeff"),
            icon: "🪟",
            iconActiveBackground: color("#06b6d4"),
            iconInactiveBackground: color("#bae6fd"),
            accent: [color("#06b6d4"), color("#22d3ee")]
        ),
        "Motion Sensor": DeviceVisualPreset(
            gradient: [color("#d1fae5"), color("#6ee7b7")],
            inactiveBackground: color("#ecfdf3"),
            icon: "🛰️",
            iconActiveBackground: color("#10b981"),
            iconInactiveBackground: color("#bbf7d0"),
            accent: [color("#10b981"), color("#34d399")]
        ),
        "Spotify": DeviceVisualPreset(
            gradient: [color("#d1fae5"), color("#34d399")],
            inactiveBackground: color("#e8fff3"),
            icon: "🎵",
            iconActiveBackground: color("#10b981"),
            iconInactiveBackground: color("#bbf7d0"),
            accent: [color("#10b981"), color("#34d399")]
        ),
        "Boiler": DeviceVisualPreset(
            gradient: [color("#ffedd5"), color("#fb923c")],
            inactiveBackground: color("#fff4e5"),
            icon: "🔥",
            iconActiveBackground: color("#f97316"),
            iconInactiveBackground: color("#fed7aa"),
            accent: [color("#fb923c"), color("#fdba74")]
        ),
        "Doorbell": DeviceVisualPreset(
            gradient: [color("#ffedd5"), color("#fbbf24")],
            inactiveBackground: color("#fff8e1"),
            icon: "🔔",
            iconActiveBackground: color("#f59e0b"),
            iconInactiveBackground: color("#fde68a"),
            accent: [color("#f59e0b"), color("#fbbf24")]
        ),
        "Home Security": DeviceVisualPreset(
            gradient: [color("#e0e7ff"), color("#818cf8")],
            inactiveBackground: color("#eef2ff"),
            icon: "🛡️",
            iconActiveBackground: color("#6366f1"),
            iconInactiveBackground: color("#c7d2fe"),
            accent: [color("#6366f1"), color("#818cf8")]
        ),
        "TV": DeviceVisualPreset(
            gradient: [color("#e0e7ff"), color("#6366f1")],
            inactiveBackground: color("#eef2ff"),
            icon: "📺",
            iconActiveBackground: color("#4f46e5"),
            iconInactiveBackground: color("#c7d2fe"),
            accent: [color("#4f46e5"), color("#818cf8")]
        ),
        "Speaker": DeviceVisualPreset(
            gradient: [color("#ede9fe"), color("#a78bfa")],
            inactiveBackground: color("#f5f3ff"),
            icon: "🔊",
            iconActiveBackground: color("#8b5cf6"),
            iconInactiveBackground: color("#ddd6fe"),
            accent: [color("#8b5cf6"), color("#a78bfa")]
        )
    ]
}()

func getDevicePreset(label: String?) -> DeviceVisualPreset {
    guard let label else { return defaultPreset }
    return presets[label] ?? defaultPreset
}

func isDeviceActive(label: String?, device: UIDevice) -> Bool {
    let state = device.state.lowercased()
    let activeForMotion = ["on", "motion", "detected", "open"]
    switch label {
    case "Light", "Spotify", "TV", "Speaker":
        return state == "on" || state == "playing"
    case "Blind":
        return state == "open" || state == "opening"
    case "Home Security", "Doorbell", "Boiler":
        return true
    case "Motion Sensor":
        return activeForMotion.contains(state)
    default:
        return state == "on" || state == "playing"
    }
}

extension Color {
    init(hex: String) {
        let hexString = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hexString.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
