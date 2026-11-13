import Foundation

public struct CampaignItem: Codable, Sendable {
    public var test: LabCase; public var variant: String; public var condition: String
}
public enum LabCampaign {
    /// Contemporary Saturday matrix; date/hour differences are explicit versus historical runs.
    public static func decisionComparison(now: Date) -> [CampaignItem] {
        LabMatrix.cases(now: now.addingTimeInterval(-86400)).enumerated().flatMap { index, original in
            var test = original
            test.request.departure = TripClock.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: test.request.departure)!
            return (index % 2 == 0 ? ["D", "E"] : ["E", "D"]).map {
                CampaignItem(test: test, variant: $0, condition: "fresh_decision_sequence")
            }
        }
    }
    public static func fastComparison(now: Date) -> [CampaignItem] {
        LabMatrix.cases(now: now).enumerated().flatMap { index, test in
            (index % 2 == 0 ? ["C", "D"] : ["D", "C"]).map {
                CampaignItem(test: test, variant: $0, condition: "fresh")
            }
        }
    }
    public static func replay(now: Date = LabMatrix.now) -> [CampaignItem] {
        LabMatrix.cases(now: now).enumerated().flatMap { index, test in
            [["A", "B", "C"], ["B", "C", "A"], ["C", "A", "B"]][index % 3].map {
                CampaignItem(test: test, variant: $0, condition: "fresh")
            }
        }
    }
    /// Priority and order are frozen before observing providers. Warm priming is reported separately.
    public static func live(now: Date) -> [CampaignItem] {
        let matrix = LabMatrix.cases(now: now)
        var result: [CampaignItem] = []
        func fresh(_ family: String) {
            let cases = matrix.filter { $0.family == family }
            for (block, test) in cases.enumerated() {
                for variant in [["A", "B", "C"], ["B", "C", "A"], ["C", "A", "B"]][block] {
                    result.append(.init(test: test, variant: variant, condition: "fresh"))
                }
            }
        }
        for family in ["N3", "N4", "N5"] { fresh(family) }
        for (index, test) in matrix.filter({ ["REV5", "MIX5", "TIGHT5", "SIX", "UNKNOWN"].contains($0.family) }).enumerated() {
            for variant in [["A", "B", "C"], ["B", "C", "A"], ["C", "A", "B"]][index % 3] {
                result.append(.init(test: test, variant: variant, condition: "edge"))
            }
        }
        fresh("N1")
        for family in ["N1", "N3", "N4", "N5"] {
            for variant in ["A", "B", "C"] {
                for condition in ["priming", "warm"] {
                    var test = matrix.first { $0.family == family }!
                    test.id = family + "-" + condition
                    result.append(.init(test: test, variant: variant, condition: condition))
                }
            }
        }
        return result
    }
}
