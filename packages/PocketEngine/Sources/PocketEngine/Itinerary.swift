import Foundation

public struct TripInput: Sendable {
    public var departure: Date
    public var deadline: Date
    public var origin: Coordinate
    public var returnToOrigin: Bool
    public var maxWaitMinutes: Int
    public var avoidRain: Bool
    public var latestDeparture: Date?
    public var lastVenueID: String?
    public var maximumStops: Int
    public var minimumStops: Int
    public var preservesOrder: Bool
    public var firstVenueID: String?
    public init(departure: Date, deadline: Date, origin: Coordinate, returnToOrigin: Bool,
                maxWaitMinutes: Int, avoidRain: Bool, latestDeparture: Date? = nil,
                lastVenueID: String? = nil, minimumStops: Int = 1, maximumStops: Int = 6,
                preservesOrder: Bool = false, firstVenueID: String? = nil) {
        self.departure = departure; self.deadline = deadline; self.origin = origin
        self.returnToOrigin = returnToOrigin; self.maxWaitMinutes = maxWaitMinutes; self.avoidRain = avoidRain
        self.latestDeparture = latestDeparture; self.lastVenueID = lastVenueID; self.minimumStops = minimumStops; self.maximumStops = maximumStops
        self.preservesOrder = preservesOrder; self.firstVenueID = firstVenueID
    }
}
public struct LegQuote: Sendable {
    public var seconds: Double
    public var meters: Double
    public init(seconds: Double, meters: Double) { self.seconds = seconds; self.meters = meters }
}
public enum TravelQuoteError: Error, Sendable {
    case temporary(retryAfter: Duration)
    case throttled
}
public struct WeatherReading: Sendable {
    public var maxRainChance: Double?
    public var summary: String
    public init(maxRainChance: Double?, summary: String) { self.maxRainChance = maxRainChance; self.summary = summary }
}
public struct ScheduledStop: Codable, Identifiable, Sendable {
    public var venueID: String
    public var name: String
    public var coordinate: Coordinate
    public var departure: Date
    public var arrival: Date
    public var visitStart: Date
    public var visitEnd: Date
    public var driveSeconds: Double
    public var distanceMeters: Double
    public var evidence: String
    public var weather: String
    public var id: String { venueID }
}
public struct Itinerary: Codable, Identifiable, Sendable {
    public var id: UUID
    public var generatedAt: Date
    public var departure: Date
    public var finish: Date
    public var origin: Coordinate
    public var returnToOrigin: Bool
    public var returnSeconds: Double
    public var stops: [ScheduledStop]
    public var omitted: [String]
    public var warnings: [String]
    public var etaRequests: Int
    public var searchTruncated: Bool
}

public enum PlanningEvent: Sendable {
    case firstSchedule(Duration)
    case etaAttempt(number: Int, elapsed: Duration, succeeded: Bool)
    case etaCacheHit
    case etaRetry
    case finished(Duration)
}

public enum ItineraryPlanner {
    public typealias Travel = @Sendable (Coordinate, Coordinate, Date) async throws -> LegQuote
    public typealias Weather = @Sendable (Coordinate, Date, Date) async throws -> WeatherReading
    public static func make(input: TripInput, choices: [StopChoice], venues: [Venue], profile: Profile,
                            travel: @escaping Travel, weather: @escaping Weather, budget: Int = 60,
                            report: @escaping @Sendable (PlanningEvent) -> Void = { _ in }) async throws -> Itinerary {
        let options = try await makeOptions(input: input, choices: choices, venues: venues, profile: profile,
                                            travel: travel, weather: weather, budget: budget, report: report)
        return options[0]
    }
    public static func makeOptions(input: TripInput, choices: [StopChoice], venues: [Venue], profile: Profile,
                                   travel: @escaping Travel, weather: @escaping Weather, budget: Int = 60,
                                   report: @escaping @Sendable (PlanningEvent) -> Void = { _ in }) async throws -> [Itinerary] {
        let started = ContinuousClock.now
        defer { report(.finished(started.duration(to: .now))) }
        guard input.origin.valid, input.deadline > input.departure,
              TripClock.day(input.departure) == TripClock.day(input.deadline),
              (0 ... 120).contains(input.maxWaitMinutes), !choices.isEmpty, choices.count <= 6,
              (1 ... choices.count).contains(input.minimumStops),
              (input.minimumStops ... 6).contains(input.maximumStops),
              Set(choices.map(\.venueID)).count == choices.count, (1 ... 120).contains(budget),
              input.latestDeparture.map({ $0 >= input.departure && $0 <= input.deadline }) ?? true,
              input.lastVenueID.map({ id in choices.contains { $0.venueID == id } }) ?? true,
              input.firstVenueID.map({ id in choices.contains { $0.venueID == id } }) ?? true,
              Set(venues.map(\.id)).count == venues.count else {
            throw EngineError.invalid("Gunakan 1–6 tujuan, satu hari WIB, dan batas pulang setelah keberangkatan.")
        }
        let lookup = Dictionary(uniqueKeysWithValues: venues.map { ($0.id, $0) })
        let pairs = try choices.map { choice -> (StopChoice, Venue) in
            guard let venue = lookup[choice.venueID], venue.coordinate.valid, (15 ... 240).contains(choice.durationMinutes),
                  choice.timing.map({ (0 ..< 1440).contains($0.minute) }) ?? true else {
                throw EngineError.invalid("Tujuan atau durasi kunjungan tidak valid.")
            }
            return (choice, venue)
        }
        let mandatoryCount = pairs.filter { choice, venue in
            if choice.required || venue.id == input.lastVenueID { return true }
            if case .required = choice.timing { return true }
            return false
        }.count
        guard mandatoryCount <= input.maximumStops else {
            throw EngineError.invalid("Jumlah tujuan wajib melebihi target kunjungan. Tambah target atau ubah tujuan wajib.")
        }
        return try await PlanningSearch(input: input, pairs: pairs, profile: profile, travel: travel, weather: weather, budget: budget, started: started, report: report).run()
    }
}

private actor PlanningSearch {
    let input: TripInput
    let pairs: [(StopChoice, Venue)]
    let profile: Profile
    let travel: ItineraryPlanner.Travel
    let weather: ItineraryPlanner.Weather
    let budget: Int
    let started: ContinuousClock.Instant
    let report: @Sendable (PlanningEvent) -> Void
    struct LegKey: Hashable {
        let from: Coordinate
        let to: Coordinate
        let departure: Date
    }

    let checkedAt = Date()
    let day: Date
    let required: Set<String>
    var calls = 0
    var retries = 0
    var examined = 0
    var callLimit: Int
    var interrupted = false
    var truncated = false
    var throttled = false
    var options: [(plan: Itinerary, penalty: Double)] = []
    var best: Itinerary?
    var bestTimingPenalty = Double.infinity
    var failures = Set<String>()
    var quotes: [LegKey: LegQuote] = [:]
    var unavailable = Set<LegKey>()

    init(input: TripInput, pairs: [(StopChoice, Venue)], profile: Profile, travel: @escaping ItineraryPlanner.Travel,
         weather: @escaping ItineraryPlanner.Weather, budget: Int, started: ContinuousClock.Instant,
         report: @escaping @Sendable (PlanningEvent) -> Void) {
        self.started = started
        self.report = report
        self.input = input; self.pairs = pairs; self.profile = profile; self.travel = travel; self.weather = weather; self.budget = budget
        day = TripClock.calendar.startOfDay(for: input.departure)
        required = Set(pairs.compactMap { choice, venue in
            if choice.required || venue.id == input.lastVenueID { return venue.id }
            if case .required = choice.timing { return venue.id }
            return nil
        })
        callLimit = budget
    }

    func run() async throws -> [Itinerary] {
        let departures = departureCandidates()
        for (index, departure) in departures.enumerated() {
            if throttled || examined >= 800 { break }
            if calls >= budget { truncated = true; break }
            interrupted = false
            let remainingStarts = departures.count - index
            let legCount = max(required.count, input.minimumStops) + (input.returnToOrigin ? 1 : 0)
            callLimit = min(budget, calls + max(legCount, (budget - calls) / remainingStarts))
            try await visit(path: [], used: [], location: input.origin, time: departure, departure: departure)
            if best?.stops.count == min(pairs.count, input.maximumStops) && bestTimingPenalty == 0 && departures.count > 1 {
                if remainingStarts > 1 { truncated = true }
                break
            }
        }
        try Task.checkCancellation()
        guard var result = best else {
            let details = failures.sorted().prefix(6).joined(separator: "\n")
            let limit = truncated ? "\nBatas pencarian tercapai; ini bukan bukti tidak ada solusi." : ""
            throw EngineError.invalid("Belum ditemukan jadwal yang memenuhi seluruh tujuan wajib dan batas perjalanan.\n" + details + limit)
        }
        let selected = Set(result.stops.map(\.venueID))
        result.etaRequests = calls; result.searchTruncated = truncated
        result.omitted = pairs.filter { !selected.contains($0.1.id) }.map { pair in
            let reason = failures.sorted().first { $0.hasPrefix(pair.1.name + ":") }
            return reason ?? pair.1.name + ": tidak terpilih dalam pencarian terbatas."
        }
        result.warnings = ["ETA adalah perkiraan Apple Maps pada waktu tiap ruas; kondisi nyata dapat berubah.",
                           "Jam reguler belum membuktikan pengecualian hari libur atau slot reservasi."]
        if truncated { result.warnings.append("Sebagian alternatif belum diperiksa; maksimum \(budget) permintaan ETA dan 800 cabang.") }
        if throttled { result.warnings.append("Apple Maps membatasi permintaan ETA; alternatif belum diperiksa.") }
        for (choice, venue) in pairs {
            guard case .preferred(let minute) = choice.timing,
                  let visit = result.stops.first(where: { $0.venueID == venue.id }),
                  abs(visit.visitStart.timeIntervalSince(at(minute))) >= 60 else { continue }
            result.warnings.append("\(venue.name): mulai \(TripClock.time(visit.visitStart)), preferensi \(TripClock.time(at(minute))).")
        }
        // Every option was built by this same search and uses the same shared ETA budget.
        return options.filter { $0.plan.stops.count == result.stops.count }.map { entry in
            var option = entry.plan
            option.etaRequests = calls; option.searchTruncated = truncated
            let selected = Set(option.stops.map(\.venueID))
            option.omitted = pairs.filter { !selected.contains($0.1.id) }.map { pair in
                failures.sorted().first { $0.hasPrefix(pair.1.name + ":") } ?? pair.1.name + ": tidak terpilih dalam pencarian terbatas."
            }
            option.warnings = result.warnings.filter { !$0.contains(": mulai ") }
            for (choice, venue) in pairs {
                guard case .preferred(let minute) = choice.timing,
                      let visit = option.stops.first(where: { $0.venueID == venue.id }),
                      abs(visit.visitStart.timeIntervalSince(at(minute))) >= 60 else { continue }
                option.warnings.append("\(venue.name): mulai \(TripClock.time(visit.visitStart)), preferensi \(TripClock.time(at(minute))).")
            }
            return option
        }
    }

    func at(_ minute: Int) -> Date { day.addingTimeInterval(Double(minute * 60)) }

    func departureCandidates() -> [Date] {
        guard let latest = input.latestDeparture, latest > input.departure else { return [input.departure] }
        var candidates: [Date] = []
        func add(_ value: Date) {
            let clamped = min(max(value, input.departure), latest)
            if !candidates.contains(clamped) { candidates.append(clamped) }
        }
        let timed = pairs.compactMap { choice, venue in choice.timing.map { ($0.minute, venue.id) } }
            .sorted { $0.0 < $1.0 }
        for (minute, id) in timed.prefix(2) {
            let target = at(minute)
            let preceding: Int
            if id == input.lastVenueID {
                let others = pairs.filter { $0.1.id != id }.sorted {
                    let a = required.contains($0.1.id), b = required.contains($1.1.id)
                    return a != b ? a : $0.0.durationMinutes < $1.0.durationMinutes
                }
                preceding = others.prefix(max(0, input.maximumStops - 1)).reduce(0) { $0 + $1.0.durationMinutes }
            } else { preceding = 0 }
            for lead in [15, 30, 5] { add(target.addingTimeInterval(-Double((preceding + lead) * 60))) }
        }
        add(input.departure)
        let openings = pairs.filter { required.contains($0.1.id) }.compactMap { choice, venue in
            openingWindows(choice, venue).first { $0.end > input.departure }?.start
        }.sorted()
        for opening in openings.prefix(2) { add(opening.addingTimeInterval(-900)) }
        let span = latest.timeIntervalSince(input.departure)
        for fraction in [0.5, 0.75] { add(input.departure.addingTimeInterval(span * fraction)) }
        add(latest)
        return Array(candidates.prefix(8))
    }

    func quote(from: Coordinate, to: Coordinate, at date: Date) async throws -> LegQuote? {
        let key = LegKey(from: from, to: to, departure: date)
        if let known = quotes[key] {
            report(.etaCacheHit)
            return known
        }
        if unavailable.contains(key) {
            report(.etaCacheHit)
            return nil
        }
        var retried = false
        while !throttled {
            guard calls < callLimit else { truncated = true; interrupted = true; return nil }
            try Task.checkCancellation()
            calls += 1
            let value: LegQuote
            do {
                value = try await timedTravel(from: from, to: to, at: date)
            } catch TravelQuoteError.temporary(let delay) where !retried && retries < 3 && calls < callLimit {
                try Task.checkCancellation()
                retries += 1
                report(.etaRetry)
                retried = true
                if delay > .zero { try await Task.sleep(for: delay) }
                continue
            } catch TravelQuoteError.throttled {
                try Task.checkCancellation()
                throttled = true; interrupted = true; truncated = true
                failures.insert("Apple Maps membatasi permintaan ETA. Coba lagi setelah beberapa saat.")
                return nil
            } catch {
                try Task.checkCancellation()
                unavailable.insert(key)
                failures.insert("ETA Apple: satu ruas tidak tersedia; tidak diganti dengan estimasi buatan.")
                return nil
            }
            guard value.seconds.isFinite, value.seconds >= 0, value.meters.isFinite, value.meters >= 0 else {
                throw EngineError.invalid("Respons ETA Apple tidak valid.")
            }
            quotes[key] = value
            return value
        }
        return nil
    }

    func timedTravel(from: Coordinate, to: Coordinate, at date: Date) async throws -> LegQuote {
        let started = ContinuousClock.now
        let request = calls
        var valid = false
        defer { report(.etaAttempt(number: request, elapsed: started.duration(to: .now), succeeded: valid)) }
        let quote = try await travel(from, to, date)
        valid = quote.seconds.isFinite && quote.seconds >= 0 && quote.meters.isFinite && quote.meters >= 0
        return quote
    }

    func saveCandidate(_ path: [ScheduledStop], location: Coordinate, time: Date, departure: Date) async throws {
        let penalty = pairs.reduce(0.0) { partial, pair in
            guard case .preferred(let minute) = pair.0.timing else { return partial }
            let visit = path.first { $0.venueID == pair.1.id }
            return partial + (visit.map { abs($0.visitStart.timeIntervalSince(at(minute))) } ?? 86_400)
        }
        if let best {
            guard path.count > best.stops.count ||
                path.count == best.stops.count && (penalty < bestTimingPenalty ||
                    penalty == bestTimingPenalty && time < best.finish) else { return }
        }
        var finish = time
        var back = 0.0
        if input.returnToOrigin {
            guard let last = try await quote(from: location, to: input.origin, at: time) else { return }
            finish = time.addingTimeInterval(last.seconds)
            back = last.seconds
        }
        guard finish <= input.deadline else {
            failures.insert("Perjalanan kembali melampaui batas pulang.")
            return
        }
        let candidate = Itinerary(id: UUID(), generatedAt: checkedAt, departure: departure, finish: finish,
                                  origin: input.origin, returnToOrigin: input.returnToOrigin, returnSeconds: back, stops: path,
                                  omitted: [], warnings: [], etaRequests: calls, searchTruncated: false)
        let signature = path.map { $0.venueID + "@" + String($0.visitStart.timeIntervalSince1970) }.joined(separator: "|")
        if !options.contains(where: { entry in
            entry.plan.stops.map { $0.venueID + "@" + String($0.visitStart.timeIntervalSince1970) }.joined(separator: "|") == signature
        }) {
            options.append((candidate, penalty))
            options.sort {
                if $0.plan.stops.count != $1.plan.stops.count { return $0.plan.stops.count > $1.plan.stops.count }
                if $0.penalty != $1.penalty { return $0.penalty < $1.penalty }
                return $0.plan.finish < $1.plan.finish
            }
            options = Array(options.prefix(6))
        }
        if let best {
            guard path.count > best.stops.count ||
                path.count == best.stops.count && (penalty < bestTimingPenalty ||
                    penalty == bestTimingPenalty && finish < best.finish) else { return }
        }
        if best == nil { report(.firstSchedule(started.duration(to: .now))) }
        bestTimingPenalty = penalty
        best = Itinerary(id: UUID(), generatedAt: checkedAt, departure: departure, finish: finish,
                         origin: input.origin, returnToOrigin: input.returnToOrigin, returnSeconds: back, stops: path,
                         omitted: [], warnings: [], etaRequests: calls, searchTruncated: false)
        if path.count == min(pairs.count, input.maximumStops) && penalty == 0 {
            callLimit = min(callLimit, calls + 12)
        }
    }

    func visit(path: [ScheduledStop], used: Set<String>, location: Coordinate, time: Date, departure: Date) async throws {
        try Task.checkCancellation()
        guard !interrupted else { return }
        examined += 1
        guard examined <= 800 else { truncated = true; interrupted = true; return }
        let pendingRequired = required.subtracting(used)
        let isFinal = input.lastVenueID.map { $0 == path.last?.venueID } ?? true
        if path.count >= input.minimumStops && pendingRequired.isEmpty && isFinal {
            try await saveCandidate(path, location: location, time: time, departure: departure)
        }
        if path.count >= input.maximumStops { return }
        if let last = input.lastVenueID, used.contains(last) { return }
        // Leave room for the next leg when prioritizing a timed stop. The actual ETA still gates its start.
        let soon = time.addingTimeInterval(Double(input.maxWaitMinutes + 10) * 60)
        let ordered = pairs.filter { !used.contains($0.1.id) }.map { choice, venue in
            let canFillTime: Bool
            if let timing = choice.timing {
                canFillTime = at(timing.minute) <= soon
            } else {
                canFillTime = true
            }
            return (choice, venue, latestStart(choice, venue, after: time), canFillTime)
        }.sorted {
            // Try an untimed stop before a later appointment, while keeping the other order searchable.
            if $0.3 != $1.3 { return $0.3 }
            let aRequired = required.contains($0.1.id), bRequired = required.contains($1.1.id)
            if aRequired != bRequired { return aRequired }
            if $0.2 != $1.2 { return $0.2 < $1.2 }
            let a = location.distance(to: $0.1.coordinate), b = location.distance(to: $1.1.coordinate)
            return a == b ? $0.1.id < $1.1.id : a < b
        }
        for (choice, venue, _, _) in ordered {
            try Task.checkCancellation()
            if input.preservesOrder, pairs.first(where: { !used.contains($0.1.id) })?.1.id != venue.id { continue }
            if path.isEmpty, let first = input.firstVenueID, venue.id != first { continue }
            if interrupted { return }
            if venue.id == input.lastVenueID &&
                (!pendingRequired.subtracting([venue.id]).isEmpty || path.count + 1 < input.minimumStops) { continue }
            let manual = confirmation(choice)
            var effectiveProfile = profile
            if manual != nil && effectiveProfile.preferences[.publicAccess] == .required {
                effectiveProfile.preferences[.publicAccess] = .neutral
            }
            if manual != nil && effectiveProfile.preferences[.publicAccess] == .avoided {
                failures.insert(venue.name + ": akses publik yang dikonfirmasi bertentangan dengan atribut yang dihindari."); continue
            }
            let assessment = Recommender.assess(venue, profile: effectiveProfile, now: input.departure)
            guard assessment.eligible else { failures.insert(venue.name + ": " + assessment.blockers.joined(separator: "; ")); continue }
            guard venue.status(.publicAccess, at: input.departure) == .supported || manual?.publicAccessConfirmed == true else {
                failures.insert(venue.name + ": akses pengunjung umum belum didukung bukti atau konfirmasi perjalanan."); continue
            }
            let intervals = openingWindows(choice, venue)
            guard !intervals.isEmpty else {
                failures.insert(venue.name + ": jam kunjungan belum tersedia, kedaluwarsa, atau tidak ada interval buka.")
                continue
            }
            guard let eta = try await quote(from: location, to: venue.coordinate, at: time) else {
                if interrupted { return }
                failures.insert(venue.name + ": ETA menuju tempat tidak tersedia."); continue
            }
            let arrival = time.addingTimeInterval(eta.seconds)
            let duration = Double(choice.durationMinutes) * 60
            let outdoor = venue.status(.outdoor, at: arrival) == .supported
            let starts = visitStarts(choice, arrival: arrival, duration: duration, intervals: intervals,
                                     checkLaterWeather: input.avoidRain && outdoor)
            guard !starts.isEmpty else {
                failures.insert(venue.name + ": durasi penuh atau jam wajib tidak muat pada jam buka, batas menunggu, atau batas pulang.")
                continue
            }
            for start in starts {
                if interrupted { return }
                let end = start.addingTimeInterval(duration)
                guard manual != nil || venue.hours?.fresh(at: end) == true else { failures.insert(venue.name + ": masa berlaku jam berakhir sebelum kunjungan selesai."); continue }
                guard Recommender.assess(venue, profile: effectiveProfile, now: end).eligible else { failures.insert(venue.name + ": bukti syarat wajib berakhir sebelum kunjungan selesai."); continue }
                guard manual?.publicAccessConfirmed == true || venue.status(.publicAccess, at: end) == .supported else { failures.insert(venue.name + ": bukti akses berakhir sebelum kunjungan selesai."); continue }
                guard let weatherText = try await weatherText(for: venue, from: start, to: end) else { continue }
                let evidence = manual != nil ? "Jam dan akses dikonfirmasi pengguna untuk perjalanan ini." : "Jam dari " + (venue.hours?.sourceURL ?? "")
                let stop = ScheduledStop(venueID: venue.id, name: venue.name, coordinate: venue.coordinate, departure: time,
                                         arrival: arrival, visitStart: start, visitEnd: end, driveSeconds: eta.seconds, distanceMeters: eta.meters,
                                         evidence: evidence, weather: weatherText)
                try await visit(path: path + [stop], used: used.union([venue.id]), location: venue.coordinate,
                                time: end, departure: departure)
            }
        }
    }

    func confirmation(_ choice: StopChoice) -> TripOverride? {
        guard let value = choice.override, value.day == TripClock.day(day), value.publicAccessConfirmed,
              (0 ..< 1440).contains(value.opens), value.closes > value.opens, value.closes <= 1440 else { return nil }
        return value
    }

    func openingWindows(_ choice: StopChoice, _ venue: Venue) -> [DateInterval] {
        if let manual = confirmation(choice) {
            return [DateInterval(start: at(manual.opens), end: at(manual.closes))]
        }
        guard let hours = venue.hours, hours.fresh(at: input.departure) else { return [] }
        return hours.windows(on: day)
    }

    func latestStart(_ choice: StopChoice, _ venue: Venue, after time: Date) -> Date {
        if case .required(let minute) = choice.timing { return at(minute) }
        let duration = Double(choice.durationMinutes) * 60
        return openingWindows(choice, venue).first { $0.end.addingTimeInterval(-duration) >= max(time, $0.start) }?
            .end.addingTimeInterval(-duration) ?? .distantFuture
    }

    func visitStarts(_ choice: StopChoice, arrival: Date, duration: Double, intervals: [DateInterval],
                     checkLaterWeather: Bool) -> [Date] {
        var starts = Set<Date>()
        for window in intervals {
            var earliest = max(arrival, window.start)
            if case .notBefore(let minute) = choice.timing { earliest = max(earliest, at(minute)) }
            let latest = min(arrival.addingTimeInterval(Double(input.maxWaitMinutes) * 60),
                             min(window.end, input.deadline).addingTimeInterval(-duration))
            guard earliest <= latest else { continue }
            if case .required(let minute) = choice.timing {
                let fixed = at(minute)
                if (earliest ... latest).contains(fixed) { starts.insert(fixed) }
                continue
            }
            starts.insert(earliest)
            if case .preferred(let minute) = choice.timing { starts.insert(min(max(at(minute), earliest), latest)) }
            if checkLaterWeather {
                let nextHour = TripClock.calendar.dateInterval(of: .hour, for: earliest)!.end
                for boundary in sequence(first: nextHour, next: { $0.addingTimeInterval(3600) }).prefix(while: { $0 <= latest }) {
                    starts.insert(boundary)
                }
            }
            if choice.timing == nil && !checkLaterWeather { break }
        }
        if case .preferred(let minute) = choice.timing {
            let target = at(minute)
            return starts.sorted {
                let a = abs($0.timeIntervalSince(target)), b = abs($1.timeIntervalSince(target))
                return a == b ? $0 < $1 : a < b
            }
        }
        return starts.sorted()
    }

    func weatherText(for venue: Venue, from start: Date, to end: Date) async throws -> String? {
        let exposure = venue.status(.outdoor, at: end)
        if exposure == .contradicted { return "Bukti menyatakan kegiatan tidak berada di luar ruang." }
        if exposure == .unknown {
            if !input.avoidRain { return "Paparan outdoor belum diketahui; kecocokan cuaca belum dapat dipastikan." }
            failures.insert(venue.name + ": paparan indoor/outdoor belum diketahui untuk syarat hindari hujan.")
            return nil
        }
        do {
            let reading = try await weather(venue.coordinate, start, end)
            guard input.avoidRain else { return reading.summary }
            guard let chance = reading.maxRainChance, (0 ... 1).contains(chance) else {
                failures.insert(venue.name + ": prakiraan belum mencakup seluruh kunjungan.")
                return nil
            }
            if chance <= 0.5 { return reading.summary }
            failures.insert(venue.name + ": prakiraan tidak memenuhi batas peluang hujan 50% selama kunjungan.")
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            if !input.avoidRain { return "Prakiraan cuaca tidak tersedia; kondisi belum diperiksa." }
            failures.insert(venue.name + ": prakiraan cuaca tidak tersedia.")
        }
        return nil
    }

}

extension HoursEvidence {
    public func windows(on day: Date) -> [DateInterval] {
        let cal = TripClock.calendar, base = cal.startOfDay(for: day)
        return [-1, 0].flatMap { offset -> [DateInterval] in
            let date = cal.date(byAdding: .day, value: offset, to: base)!
            let key = TripClock.day(date), weekday = cal.component(.weekday, from: date)
            let specific = intervals.filter { $0.date == key }
            let rows = specific.isEmpty ? intervals.filter { $0.date == nil && $0.weekday == weekday } : specific
            return rows.map { .init(start: date.addingTimeInterval(Double($0.startMinute) * 60), end: date.addingTimeInterval(Double($0.endMinute) * 60)) }
        }.sorted { $0.start < $1.start }
    }
}
