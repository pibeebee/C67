import Foundation
import C67Domain

struct TripGraphDTO: Decodable {
    let schema_version: Int
    let id: UUID
    let title: String
    let starts_at: Date
    let revision: Int
    let status: String
    let sources: [GraphSourceDTO]
    let days: [GraphDayDTO]
    let stops: [GraphStopDTO]
    let legs: [GraphLegDTO]
    let warnings: [String]
    var domain: TripGraph {
        .init(schemaVersion: schema_version, id: id, title: title, startsAt: starts_at, revision: revision,
              status: status, sources: sources.map(\.domain), days: days.map(\.domain), stops: stops.map(\.domain),
              legs: legs.map(\.domain), warnings: warnings)
    }
}

struct GraphPointDTO: Decodable {
    let latitude: Double
    let longitude: Double
    let label: String?
    var domain: GraphPoint {
        .init(latitude: latitude, longitude: longitude, label: label)
    }
}

struct GraphSourceDTO: Decodable {
    let id: UUID
    let rundown_id: UUID
    let version_id: UUID
    let version_no: Int
    let title: String
    var domain: GraphSource {
        .init(id: id, rundownID: rundown_id, versionID: version_id, versionNo: version_no, title: title)
    }
}

struct GraphDayDTO: Decodable {
    let id: UUID
    let day_index: Int
    let starts_at: Date
    let time_zone: String?
    let local_date: String?
    let start_time_basis: String
    let origin: GraphPointDTO?
    let landing: GraphLandingDTO
    var domain: GraphDay {
        .init(id: id, dayIndex: day_index, startsAt: starts_at, timeZone: time_zone, localDate: local_date,
              startTimeBasis: start_time_basis, origin: origin?.domain, landing: landing.domain)
    }
}

struct GraphLandingDTO: Decodable {
    let kind: String
    let trip_stop_id: UUID?
    let location: GraphPointDTO?
    var domain: GraphLanding {
        .init(kind: kind, tripStopID: trip_stop_id, location: location?.domain)
    }
}

struct GraphStopDTO: Decodable {
    let id: UUID
    let day_id: UUID
    let source_id: UUID
    let source_stop_id: UUID
    let position: Int
    let title: String
    let location: GraphPointDTO?
    let time_zone: String?
    let visit_duration_seconds: Int?
    let progress_status: String
    var domain: GraphStop {
        .init(id: id, dayID: day_id, sourceID: source_id, sourceStopID: source_stop_id, position: position,
              title: title, location: location?.domain, timeZone: time_zone,
              visitDurationSeconds: visit_duration_seconds, progressStatus: progress_status)
    }
}

struct GraphLegDTO: Decodable {
    let id: UUID
    let day_id: UUID
    let position: Int
    let kind: String
    let from_trip_stop_id: UUID?
    let to_trip_stop_id: UUID?
    let transport_mode: String
    let duration_seconds: Int?
    let source_leg_id: UUID?
    let estimate_origin: String
    var domain: GraphLeg {
        .init(id: id, dayID: day_id, position: position, kind: kind, fromTripStopID: from_trip_stop_id,
              toTripStopID: to_trip_stop_id, transportMode: transport_mode, durationSeconds: duration_seconds,
              sourceLegID: source_leg_id, estimateOrigin: estimate_origin)
    }
}
