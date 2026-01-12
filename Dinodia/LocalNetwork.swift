import Foundation

enum LocalNetwork {
    static func isLocalHost(_ host: String) -> Bool {
        let lower = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty { return false }
        if lower == "localhost" { return true }
        if lower.hasSuffix(".local") || lower.hasSuffix(".lan") { return true }
        if lower == "127.0.0.1" { return true }
        if lower == "169.254.0.0" || lower.hasPrefix("169.254.") { return true }
        return isPrivateIPv4(lower)
    }

    private static func isPrivateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }

        let a = octets[0], b = octets[1]
        if a == 10 { return true }
        if a == 192 && b == 168 { return true }
        if a == 172 && (16...31).contains(b) { return true }
        if a == 127 { return true }
        if a == 169 && b == 254 { return true } // link-local
        return false
    }
}

