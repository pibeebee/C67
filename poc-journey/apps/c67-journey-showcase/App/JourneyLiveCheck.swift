#if DEBUG
    import Foundation
    import UIKit
    import TripIntegration

    // Explicit launch argument only. All provider traffic and storage belong to this isolated run.
    @MainActor extension JourneyModel {
        func runLiveCheck() async {
            struct Status: Codable {
                var complete = false
                var success = false
                var stage: String
                var weatherAvailable = false
                var itineraryReady = false
                var detail: String?
            }
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("JourneyLiveChecks/\(UUID())")
            var status = Status(stage: "Starting signed-app provider check")
            func save() throws {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try IntegrationJSON.encoder().encode(status).write(to: folder.appendingPathComponent("status.json"), options: .atomic)
            }
            func settle() async throws {
                let deadline = Date.now.addingTimeInterval(300)
                while busy, Date.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
                try Task.checkCancellation()
                guard !busy, error == nil else {
                    throw IntegrationError.invalid(error ?? "Provider check exceeded the operation budget.")
                }
            }
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            do {
                try save()
                await switchMode(.live)
                diagnoseWeather(); try await settle()
                status.weatherAvailable = !diagnosis.isEmpty && diagnosis.allSatisfy { $0.complete && $0.provider == "weatherkit" }
                try IntegrationJSON.encoder().encode(diagnosis).write(to: folder.appendingPathComponent("weather.json"), options: .atomic)
                status.stage = "Creating a coffee and Wi-Fi busway itinerary"; try save()
                newTrip()
                edit { input in input.desiredCount = 1; input.profile.prefer = [.coffee, .wifi]; input.allowOpenMeteo = false }
                advanceToPreferences(); recommend(); try await settle()
                verify(); try await settle(); generate(); try await settle()
                guard let result = session.proposal else { throw IntegrationError.invalid("No proposal produced.") }
                try IntegrationJSON.encoder().encode(result).write(to: folder.appendingPathComponent("itinerary.json"), options: .atomic)
                try PlanExplanation.markdown(result).write(to: folder.appendingPathComponent("REPORT.md"), atomically: true, encoding: .utf8)
                status.itineraryReady = result.feasible && result.evidenceMode == "live_gtfs_estimate"
                    && result.stops.map(\.id) == ["bm08"] && result.legs.contains { $0.busway?.ride != nil }
                guard status.itineraryReady else { throw IntegrationError.invalid("Live itinerary acceptance failed: \(result.conflicts)") }
                accept(); try await settle(); await flushDraft()
                let restored = try await TripStore(directory: root.appendingPathComponent("live")).load()
                guard restored.session.accepted?.id == result.id else { throw IntegrationError.invalid("Accepted itinerary did not restore.") }
                export(result); try await settle()
                status.success = status.weatherAvailable && result.weather.allSatisfy { $0.complete && $0.provider == "weatherkit" }
                status.stage = "Completed real-provider itinerary, acceptance, restore and export"
                status.detail = status.success ? "WeatherKit and personalized TransJakarta itinerary passed." : "Itinerary completed. WeatherKit requires review of the captured provider errors."
            } catch {
                status.stage = "Provider check needs review"
                status.detail = ProviderDiagnostics.message(error)
            }
            status.complete = true
            try? save()
        }
    }
#endif
