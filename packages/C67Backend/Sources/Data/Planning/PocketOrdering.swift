import Foundation
import C67Domain
import PocketEngine

enum PocketOrderCodec {
    static func validateMethod(_ actual: PlanningOrderingMethod?, expected: PlanningOrderingMethod?) throws {
        guard (actual ?? .luna) == (expected ?? .luna) else {
            throw PlanningError.failed("POCKET_ORDER_METHOD_UNSUPPORTED")
        }
    }
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let raw = try value.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: raw) else { throw PlanningError.invalidResponse }
            return date
        }
        return decoder
    }
}

extension PlanningExperiencePlan {
    func validated(for input: PlanningInput) throws -> Self {
        _ = try PocketAdviceSelection(slotID: "", requestedModel: requestedModel, reportedModel: reportedModel,
                                      reportedReasoningEffort: reportedReasoningEffort, providerProtocol: providerProtocol).validated()
        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: input.timeZone) else { throw PlanningError.invalidResponse }
        calendar.timeZone = zone
        func day(_ date: Date) -> String {
            let value = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", value.year!, value.month!, value.day!)
        }
        let ids = Set(input.places.map(\.id))
        guard status == "proposed", orderedIDs.count == ids.count, Set(orderedIDs) == ids,
              stops.count == ids.count, Set(stops.map(\.placeID)) == ids,
              !tripRationale.isEmpty, !uncertainties.isEmpty, timeZone == input.timeZone, candidateDate == day(input.startsAt),
              alternativeOrder == nil || (alternativeOrder!.count == ids.count && Set(alternativeOrder!) == ids),
              !input.preservesPlaceOrder || orderedIDs == input.places.map(\.id),
              input.firstPlaceID == nil || orderedIDs.first == input.firstPlaceID,
              Set(weatherSources.map(\.id)).count == weatherSources.count,
              Set(solarWindows.map(\.id)).count == solarWindows.count else { throw PlanningError.invalidResponse }
        for source in weatherSources {
            guard let place = input.places.first(where: { $0.id == source.placeID }), place.location == source.coordinates,
                  source.url.scheme == "https", source.timeZone == timeZone, source.date == candidateDate,
                  !source.hourlySamples.isEmpty else { throw PlanningError.invalidResponse }
            if source.source == "Apple Weather" {
                guard let logo = source.attributionLogoURL, logo.scheme == "https", logo.host == "weatherkit.apple.com",
                      source.url.host == "weatherkit.apple.com" else { throw PlanningError.invalidResponse }
            }
            for hour in source.hourlySamples {
                guard hour.end.timeIntervalSince(hour.start) == 3600, day(hour.start) == candidateDate,
                      (hour.cloudCoverValidAt == hour.end || (source.source == "Apple Weather" && hour.cloudCoverValidAt == hour.start)),
                      hour.precipitationChance.isFinite, (0 ... 1).contains(hour.precipitationChance),
                      hour.cloudCover.isFinite, (0 ... 1).contains(hour.cloudCover),
                      hour.precipitationAmountMM.isFinite, hour.precipitationAmountMM >= 0 else { throw PlanningError.invalidResponse }
            }
        }
        for window in solarWindows {
            guard ids.contains(window.placeID), window.start < window.end,
                  window.date == candidateDate, window.timeZone == timeZone,
                  day(window.start) == candidateDate, day(window.end) == candidateDate else { throw PlanningError.invalidResponse }
        }
        for stop in stops {
            guard !stop.activity.suggestion.isEmpty, !stop.reason.isEmpty,
                  ["name_inference", "user_preference", "fixture_attribute", "unknown"].contains(stop.activity.basis),
                  ["opening", "main", "break", "closing", "supporting"].contains(stop.role),
                  (stop.role == "main") == (stop.placeID == input.enginePreferences?.mainSpotID),
                  ["morning", "afternoon", "evening", "night", "flexible", "unknown"].contains(stop.preferredDayPart),
                  ["relevant", "optional", "not_relevant", "unknown"].contains(stop.light.priority) else { throw PlanningError.invalidResponse }
            if let duration = stop.duration {
                guard duration.minMinutes > 0, duration.maxMinutes >= duration.minMinutes,
                      duration.maxMinutes < Int.max / 60, duration.basis == "experience_estimate",
                      !duration.rationale.isEmpty, stop.durationUnknownReason == nil else { throw PlanningError.invalidResponse }
            } else if stop.durationUnknownReason?.isEmpty != false { throw PlanningError.invalidResponse }
            let sources = weatherSources.filter { $0.placeID == stop.placeID }
            guard stop.weather.status == (sources.isEmpty ? "unavailable" : "available"),
                  sources.isEmpty || !stop.weather.sourceRefs.isEmpty,
                  stop.weather.sourceRefs.allSatisfy({ ref in sources.contains { $0.id == ref } }) else { throw PlanningError.invalidResponse }
            if let ref = stop.light.windowRef {
                guard solarWindows.contains(where: { $0.id == ref && $0.placeID == stop.placeID }) else { throw PlanningError.invalidResponse }
            }
        }
        return self
    }
}

extension PocketResearchClient {
    public func order(_ input: PlanningInput, requestID: UUID) async throws -> PlanningExperiencePlan {
        struct Place: Encodable {
            var id: UUID
            var name: String
            var location: PlanningPoint
            var categories: [String]
        }
        struct Body: Encodable {
            var requestID: UUID
            var places: [Place]
            var preferences: String
            var origin: PlanningPoint
            var endpoint: PlanningPoint
            var mainSpotID: UUID?
            var firstPlaceID: UUID?
            var preservesPlaceOrder: Bool
            var candidateDate: String
            var timeZone: String
            var orderingMethod: PlanningOrderingMethod?
        }
        struct Job: Decodable {
            var id: UUID
            var status: String
        }
        struct Result: Decodable { var result: PlanningExperiencePlan }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: input.timeZone) ?? .current
        let day = calendar.dateComponents([.year, .month, .day], from: input.startsAt)
        let selected = input.places.map { Place(id: $0.id, name: $0.name, location: $0.location, categories: $0.categories) }
        let body = Body(requestID: requestID, places: selected, preferences: input.preferences,
                        origin: input.origin, endpoint: input.enginePreferences?.endPoint ?? input.origin,
                        mainSpotID: input.enginePreferences?.mainSpotID, firstPlaceID: input.firstPlaceID,
                        preservesPlaceOrder: input.preservesPlaceOrder,
                        candidateDate: String(format: "%04d-%02d-%02d", day.year!, day.month!, day.day!), timeZone: input.timeZone,
                        orderingMethod: input.enginePreferences?.orderingMethod == .luna ? nil : input.enginePreferences?.orderingMethod)
        do {
            var data = try await fetch("v1/order", body: JSONEncoder().encode(body))
            while true {
                try Task.checkCancellation()
                let job = try JSONDecoder().decode(Job.self, from: data)
                guard job.id == requestID else { throw PlanningError.invalidResponse }
                switch job.status {
                case "succeeded":
                    let plan = try PocketOrderCodec.decoder().decode(Result.self, from: data).result.validated(for: input)
                    try PocketOrderCodec.validateMethod(plan.orderingMethod, expected: input.enginePreferences?.orderingMethod)
                    return plan
                case "running", "queued":
                    try await Task.sleep(for: .seconds(2))
                    data = try await fetch("v1/order/jobs/" + requestID.uuidString.lowercased())
                case "failed": throw PlanningError.failed("ORDER_GENERATION_FAILED")
                case "interrupted": throw PlanningError.failed("ORDER_SERVER_INTERRUPTED")
                default: throw PlanningError.invalidResponse
                }
            }
        } catch is URLError { throw PlanningError.unavailable }
    }
}
