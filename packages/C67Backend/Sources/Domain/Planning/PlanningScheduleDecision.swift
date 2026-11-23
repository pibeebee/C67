import Foundation

public struct PlanningScheduleDecision: Codable, Equatable, Sendable {
    public struct CheckIn: Codable, Equatable, Sendable, Identifiable {
        public let id: UUID
        public let buffer: Double
        public let target: Int
        public let shortfall: Double

        package init(id: UUID, buffer: Double, target: Int, shortfall: Double) {
            self.id = id
            self.buffer = buffer
            self.target = target
            self.shortfall = shortfall
        }
    }

    public struct Outdoor: Codable, Equatable, Sendable, Identifiable {
        public let id: UUID
        public let interval: DateInterval
        public let readings: [Reading]

        package init(id: UUID, interval: DateInterval, readings: [Reading]) {
            self.id = id
            self.interval = interval
            self.readings = readings
        }
    }

    public struct Reading: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let value: Double?
        public let source: String?

        package init(id: String, value: Double?, source: String?) {
            self.id = id
            self.value = value
            self.source = source
        }
    }

    public let checkIns: [CheckIn]
    public let outdoor: [Outdoor]
    public let extraTravel: Int
    public let alternative: [String]

    package init(checkIns: [CheckIn], outdoor: [Outdoor], extraTravel: Int, alternative: [String]) {
        self.checkIns = checkIns
        self.outdoor = outdoor
        self.extraTravel = extraTravel
        self.alternative = alternative
    }
}
