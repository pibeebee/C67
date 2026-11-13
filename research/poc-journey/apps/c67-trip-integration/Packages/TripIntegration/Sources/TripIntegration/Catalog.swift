import Foundation
import PreferenceQuality
import VisitTiming

public struct IntegrationCatalog: Sendable {
    public var quality: QualityCatalog
    public var timing: TimingCatalog
    public var region: ExperimentRegion?
    public static func load(blokM: Bool = false, includeBlokM: Bool = false) throws -> Self {
        let decoder = IntegrationJSON.decoder()
        var quality = try decoder.decode(QualityCatalog.self, from: Data(contentsOf:
            Bundle.module.url(forResource: blokM ? "quality-blok-m" : "quality", withExtension: "json")!))
        var timing = try decoder.decode(TimingCatalog.self, from: Data(contentsOf:
            Bundle.module.url(forResource: blokM ? "timing-blok-m" : "timing", withExtension: "json")!))
        if !blokM && includeBlokM {
            let local = try load(blokM: true)
            quality.id += "+blok-m"
            quality.sources += local.quality.sources.filter { source in !quality.sources.contains { $0.id == source.id } }
            quality.candidates += local.quality.candidates
            timing.id += "+blok-m"
            timing.sources += local.timing.sources.filter { source in !timing.sources.contains { $0.id == source.id } }
            timing.venues += local.timing.venues.filter { venue in !timing.venues.contains { $0.id == venue.id } }
        }
        try quality.validate(); try timing.validate()
        let region = blokM ? try decoder.decode(ExperimentRegion.self, from: Data(contentsOf:
            Bundle.module.url(forResource: "region-blok-m", withExtension: "json")!)) : nil
        try region?.validate(candidateIDs: Set(quality.candidates.map(\.id)))
        return Self(quality: quality, timing: timing, region: region)
    }
    private static let blokMRegion = try? load(blokM: true).region
    public func region(for candidateID: String) -> ExperimentRegion? {
        region ?? (candidateID.hasPrefix("bm") ? Self.blokMRegion : nil)
    }
    public func candidate(_ id: String) -> QualityCandidate? { quality.candidates.first { $0.id == id } }
    public func venue(_ id: String) -> VenueFacts? { timing.venues.first { $0.id == id } }
    public static func contains(_ pin: PlacePin) -> Bool {
        guard pin.latitude.isFinite, pin.longitude.isFinite,
              (-90 ... 90).contains(pin.latitude), (-180 ... 180).contains(pin.longitude) else { return false }
        return NativeTripJakarta.contains(latitude: pin.latitude, longitude: pin.longitude)
    }
    public func timingRun(candidateID: String, request: TripRequest,
                          environment: TimingEnvironment? = nil, now: Date) throws -> TimingRun? {
        guard let candidate = candidate(candidateID), let venue = venue(candidate.venueID),
              candidateID != "bdt-cafe" else { return nil }
        return try VisitTimingEngine().evaluate(.init(venueID: venue.id, date: TripClock.day(request.departure),
                                                      available: .init(TripClock.minute(request.departure), TripClock.minute(request.deadline)),
                                                      durationMinutes: request.duration(venue.id), goal: request.goal), catalog: timing,
                                                environment: environment, now: now)
    }
}

public enum VisitStartPolicy {
    /// Valid starts are inclusive, on a 15-minute grid. A continuous interval is never inferred
    /// across session breaks. The existing P1 engine supplies full-stay-valid ranges.
    public static func earliest(arrival: Date, tripDate: Date, ranges: [MinuteRange]) -> Date? {
        let midnight = TripClock.calendar.startOfDay(for: tripDate)
        let seconds = arrival.timeIntervalSince(midnight)
        guard seconds.isFinite, seconds >= 0, seconds < 86400 else { return nil }
        let rounded = Int(ceil(seconds / 900)) * 15
        return ranges.sorted { $0.start < $1.start }.compactMap { range -> Date? in
            let minute = max(rounded, range.start)
            return minute <= range.end ? midnight.addingTimeInterval(Double(minute) * 60) : nil
        }.first
    }
}
