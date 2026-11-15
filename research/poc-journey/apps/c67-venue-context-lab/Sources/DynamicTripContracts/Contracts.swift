import Foundation
import PlaceContextEngine

public struct DynamicSearchInput: Codable, Sendable {
    public var query: String
    public init(query: String) { self.query = query }
}

public struct DynamicAppleCandidate: Codable, Identifiable, Sendable {
    public static let maximumPilotSeparationMeters = 500.0
    public static func canConfirm(separation: Double) -> Bool { separation.isFinite && (0 ... maximumPilotSeparationMeters).contains(separation) }
    public var canConfirm: Bool { Self.canConfirm(separation: distanceFromReferenceMeters) && nameSupported != false }
    public var nameSupported: Bool?
    public static func compatibleNames(reference: String, apple: String, address: String) -> Bool {
        let aliases = ["national": "nasional", "history": "sejarah", "monument": "monumen", "stadium": "stadion"]
        func tokens(_ value: String) -> Set<String> {
            Set(value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .lowercased().split{ !$0.isLetter && !$0.isNumber}.map{aliases[String($0)] ?? String($0)})
        }
        let g = tokens(reference), a = tokens(apple)
        if g == a && !g.isEmpty { return true }
        let generic: Set<String> = ["hotel", "museum", "cafe", "kafe", "coffee", "kopi", "taman", "park", "station", "stasiun", "restoran", "restaurant", "perpustakaan", "library", "shop", "store", "book", "toko", "buku", "jakarta", "indonesia", "central", "pusat", "barat", "timur", "utara", "selatan", "jalan", "jl", "no", "rt", "rw", "the", "of", "in", "and", "dan", "at", "cabang", "gedung"]
        let excluded = generic.union(tokens(address))
        let left = g.subtracting(excluded), right = a.subtracting(excluded)
        return !left.isEmpty && !right.isEmpty && Double(left.intersection(right).count) / Double(left.count) >= 0.5
    }
    public var id: String
    public var name: String
    public var address: String
    public var latitude: Double
    public var longitude: Double
    public var distanceFromReferenceMeters: Double
    public init(id: String, name: String, address: String, latitude: Double, longitude: Double, distanceFromReferenceMeters: Double, nameSupported: Bool? = nil) {
        self.id = id; self.name = name; self.address = address
        self.latitude = latitude; self.longitude = longitude
        self.distanceFromReferenceMeters = distanceFromReferenceMeters
        self.nameSupported = nameSupported
    }
}

public struct DynamicPrepareInput: Codable, Sendable {
    public var placeID: String
    public var day: String
    public var appleQuery: String?
    public var forOrigin: Bool?
    public init(placeID: String, day: String, appleQuery: String? = nil, forOrigin: Bool? = nil) {
        self.placeID = placeID; self.day = day; self.appleQuery = appleQuery; self.forOrigin = forOrigin
    }
}

public struct DynamicPreparedPlace: Codable, Identifiable, Sendable {
    public var id: UUID
    public var placeID: String
    public var name: String
    public var address: String
    public var evidenceURL: String?
    public var attribution: String
    public var expiresAt: Date
    public var hours: OperatingResolution
    public var appleCandidates: [DynamicAppleCandidate]
    public init(id: UUID, placeID: String, name: String, address: String, evidenceURL: String?, attribution: String, expiresAt: Date, hours: OperatingResolution, appleCandidates: [DynamicAppleCandidate]) {
        self.id = id; self.placeID = placeID; self.name = name; self.address = address
        self.evidenceURL = evidenceURL; self.attribution = attribution; self.expiresAt = expiresAt
        self.hours = hours; self.appleCandidates = appleCandidates
    }
}

public struct DynamicEndpoint: Codable, Sendable {
    public var preparedID: UUID
    public var appleCandidateID: String
    public init(preparedID: UUID, appleCandidateID: String) {
        self.preparedID = preparedID; self.appleCandidateID = appleCandidateID
    }
}

public struct DynamicStopInput: Codable, Sendable {
    public var endpoint: DynamicEndpoint
    public var durationMinutes: Int
    public var exposure: ActivityExposure
    public var preferredTime: PreferredVisitTime?
    public var avoidRain: Bool
    public init(endpoint: DynamicEndpoint, durationMinutes: Int = 60, exposure: ActivityExposure = .unknown, preferredTime: PreferredVisitTime? = nil, avoidRain: Bool = false) {
        self.endpoint = endpoint; self.durationMinutes = durationMinutes; self.exposure = exposure
        self.preferredTime = preferredTime; self.avoidRain = avoidRain
    }
}

public struct DynamicPlanInput: Codable, Sendable {
    public var origin: DynamicEndpoint
    public var stops: [DynamicStopInput]
    public var departure: Date
    public var deadline: Date
    public var maximumWaitingMinutes: Int
    public var startStepMinutes: Int
    public var priorities: [VisitGoal]
    public var policy: ContextSearchPolicy
    public var maxTravelCalls: Int
    public init(origin: DynamicEndpoint, stops: [DynamicStopInput], departure: Date, deadline: Date, maximumWaitingMinutes: Int = 30, startStepMinutes: Int = 5, priorities: [VisitGoal] = [.preferredTime, .lowerRain, .quiet, .comfortableTemperature], policy: ContextSearchPolicy = .firstFeasible, maxTravelCalls: Int = 64) {
        self.origin = origin; self.stops = stops; self.departure = departure; self.deadline = deadline
        self.maximumWaitingMinutes = maximumWaitingMinutes; self.startStepMinutes = startStepMinutes
        self.priorities = priorities; self.policy = policy; self.maxTravelCalls = maxTravelCalls
    }
}

public struct DynamicStageMetrics: Codable, Sendable {
    public var preparationSeconds: Double
    public var routingSeconds: Double
    public var etaAdapterSeconds: Double
    public var serverTotalSeconds: Double
    public var etaCalls: Int
    public var unavailableETA: Int
    public var weatherStatus: String
    public var evidenceMode: String
    public init(preparationSeconds: Double, routingSeconds: Double, etaAdapterSeconds: Double, serverTotalSeconds: Double, etaCalls: Int, unavailableETA: Int, weatherStatus: String, evidenceMode: String) {
        self.preparationSeconds = preparationSeconds; self.routingSeconds = routingSeconds
        self.etaAdapterSeconds = etaAdapterSeconds; self.serverTotalSeconds = serverTotalSeconds
        self.etaCalls = etaCalls; self.unavailableETA = unavailableETA
        self.weatherStatus = weatherStatus; self.evidenceMode = evidenceMode
    }
}

public struct DynamicPlanResponse: Codable, Sendable {
    public var itinerary: ContextItineraryResult
    public var metrics: DynamicStageMetrics
    public var weatherAttributions: [String]
    public var moment: VisitOpportunity?
    public init(itinerary: ContextItineraryResult, metrics: DynamicStageMetrics, weatherAttributions: [String] = [],
                moment: VisitOpportunity? = nil) {
        self.itinerary = itinerary; self.metrics = metrics; self.weatherAttributions = weatherAttributions
        self.moment = moment
    }
}

public struct DynamicPlanChoices: Sendable {
    public let baseline: DynamicPlanResponse
    public let alternative: DynamicPlanResponse?
    public init(baseline: DynamicPlanResponse, alternative: DynamicPlanResponse? = nil) {
        self.baseline = baseline
        self.alternative = alternative
    }
}

public struct ContextExperimentInput: Codable, Sendable {
    public var scenario: String
    public init(scenario: String) { self.scenario = scenario }
}

public struct PersonalPlanInput: Codable, Sendable {
    public var recommendationID: UUID
    public var profileRevision: Int
    public var requiredPlaceIDs: [String]
    public var plan: DynamicPlanInput
    public var considerMoments: Bool?
    public init(recommendationID: UUID, profileRevision: Int, requiredPlaceIDs: [String], plan: DynamicPlanInput, considerMoments: Bool? = nil) {
        self.recommendationID = recommendationID; self.profileRevision = profileRevision; self.requiredPlaceIDs = requiredPlaceIDs; self.plan = plan
        self.considerMoments = considerMoments
    }
}
public struct PersonalPlanOmission: Codable, Sendable {
    public var id: String
    public var required: Bool
    public var reason: String
    public init(id: String, required: Bool, reason: String) { self.id = id; self.required = required; self.reason = reason }
}
public struct MomentPlanReview: Codable, Sendable {
    public let outcome: String
    public let selectedPlanID: String
    public let model: String?
    public let seconds: Double
    public let extraTravelSeconds: Double
    public let extraWaitingSeconds: Double
    public let costUSD: Double?
    public let reasonCode: String?
    public init(outcome: String, selectedPlanID: String, model: String?, seconds: Double,
                extraTravelSeconds: Double, extraWaitingSeconds: Double, costUSD: Double?, reasonCode: String? = nil) {
        self.outcome = outcome
        self.selectedPlanID = selectedPlanID
        self.model = model
        self.seconds = seconds
        self.extraTravelSeconds = extraTravelSeconds
        self.extraWaitingSeconds = extraWaitingSeconds
        self.costUSD = costUSD
        self.reasonCode = reasonCode
    }
}

public struct PersonalPlanResult: Codable, Sendable {
    public var result: DynamicPlanResponse
    public var requiredPlaceIDs: [String]
    public var omitted: [PersonalPlanOmission]
    public var momentReview: MomentPlanReview?
    public init(result: DynamicPlanResponse, requiredPlaceIDs: [String], omitted: [PersonalPlanOmission], momentReview: MomentPlanReview? = nil) {
        self.result = result; self.requiredPlaceIDs = requiredPlaceIDs; self.omitted = omitted
        self.momentReview = momentReview
    }
}

public struct ContextScenario: Codable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public init(id: String, title: String) { self.id = id; self.title = title }
}

public struct ContextExperimentResponse: Codable, Sendable {
    public var scenario: ContextScenario
    public var input: ContextPlanRequest
    public var now: Date
    public var fixedTravelSeconds: Double
    public var travelUnavailable: Bool
    public var output: DynamicPlanResponse
    public init(scenario: ContextScenario, input: ContextPlanRequest, now: Date, fixedTravelSeconds: Double, travelUnavailable: Bool, output: DynamicPlanResponse) {
        self.scenario = scenario; self.input = input; self.now = now
        self.fixedTravelSeconds = fixedTravelSeconds; self.travelUnavailable = travelUnavailable; self.output = output
    }
}
