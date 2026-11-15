import Foundation

enum WeatherLabLaunchRouting {
    static func showsLab(arguments: [String]) -> Bool {
        if arguments.contains("--weather-lab") || arguments.contains("--weather-lab-ui-testing") { return true }
        return !arguments.contains { ["--native-itinerary", "--jakarta-ui-testing", "--active-ui-testing"].contains($0) }
    }
}

struct WeatherLabPoint: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var coordinateKey: String { "\(latitude),\(longitude)" }

    func distance(to other: Self) -> Double {
        let scale = Double.pi / 180
        let a = latitude * scale, b = other.latitude * scale
        let x = sin((b - a) / 2), y = sin((other.longitude - longitude) * scale / 2)
        let h = min(1, max(0, x * x + cos(a) * cos(b) * y * y))
        return 6_371_000 * 2 * atan2(sqrt(h), sqrt(1 - h))
    }

    static let samples: [Self] = [
        .init(id: "sudirman", name: "Sudirman", latitude: -6.2023912, longitude: 106.8234359),
        .init(id: "monas", name: "Monas", latitude: -6.1753936, longitude: 106.827186),
        .init(id: "kota-tua", name: "Kota Tua", latitude: -6.1347997, longitude: 106.8130414),
        .init(id: "glodok", name: "Glodok", latitude: -6.1434347, longitude: 106.815066),
        .init(id: "ashta", name: "Ashta", latitude: -6.229714, longitude: 106.807101),
        .init(id: "blok-m", name: "Blok M", latitude: -6.2445743, longitude: 106.8006164),
    ]
}

struct WeatherLabGroup: Identifiable, Codable, Sendable {
    var representative: WeatherLabPoint
    var members: [WeatherLabPoint]
    var id: String { representative.coordinateKey }
    var maximumDistance: Double { members.map { representative.distance(to: $0) }.max() ?? 0 }

    /// Stable representative, bounded radius. A–B–C proximity never chains a distant C into A.
    static func make(_ points: [WeatherLabPoint], radius: Double = 3_000) throws -> [Self] {
        guard radius.isFinite, radius > 0, !points.isEmpty, points.count <= 22,
              Set(points.map(\.id)).count == points.count,
              points.allSatisfy({ $0.latitude.isFinite && $0.longitude.isFinite
                      && (-6.40 ... -6.08).contains($0.latitude) && (106.68 ... 107.00).contains($0.longitude) })
        else { throw WeatherLabError.invalidInput }
        let sorted = points.sorted {
            if $0.latitude != $1.latitude { return $0.latitude < $1.latitude }
            if $0.longitude != $1.longitude { return $0.longitude < $1.longitude }
            return $0.id < $1.id
        }
        var groups: [Self] = []
        for point in sorted {
            if let index = groups.indices.filter({ groups[$0].representative.distance(to: point) <= radius })
                .min(by: { groups[$0].representative.distance(to: point) < groups[$1].representative.distance(to: point) }) {
                groups[index].members.append(point)
            } else { groups.append(.init(representative: point, members: [point])) }
        }
        return groups
    }
}

struct WeatherLabWindow: Codable, Equatable, Sendable {
    var start: Date
    var end: Date
    func validate() throws {
        guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              end > start, end.timeIntervalSince(start) <= 24 * 3_600 else { throw WeatherLabError.invalidInput }
    }
    var hourly: Self {
        .init(start: Date(timeIntervalSince1970: floor(start.timeIntervalSince1970 / 3_600) * 3_600),
              end: Date(timeIntervalSince1970: ceil(end.timeIntervalSince1970 / 3_600) * 3_600))
    }
}

enum WeatherLabMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic, weatherKitOnly, openMeteoOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "WeatherKit + cadangan"
        case .weatherKitOnly: "WeatherKit saja"
        case .openMeteoOnly: "Open-Meteo saja"
        }
    }
}

enum WeatherLabError: LocalizedError {
    case invalidInput, timeout, authentication(String), incomplete, missingCredit
    var errorDescription: String? {
        switch self {
        case .invalidInput: "Pilih 1–22 titik Jakarta dan rentang waktu positif maksimal 24 jam."
        case .timeout: "Batas waktu provider tercapai."
        case .authentication(let detail): "Autentikasi WeatherKit gagal: \(detail)"
        case .incomplete: "Provider belum menyediakan seluruh jam yang diminta."
        case .missingCredit: "Atribusi Apple Weather belum tersedia."
        }
    }
    static func isAuthentication(_ error: Error) -> Bool {
        if case WeatherLabError.authentication = error { return true }
        var current: NSError? = error as NSError
        for _ in 0 ..< 5 {
            guard let value = current else { break }
            // Observed auth-service failures, rather than treating every error 0/2 as authentication.
            // A proxy failure does not establish which account/capability/provisioning setting is wrong.
            if value.domain == "WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors", value.code == 2 { return true }
            if value.domain == "WeatherDaemon.WDSJWTAuthenticatorServiceProxy.Errors", value.code == 0 { return true }
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled
    }
    static func diagnostic(_ error: Error) -> String {
        var current: NSError? = error as NSError, chain: [String] = []
        for _ in 0 ..< 5 {
            guard let value = current else { break }
            chain.append("\(String(value.localizedDescription.prefix(350))) [\(value.domain):\(value.code)]")
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return chain.joined(separator: " → ")
    }
}

struct WeatherLabPayload: Codable, Sendable {
    var forecast: NativeTripForecast
    var expiresAt: Date
    var credit: NativeTripWeatherCredit?

    func covers(_ window: WeatherLabWindow) -> Bool {
        let range = window.hourly
        var cursor = range.start
        while cursor < range.end {
            guard forecast.hours.contains(where: {
                abs($0.date.timeIntervalSince(cursor)) < 1 && $0.rainChance.isFinite
                    && (0 ... 1).contains($0.rainChance)
            }) else { return false }
            cursor = cursor.addingTimeInterval(3_600)
        }
        return cursor > range.start
    }
}

struct WeatherLabResult: Identifiable, Codable, Sendable {
    var group: WeatherLabGroup
    var payload: WeatherLabPayload?
    var cached: Bool = false
    var notes: [String] = []
    var id: String { group.id }
}

struct WeatherLabStats: Codable, Sendable {
    var weatherKitRequests = 0
    var openMeteoRequests = 0
    var cacheHits = 0
    var maxConcurrentGroups = 0
    var elapsedSeconds = 0.0
}

struct WeatherLabEvent: Identifiable, Codable, Sendable {
    var id = UUID()
    var date = Date()
    var message: String
}

@MainActor protocol WeatherLabProvider {
    func fetch(_ provider: NativeTripWeatherProvider, point: WeatherLabPoint,
               window: WeatherLabWindow) async throws -> WeatherLabPayload
}

/// The continuation is settled once. A provider ignoring cancellation cannot delay the UI deadline
/// or publish/cache its late response. Unstructured worker tasks own no model/cache mutations.
@MainActor private final class WeatherLabRace<T> {
    var continuation: CheckedContinuation<T, Error>?
    var outcome: Result<T, Error>?
    var worker: Task<Void, Never>?
    var timer: Task<Void, Never>?
    func finish(_ result: Result<T, Error>) {
        guard outcome == nil else { return }
        outcome = result
        worker?.cancel(); timer?.cancel()
        continuation?.resume(with: result); continuation = nil
    }
    func attach(_ value: CheckedContinuation<T, Error>) {
        if let outcome { value.resume(with: outcome) } else { continuation = value }
    }
}

@MainActor enum WeatherLabDeadline {
    static func run<T>(seconds: Double, operation: @escaping @MainActor () async throws -> T) async throws -> T {
        let race = WeatherLabRace<T>()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                race.attach(continuation)
                race.worker = Task { @MainActor in
                    do { race.finish(.success(try await operation())) }
                    catch { race.finish(.failure(error)) }
                }
                race.timer = Task { @MainActor in
                    do {
                        try await Task.sleep(nanoseconds: UInt64(max(0.001, seconds) * 1_000_000_000))
                        race.finish(.failure(WeatherLabError.timeout))
                    } catch { /* settled or cancelled */ }
                }
            }
        } onCancel: { Task { @MainActor in race.finish(.failure(CancellationError())) } }
    }
}

@MainActor final class WeatherLabEngine {
    private struct Entry {
        var pointKey: String
        var provider: NativeTripWeatherProvider
        var payload: WeatherLabPayload
    }
    private let service: any WeatherLabProvider
    private let now: () -> Date
    private let timeout: Double
    private var cache: [Entry] = []
    private(set) var authenticationBlocked = false
    private(set) var stats = WeatherLabStats()
    private var activeGroups = 0
    private var activeRun: UUID?
    var onEvent: ((String) -> Void)?
    var cacheCount: Int { cache.filter { $0.payload.expiresAt > now() }.count }

    init(service: any WeatherLabProvider, timeout: Double = 8, now: @escaping () -> Date = Date.init) {
        self.service = service; self.timeout = timeout; self.now = now
    }
    func resetAuthentication() { authenticationBlocked = false; onEvent?("Pemutus autentikasi direset secara eksplisit.") }
    func clearCache() { cache.removeAll(); onEvent?("Cache eksperimen dikosongkan.") }

    func run(groups: [WeatherLabGroup], window: WeatherLabWindow, mode: WeatherLabMode,
             probe: Bool = false, refresh: Bool = false,
             onResult: @escaping (WeatherLabResult) -> Void = { _ in }) async throws -> [WeatherLabResult] {
        try window.validate()
        guard activeRun == nil, !groups.isEmpty else { throw WeatherLabError.invalidInput }
        let run = UUID(), started = now()
        activeRun = run; stats = .init(); activeGroups = 0
        defer { stats.elapsedSeconds = max(0, now().timeIntervalSince(started)); activeRun = nil }
        let requested = probe ? Array(groups.prefix(1)) : groups
        var results: [WeatherLabResult] = []
        // First group tests authorization before launching more WeatherKit work.
        let first = try await resolve(requested[0], window: window, mode: probe ? .weatherKitOnly : mode,
                                      bypass: probe || refresh, probe: probe)
        try Task.checkCancellation(); results.append(first); onResult(first)
        var index = 1
        while index < requested.count {
            try Task.checkCancellation()
            let batch = Array(requested[index ..< min(index + 2, requested.count)])
            try await withThrowingTaskGroup(of: WeatherLabResult.self) { tasks in
                for group in batch {
                    tasks.addTask { @MainActor in
                        try await self.resolve(group, window: window, mode: mode, bypass: refresh, probe: false)
                    }
                }
                for try await result in tasks {
                    try Task.checkCancellation(); results.append(result); onResult(result)
                }
            }
            index += batch.count
        }
        return requested.compactMap { group in results.first { $0.id == group.id } }
    }

    private func resolve(_ group: WeatherLabGroup, window: WeatherLabWindow, mode: WeatherLabMode,
                         bypass: Bool, probe: Bool) async throws -> WeatherLabResult {
        try Task.checkCancellation()
        activeGroups += 1; stats.maxConcurrentGroups = max(stats.maxConcurrentGroups, activeGroups)
        defer { activeGroups -= 1 }
        let providers: [NativeTripWeatherProvider] = mode == .automatic ? [.weatherKit, .openMeteo]
            : [mode == .weatherKitOnly ? .weatherKit : .openMeteo]
        var result = WeatherLabResult(group: group)
        for provider in providers {
            try Task.checkCancellation()
            cache.removeAll { $0.payload.expiresAt <= now() }
            if !bypass, let entry = cache.last(where: {
                $0.pointKey == group.id && $0.provider == provider && $0.payload.covers(window)
            }) {
                result.payload = entry.payload; result.cached = true; stats.cacheHits += 1
                onEvent?("\(group.representative.name): cache \(provider.title).")
                return result
            }
            if provider == .weatherKit && authenticationBlocked && !probe {
                result.notes.append("WeatherKit dilewati: autentikasi diblokir untuk sesi ini.")
                continue
            }
            do {
                let payload = try await WeatherLabDeadline.run(seconds: timeout) { [self] in
                    var attempt = 0
                    while true {
                        try Task.checkCancellation()
                        if provider == .weatherKit { stats.weatherKitRequests += 1 }
                        else { stats.openMeteoRequests += 1 }
                        onEvent?("\(group.representative.name): meminta \(provider.title), percobaan \(attempt + 1).")
                        do { return try await service.fetch(provider, point: group.representative, window: window.hourly) }
                        catch {
                            if WeatherLabError.isCancellation(error) { throw CancellationError() }
                            let retryable = (error as? URLError).map { [.networkConnectionLost, .timedOut].contains($0.code) } ?? false
                            guard retryable, attempt == 0, !probe else { throw error }
                            attempt += 1
                            try await Task.sleep(nanoseconds: 200_000_000)
                        }
                    }
                }
                try Task.checkCancellation()
                guard payload.covers(window) else { throw WeatherLabError.incomplete }
                guard provider != .weatherKit || payload.credit != nil else { throw WeatherLabError.missingCredit }
                var accepted = payload
                accepted.forecast.provider = provider
                accepted.forecast.pointID = group.representative.id
                accepted.forecast.retrievedAt = accepted.forecast.retrievedAt ?? now()
                accepted.expiresAt = min(payload.expiresAt, accepted.forecast.retrievedAt!.addingTimeInterval(900))
                guard accepted.expiresAt > now() else { throw WeatherLabError.incomplete }
                if provider == .weatherKit { authenticationBlocked = false }
                result.payload = accepted
                if !probe {
                    cache.removeAll { $0.pointKey == group.id && $0.provider == provider && $0.payload.covers(window) }
                    cache.append(.init(pointKey: group.id, provider: provider, payload: accepted))
                    if cache.count > 128 { cache.removeFirst(cache.count - 128) }
                }
                onEvent?("\(group.representative.name): \(provider.title) tersedia.")
                return result
            } catch {
                if WeatherLabError.isCancellation(error) { throw CancellationError() }
                if provider == .weatherKit && WeatherLabError.isAuthentication(error) { authenticationBlocked = true }
                let detail = "\(provider.title): \(WeatherLabError.diagnostic(error))"
                result.notes.append(detail); onEvent?("\(group.representative.name): \(detail)")
            }
        }
        onEvent?("\(group.representative.name): prakiraan belum diketahui; tidak dianggap 0% hujan.")
        return result
    }
}
