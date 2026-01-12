import Foundation
import SwiftUI

struct LabelMeta {
    let name: String
    let synonyms: [String]
    let order: Int
    let isPrimary: Bool
    let isSensor: Bool
    let isDetailOnly: Bool
}

enum LabelRegistry {
    static let other = "Other"

    private static let metas: [LabelMeta] = [
        .init(name: "Light", synonyms: ["light", "lights"], order: 0, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Blind", synonyms: ["blind", "blinds", "shade", "shades", "curtain", "curtains"], order: 1, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Motion Sensor", synonyms: ["motion sensor", "motion"], order: 2, isPrimary: true, isSensor: true, isDetailOnly: false),
        .init(name: "Spotify", synonyms: ["spotify"], order: 3, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Boiler", synonyms: ["boiler", "heating"], order: 4, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Doorbell", synonyms: ["doorbell"], order: 5, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Home Security", synonyms: ["home security", "security", "alarm"], order: 6, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "TV", synonyms: ["tv", "television"], order: 7, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Speaker", synonyms: ["speaker", "speakers", "audio"], order: 8, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Switch", synonyms: ["switch", "switches", "outlet", "plug"], order: 9, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Thermostat", synonyms: ["thermostat"], order: 10, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Media", synonyms: ["media", "media player"], order: 11, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Vacuum", synonyms: ["vacuum", "cleaner"], order: 12, isPrimary: false, isSensor: false, isDetailOnly: true),
        .init(name: "Camera", synonyms: ["camera", "cctv"], order: 13, isPrimary: false, isSensor: false, isDetailOnly: true),
        .init(name: "Sensor", synonyms: ["sensor"], order: 14, isPrimary: false, isSensor: true, isDetailOnly: true),
        .init(name: "Lock", synonyms: ["lock", "door lock"], order: 15, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Garage", synonyms: ["garage", "garage door"], order: 16, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Fan", synonyms: ["fan", "ceiling fan"], order: 17, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "AC", synonyms: ["ac", "aircon", "air conditioner"], order: 18, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Heater", synonyms: ["heater", "heat"], order: 19, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Washer", synonyms: ["washer", "washing machine"], order: 20, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Dryer", synonyms: ["dryer"], order: 21, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Humidifier", synonyms: ["humidifier"], order: 22, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Dehumidifier", synonyms: ["dehumidifier"], order: 23, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Air Purifier", synonyms: ["air purifier", "purifier"], order: 24, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Irrigation", synonyms: ["irrigation", "sprinkler"], order: 25, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Pool", synonyms: ["pool"], order: 26, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Siren", synonyms: ["siren"], order: 27, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Oven", synonyms: ["oven"], order: 28, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Stove", synonyms: ["stove", "cooktop"], order: 29, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Dishwasher", synonyms: ["dishwasher"], order: 30, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Fridge", synonyms: ["fridge", "refrigerator", "freezer"], order: 31, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Microwave", synonyms: ["microwave"], order: 32, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Water Heater", synonyms: ["water heater", "geyser"], order: 33, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Valve", synonyms: ["valve"], order: 34, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Pump", synonyms: ["pump"], order: 35, isPrimary: true, isSensor: false, isDetailOnly: false),
        .init(name: "Scene", synonyms: ["scene"], order: 36, isPrimary: false, isSensor: false, isDetailOnly: true),
        .init(name: "Group", synonyms: ["group"], order: 37, isPrimary: false, isSensor: false, isDetailOnly: true),
    ]

    private static let lookup: [String: LabelMeta] = {
        var dict: [String: LabelMeta] = [:]
        for meta in metas {
            dict[meta.name.lowercased()] = meta
            for s in meta.synonyms {
                dict[s.lowercased()] = meta
            }
        }
        return dict
    }()

    // Kiosk dashboard primary device whitelist.
    private static let primaryAllowed: Set<String> = [
        "Light",
        "Blind",
        "Motion Sensor",
        "Spotify",
        "Boiler",
        "Doorbell",
        "Home Security",
        "TV",
        "Speaker"
    ]

    static var orderedLabels: [String] {
        metas.sorted { $0.order < $1.order }.map { $0.name }
    }

    static func resolve(_ raw: String?) -> LabelMeta? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return lookup[trimmed.lowercased()]
    }

    static func canonical(from raw: String?) -> String? {
        resolve(raw)?.name
    }

    static func isPrimary(label: String?) -> Bool {
        guard let canonical = canonical(from: label) else { return false }
        return primaryAllowed.contains(canonical)
    }

    static func isSensor(label: String?) -> Bool {
        resolve(label)?.isSensor ?? false
    }

    static func isDetailOnly(label: String?) -> Bool {
        resolve(label)?.isDetailOnly ?? false
    }

    static func groupLabel(for label: String) -> String {
        guard let meta = resolve(label) else { return label }
        return meta.name
    }

    static func sortLabels(_ labels: [String]) -> [String] {
        labels.sorted { a, b in
            let metaA = resolve(a)
            let metaB = resolve(b)
            if let orderA = metaA?.order, let orderB = metaB?.order, orderA != orderB {
                return orderA < orderB
            }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }
}
