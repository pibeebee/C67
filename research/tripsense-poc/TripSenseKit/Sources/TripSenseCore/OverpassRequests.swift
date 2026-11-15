import Foundation
import CryptoKit

/// Shared across provider instances so a new Generate operation cannot bypass server cooldown.
@MainActor public final class OSMRequestGate {
    public static let shared = OSMRequestGate()
    private let now: @MainActor () -> Date
    private var blockedUntil: [String: Date] = [:]
    private var active: Set<String> = []
    public init(now: @escaping @MainActor () -> Date = { Date() }) { self.now = now }
    private func key(_ endpoint: URL) -> String {
        "\(endpoint.scheme?.lowercased() ?? "")://\(endpoint.host?.lowercased() ?? ""):\(endpoint.port ?? (endpoint.scheme?.lowercased() == "http" ? 80 : 443))"
    }
    func acquire(_ endpoint: URL) throws {
        let key = key(endpoint)
        if let date = blockedUntil[key], date > now() { throw HoursServiceError.cooldown(date) }
        guard !active.contains(key) else { throw HoursServiceError.busy }
        active.insert(key)
    }
    func release(_ endpoint: URL) { active.remove(key(endpoint)) }
    @discardableResult func reject(_ endpoint: URL, retryAfter: String?) -> Date {
        let current = now()
        let minimum = current.addingTimeInterval(30)
        let requested = Self.retryDate(retryAfter, now: current) ?? minimum
        let date = max(blockedUntil[key(endpoint)] ?? minimum, max(minimum, requested))
        blockedUntil[key(endpoint)] = date
        return date
    }
    static func retryDate(_ header: String?, now: Date) -> Date? {
        guard let value = header?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.utf8.allSatisfy({ (48 ... 57).contains($0) }), let seconds = Double(value), seconds.isFinite {
            if seconds >= Date.distantFuture.timeIntervalSince(now) { return .distantFuture }
            let date = now.addingTimeInterval(seconds)
            return date.timeIntervalSince1970.isFinite ? date : nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        for pattern in ["EEE, dd MMM yyyy HH:mm:ss 'GMT'", "EEEE, dd-MMM-yy HH:mm:ss 'GMT'", "EEE MMM d HH:mm:ss yyyy"] {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

enum HoursServiceError: Error, Sendable {
    case httpStatus(Int, retryAfter: String?)
    case cooldown(Date)
    case busy
}

enum OverpassHTTP {
    static let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!
    static let userAgent = "TripSensePOC/0.1 (native iOS-macOS opening-hours research prototype)"
    static let timeout: TimeInterval = 60
    static func request(endpoint: URL, query: String) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        var encoded = URLComponents(); encoded.queryItems = [URLQueryItem(name: "data", value: query)]
        request.httpBody = encoded.percentEncodedQuery?.data(using: .utf8)
        return request
    }
    static func load(_ request: URLRequest) async throws -> (Data, Int) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200 ... 299).contains(http.statusCode) else {
            throw HoursServiceError.httpStatus(http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 2_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return (data, http.statusCode)
    }
}

/// The same fixed public query and request builder are used on Mac and iPhone.
/// No current location, account, IP address or network identifier is collected.
public enum OSMNetworkProbe {
    @MainActor public static func run() async -> String {
        let endpoint = OverpassHTTP.endpoint
        let query = "[out:json][timeout:20];nwr(around:150,-6.1754,106.8272)[name];out center;"
        let request = OverpassHTTP.request(endpoint: endpoint, query: query)
        let hash = SHA256.hash(data: request.httpBody ?? Data()).map { String(format: "%02x", $0) }.joined()
        let began = Date()
        var lines = ["TripSense Overpass network probe", "Started UTC: \(began.ISO8601Format())",
                     "OS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
                     "Endpoint: \(endpoint.absoluteString)", "Method: POST", "Body SHA256: \(hash)",
                     "User-Agent: \(OverpassHTTP.userAgent)", "Network timeout: 60s; Overpass execution timeout: 20s"]
        do {
            try OSMRequestGate.shared.acquire(endpoint)
            defer { OSMRequestGate.shared.release(endpoint) }
            let (data, status) = try await OverpassHTTP.load(request)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let elements = object?["elements"] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
            lines.append("HTTP: \(status); valid OSM elements: \(elements.count); bytes: \(data.count)")
            lines.append("Transport verified. This probe does not verify any venue's opening hours.")
        } catch HoursServiceError.httpStatus(let status, let retryAfter) {
            lines.append("HTTP: \(status)")
            if status == 406 || status == 429 || (status == 503 && retryAfter != nil) {
                let date = OSMRequestGate.shared.reject(endpoint, retryAfter: retryAfter)
                lines.append("Next permitted request UTC: \(date.ISO8601Format())")
            }
            lines.append("Hours remain unknown; no automatic retry.")
        } catch HoursServiceError.cooldown(let date) {
            lines.append("Cooldown until UTC: \(date.ISO8601Format()); no request sent.")
        } catch HoursServiceError.busy {
            lines.append("Another OSM request is active; no request sent.")
        } catch {
            let failure = error as NSError
            lines.append("Failure: \(failure.domain) \(failure.code); hours unknown.")
        }
        lines.append("Elapsed seconds: \(String(format: "%.2f", Date().timeIntervalSince(began)))")
        return lines.joined(separator: "\n")
    }
}
