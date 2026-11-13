import Foundation
import VisitTiming

@main struct VisitTimeEval {
    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        func argument(_ key: String, fallback: String) -> String {
            guard let i = args.firstIndex(of: key), i + 1 < args.count else { return fallback }
            return args[i + 1]
        }
        let catalog = try TimingCatalog.load()
        let out = URL(fileURLWithPath: argument("--out", fallback: "/tmp/c67-visit-time-eval"))
        let store = TimingStore(directory: out)
        let venueID = argument("--venue", fallback: "gbk")
        let date = argument("--date", fallback: VenueClock.dateString(.now))
        let goal = TimingGoal(rawValue: argument("--goal", fallback: "openingOnly")) ?? .openingOnly
        let duration = Int(argument("--duration", fallback: "60")) ?? 60
        let startMinute = Int(argument("--start", fallback: "360")) ?? 360
        let endMinute = Int(argument("--end", fallback: "1320")) ?? 1320
        let request = TimingRequest(
            venueID: venueID, date: date,
            available: .init(startMinute, endMinute), durationMinutes: duration, goal: goal)
        guard let venue = catalog.venues.first(where: { $0.id == venueID }) else {
            throw TimingError.invalid("Unknown venue")
        }
        var environment: TimingEnvironment?
        var failure: String?
        let start = Date()
        if args.contains("--live") {
            do { environment = try await LiveTimingEnvironment().fetch(venue: venue, date: date) } catch {
                failure = error.localizedDescription
            }
        }
        var run = try VisitTimingEngine().evaluate(request, catalog: catalog, environment: environment)
        if let failure { run.warnings.append("Live acquisition failed: \(failure)") }
        run.elapsedSeconds = Date().timeIntervalSince(start)
        try await store.save(run)
        let folder = try await store.export(run)
        print("status=\(run.status) options=\(run.options.count) seconds=\(run.elapsedSeconds)")
        print(folder.path)
        if let failure { print("provider_error=\(failure)") }
    }
}
