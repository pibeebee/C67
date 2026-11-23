import Foundation

/// The v5.1 policy uses the same routing and refinement path as v5.
public struct PlannerV51: Sendable {
    private let planner: PlannerV5

    public init(checkInBufferMinutes: Int = 15, route: @escaping PlannerV5.RouteProvider) {
        planner = PlannerV5(route: route, checkInBufferMinutes: checkInBufferMinutes)
    }

    public func plan(_ input: PlannerV5Input) async throws -> PlannerV5Result {
        try await planner.plan(input)
    }

    public func prepare(_ input: PlannerV5Input) async throws -> PlannerV5PreparedPlan {
        try await planner.prepare(input)
    }
}

public enum PlannerV51SunExposure: Equatable, Sendable {
    case direct, sheltered
}

public enum PlannerV51WeatherKind: CaseIterable, Hashable, Sendable {
    /// Degrees Celsius.
    case apparentTemperature
    /// Direct solar irradiance in watts per square meter.
    case directIrradiance
    /// Environmental UV index.
    case uvIndex
}

public struct PlannerV51WeatherSeries: Sendable {
    public struct Sample: Sendable {
        public let interval: DateInterval
        public let value: Double

        public init(interval: DateInterval, value: Double) {
            self.interval = interval
            self.value = value
        }
    }

    public let kind: PlannerV51WeatherKind
    /// Identifies the provider and forecast series used for comparison.
    public let source: String
    public let samples: [Sample]
    /// The threshold uses the same units as the series.
    public let threshold: Double?

    public init(kind: PlannerV51WeatherKind, source: String, samples: [Sample], threshold: Double? = nil) {
        self.kind = kind
        self.source = source
        self.samples = samples
        self.threshold = threshold
    }
}

public struct PlannerV51CheckIn: Equatable, Sendable {
    public let placeID: UUID
    public let deadline: Date
    public let arrival: Date
    public let targetMinutes: Int
    public let bufferMinutes: Double
    public let shortfallMinutes: Double
}

public struct PlannerV51WeatherReading: Sendable {
    public let kind: PlannerV51WeatherKind
    public let average: Double?
    /// Integral in the series' units multiplied by minutes.
    public let excessIntegral: Double?
    public let source: String?
    public let threshold: Double?

    var score: Double? { threshold == nil ? average : excessIntegral }
}

public struct PlannerV51OutdoorVisit: Sendable {
    public let placeID: UUID
    public let interval: DateInterval
    public let sunExposure: PlannerV51SunExposure?
    public let sunExposureSource: PlannerV5Source?
    public let readings: [PlannerV51WeatherReading]
}

public struct PlannerV51Comparison: Sendable {
    public struct WeatherChange: Sendable {
        public let placeID: UUID
        public let kind: PlannerV51WeatherKind
        /// Candidate minus reference. Nil means the comparison lacks matching evidence.
        public let scoreDelta: Double?
        public let threshold: Double?
    }

    public let drivingMinutesDelta: Int
    public let weather: [WeatherChange]

    init(candidate: PlannerV5Schedule, reference: PlannerV5Schedule) {
        drivingMinutesDelta = candidate.drivingMinutes - reference.drivingMinutes
        weather = reference.outdoorVisits.flatMap { visit in
            let candidateVisit = candidate.outdoorVisits.first { $0.placeID == visit.placeID }
            return visit.readings.map { reading in
                let other = candidateVisit?.readings.first { $0.kind == reading.kind }
                let delta: Double?
                if let source = reading.source, source == other?.source, reading.threshold == other?.threshold,
                   let before = reading.score, let after = other?.score {
                    delta = after - before
                } else {
                    delta = nil
                }
                return WeatherChange(placeID: visit.placeID, kind: reading.kind, scoreDelta: delta,
                                     threshold: reading.threshold)
            }
        }
    }
}

extension PlannerV5 {
    func checkInShortfall(_ schedule: PlannerV5Schedule) -> (Double, Double) {
        let values = schedule.checkIns.map(\.shortfallMinutes)
        return (values.max() ?? 0, values.reduce(0, +))
    }

    func outdoorVisit(_ stop: Stop, start: Date, end: Date) -> PlannerV51OutdoorVisit {
        let exposure: PlannerV51SunExposure?
        switch stop.context.sunExposureSource {
        case .traveller?, .venue(_)?, .observed(_)?, .reservation?: exposure = stop.context.sunExposure
        default: exposure = nil
        }
        let readings = PlannerV51WeatherKind.allCases.compactMap { kind -> PlannerV51WeatherReading? in
            // Shade changes direct exposure. UV is an environmental forecast for the place.
            if kind == .directIrradiance && exposure != .direct { return nil }
            let matching = stop.context.outdoorWeather.filter { $0.kind == kind }
            if matching.count == 1 {
                return weatherReading(matching[0], start: start, end: end)
            }
            return .init(kind: kind, average: nil, excessIntegral: nil, source: nil, threshold: nil)
        }
        return .init(placeID: stop.place.id, interval: .init(start: start, end: end),
                     sunExposure: exposure, sunExposureSource: exposure == nil ? nil : stop.context.sunExposureSource,
                     readings: readings)
    }

    private func weatherReading(_ series: PlannerV51WeatherSeries, start: Date, end: Date) -> PlannerV51WeatherReading {
        let unknown = PlannerV51WeatherReading(kind: series.kind, average: nil, excessIntegral: nil,
                                              source: nil, threshold: series.threshold)
        guard end > start, !series.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              series.threshold.map({ $0.isFinite && (series.kind == .apparentTemperature || $0 >= 0) }) ?? true else {
            return unknown
        }
        let samples = series.samples.filter { $0.interval.start < end && $0.interval.end > start }
            .sorted { $0.interval.start < $1.interval.start }
        var cursor = start
        var sum = 0.0
        var excess = 0.0
        for sample in samples {
            let lower = max(start, sample.interval.start)
            let upper = min(end, sample.interval.end)
            guard lower == cursor, upper > lower, sample.value.isFinite,
                  series.kind == .apparentTemperature || sample.value >= 0 else { return unknown }
            let overlap = upper.timeIntervalSince(lower) / 60
            sum += sample.value * overlap
            if let threshold = series.threshold {
                excess += max(0, sample.value - threshold) * overlap
            }
            cursor = upper
        }
        guard cursor == end, sum.isFinite, excess.isFinite else { return unknown }
        return .init(kind: series.kind, average: sum / (end.timeIntervalSince(start) / 60),
                     excessIntegral: series.threshold == nil ? nil : excess, source: series.source,
                     threshold: series.threshold)
    }

    func outdoorTradeoff(_ candidate: PlannerV5Schedule, against reference: PlannerV5Schedule) -> (gain: Bool, loss: Bool) {
        let comparison = PlannerV51Comparison(candidate: candidate, reference: reference)
        var deltas = comparison.weather.compactMap(\.scoreDelta)
        for metric in reference.metrics {
            guard let other = candidate.metrics.first(where: { $0.placeID == metric.placeID && $0.goal == metric.goal }),
                  metric.sources == other.sources, let before = metric.value, let after = other.value else { continue }
            deltas.append(metric.goal == .avoidRain ? after - before : before - after)
        }
        return (deltas.contains { $0 < -1e-8 }, deltas.contains { $0 > 1e-8 })
    }

    /// Schedules arrive in the existing preference and travel order.
    func selectV51(_ schedules: [PlannerV5Schedule], extraTravelMinutes: Int) -> (PlannerV5Schedule, PlannerV5Schedule?) {
        let fastest = schedules[0]
        let affordable = schedules.filter { $0.drivingMinutes <= fastest.drivingMinutes + extraTravelMinutes }
        let bestBuffer = affordable.map(checkInShortfall).min { $0 < $1 }!
        let peers = affordable.filter { checkInShortfall($0) == bestBuffer }
        let reference = peers[0]
        let improvements = peers.dropFirst().filter {
            let difference = outdoorTradeoff($0, against: reference)
            return difference.gain && !difference.loss
        }
        let selected = improvements.first { candidate in
            !improvements.contains { other in
                let difference = outdoorTradeoff(other, against: candidate)
                return difference.gain && !difference.loss
            }
        } ?? reference

        let alternative = schedules.first { candidate in
            guard candidate.departsAt != selected.departsAt ||
                    candidate.visits.map(\.placeID) != selected.visits.map(\.placeID) else { return false }
            let difference = outdoorTradeoff(candidate, against: selected)
            return candidate.drivingMinutes < selected.drivingMinutes ||
                checkInShortfall(candidate) < checkInShortfall(selected) || difference.gain
        }
        return (selected, alternative)
    }
}

extension PlannerV5 {
    func bufferTarget(_ day: Day) -> Int? {
        checkInBufferMinutes.map { day.input.checkInBufferMinutes ?? $0 }
    }

    func v51Anchors(_ stop: Stop, day: Day) -> [Int] {
        guard let target = bufferTarget(day) else { return [] }
        var anchors: Set<Int> = []
        if let session = stop.place.activitySession {
            anchors.insert(Self.minute(session.arriveBy ?? session.startsAt) - target)
            anchors.insert(Self.minute(session.startsAt, rounding: .up) - day.wait)
        }
        if stop.exposure == .outdoor {
            let windowStart = Self.date(day.start)
            let windowEnd = Self.date(day.end)
            for series in stop.context.outdoorWeather {
                for sample in series.samples where sample.interval.start < windowEnd && sample.interval.end > windowStart {
                    anchors.insert(Self.minute(sample.interval.start, rounding: .up))
                    anchors.insert(Self.minute(sample.interval.end, rounding: .up))
                }
            }
        }
        return anchors.sorted()
    }
}
