import Foundation

/// Server-supplied graph facts; unknown route/time values remain nil.
public struct TripGraph: Equatable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let id: UUID
    public let title: String
    public let startsAt: Date
    public let revision: Int
    public let status: String
    public let sources: [GraphSource]
    public let days: [GraphDay]
    public let stops: [GraphStop]
    public let legs: [GraphLeg]
    public let warnings: [String]

    public init(schemaVersion: Int, id: UUID, title: String, startsAt: Date, revision: Int, status: String,
                sources: [GraphSource], days: [GraphDay], stops: [GraphStop], legs: [GraphLeg], warnings: [String]) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.startsAt = startsAt
        self.revision = revision
        self.status = status
        self.sources = sources
        self.days = days
        self.stops = stops
        self.legs = legs
        self.warnings = warnings
    }
}

public struct GraphPoint: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let label: String?

    public init(latitude: Double, longitude: Double, label: String?) {
        self.latitude = latitude
        self.longitude = longitude
        self.label = label
    }
}

public struct GraphSource: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let rundownID: UUID
    public let versionID: UUID
    public let versionNo: Int
    public let title: String

    public init(id: UUID, rundownID: UUID, versionID: UUID, versionNo: Int, title: String) {
        self.id = id
        self.rundownID = rundownID
        self.versionID = versionID
        self.versionNo = versionNo
        self.title = title
    }
}

public struct GraphDay: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let dayIndex: Int
    public let startsAt: Date
    public let timeZone: String?
    public let localDate: String?
    public let startTimeBasis: String
    public let origin: GraphPoint?
    public let landing: GraphLanding

    public init(id: UUID, dayIndex: Int, startsAt: Date, timeZone: String?, localDate: String?,
                startTimeBasis: String, origin: GraphPoint?, landing: GraphLanding) {
        self.id = id
        self.dayIndex = dayIndex
        self.startsAt = startsAt
        self.timeZone = timeZone
        self.localDate = localDate
        self.startTimeBasis = startTimeBasis
        self.origin = origin
        self.landing = landing
    }
}

public struct GraphLanding: Equatable, Sendable {
    public let kind: String
    public let tripStopID: UUID?
    public let location: GraphPoint?

    public init(kind: String, tripStopID: UUID?, location: GraphPoint?) {
        self.kind = kind
        self.tripStopID = tripStopID
        self.location = location
    }
}

public struct GraphStop: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let dayID: UUID
    public let sourceID: UUID
    public let sourceStopID: UUID
    public let position: Int
    public let title: String
    public let location: GraphPoint?
    public let timeZone: String?
    public let visitDurationSeconds: Int?
    public let progressStatus: String

    public init(id: UUID, dayID: UUID, sourceID: UUID, sourceStopID: UUID, position: Int, title: String,
                location: GraphPoint?, timeZone: String?, visitDurationSeconds: Int?, progressStatus: String) {
        self.id = id
        self.dayID = dayID
        self.sourceID = sourceID
        self.sourceStopID = sourceStopID
        self.position = position
        self.title = title
        self.location = location
        self.timeZone = timeZone
        self.visitDurationSeconds = visitDurationSeconds
        self.progressStatus = progressStatus
    }
}

public struct GraphLeg: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let dayID: UUID
    public let position: Int
    public let kind: String
    public let fromTripStopID: UUID?
    public let toTripStopID: UUID?
    public let transportMode: String
    public let durationSeconds: Int?
    public let sourceLegID: UUID?
    public let estimateOrigin: String

    public init(id: UUID, dayID: UUID, position: Int, kind: String, fromTripStopID: UUID?, toTripStopID: UUID?,
                transportMode: String, durationSeconds: Int?, sourceLegID: UUID?, estimateOrigin: String) {
        self.id = id
        self.dayID = dayID
        self.position = position
        self.kind = kind
        self.fromTripStopID = fromTripStopID
        self.toTripStopID = toTripStopID
        self.transportMode = transportMode
        self.durationSeconds = durationSeconds
        self.sourceLegID = sourceLegID
        self.estimateOrigin = estimateOrigin
    }
}
