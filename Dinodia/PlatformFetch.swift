import Foundation

enum PlatformFetchError: LocalizedError {
    case invalidBaseURL
    case invalidPath
    case http(Int, String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Platform API is not configured. Please try again later."
        case .invalidPath:
            return "Invalid request."
        case .http(_, let message):
            return message
        case .network(let message):
            return message
        }
    }
}

struct PlatformFetchResult<T: Decodable> {
    let data: T
    let response: HTTPURLResponse
}

enum PlatformFetch {
    private static func baseURL() -> URL? {
        return EnvConfig.dinodiaPlatformAPI
    }

    static func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> PlatformFetchResult<T> {
        guard let base = baseURL() else { throw PlatformFetchError.invalidBaseURL }
        guard path.hasPrefix("/") else { throw PlatformFetchError.invalidPath }
        guard let url = URL(string: path, relativeTo: base) else { throw PlatformFetchError.invalidPath }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body

        var finalHeaders: [String: String] = [
            "Content-Type": "application/json",
        ]
        headers.forEach { finalHeaders[$0.key] = $0.value }

        if let token = PlatformTokenStore.get(), !token.isEmpty {
            finalHeaders["Authorization"] = "Bearer \(token)"
            let identity = DeviceIdentity.shared
            finalHeaders["x-device-id"] = identity.deviceId
            finalHeaders["x-device-label"] = identity.deviceLabel
        }

        finalHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PlatformFetchError.network("Unable to reach Dinodia servers. Please try again.")
            }

            if http.statusCode == 401 {
                SessionInvalidation.triggerOnce()
                throw PlatformFetchError.http(http.statusCode, "Session expired, please log in again.")
            }

            if !(200...299).contains(http.statusCode) {
                let text = String(data: data, encoding: .utf8) ?? ""
                let message = !text.isEmpty ? text : "HTTP \(http.statusCode) while calling platform API"
                if http.statusCode == 403 {
                    throw PlatformFetchError.http(http.statusCode, message)
                }
                throw PlatformFetchError.http(http.statusCode, message)
            }

            if T.self == Empty.self {
                // swiftlint:disable:next force_cast
                return PlatformFetchResult(data: Empty() as! T, response: http)
            }

            let payload: Data
            if data.isEmpty {
                // Some endpoints return 204/empty bodies; decode from an empty JSON object for optionals.
                payload = "{}".data(using: .utf8) ?? Data()
            } else {
                payload = data
            }
            let decoded = try JSONDecoder().decode(T.self, from: payload)
            return PlatformFetchResult(data: decoded, response: http)
        } catch let error as PlatformFetchError {
            throw error
        } catch {
            if error.isCancellation { throw CancellationError() }
            throw PlatformFetchError.network(error.localizedDescription.isEmpty ? "Unable to reach Dinodia servers. Please try again." : error.localizedDescription)
        }
    }
}

// Helper to satisfy Decodable when no body is needed.
struct Empty: Decodable {}
