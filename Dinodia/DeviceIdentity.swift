import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct DeviceIdentity {
    let deviceId: String
    let deviceLabel: String

    static let shared = DeviceIdentity()

    private init() {
        let defaults = UserDefaults.standard
        let key = "dinodia_device_id_v1"
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            deviceId = existing
        } else {
            let newId = UUID().uuidString
            defaults.set(newId, forKey: key)
            deviceId = newId
        }
        #if canImport(UIKit)
        let rawName = UIKit.UIDevice.current.name
        #else
        let rawName = Host.current().localizedName ?? ""
        #endif
        let name = rawName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        deviceLabel = name.isEmpty ? "iOS Device" : name
    }
}
