#if DEBUG
    import Foundation
    import PocketEngine

    /// Opt-in integration on a separate Simulator bundle; never runs in the normal PoC app.
    @MainActor enum SimulatorFlow {
        private struct Input: Decodable {
            var serverURL: String
            var readToken: String
            var venueIDs: [String]
        }
        static func runIfRequested(model: PocketModel) async {
            guard ProcessInfo.processInfo.arguments.contains("--pocket-flow"),
                  Bundle.main.bundleIdentifier == "giovanchristoffel.c67-pocket-engine.integration" else { return }
            let directory = URL.documentsDirectory
            let started = Date()
            var output: [String: Any] = ["hypotheticalHoursAndAccess": true, "realTripValidation": false]
            do {
                let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: directory.appending(path: "flow-input.json")))
                model.serverURL = input.serverURL
                try TokenVault.write(input.readToken)
                model.message = nil
                model.sync()
                let syncDeadline = Date().addingTimeInterval(45)
                while model.isSyncing && Date() < syncDeadline { try await Task.sleep(for: .milliseconds(100)) }
                guard !model.isSyncing, model.message == nil,
                      input.venueIDs.count == 3 else {
                    throw EngineError.invalid("Katalog integrasi tidak berhasil diunduh: " + (model.message ?? (model.isSyncing ? "batas waktu sinkronisasi" : "ID fixture tidak tersedia")))
                }
                let canonicalIDs = try input.venueIDs.map { id -> String in
                    guard let raw = model.catalog?.venues.first(where: { $0.id == id }),
                          let merged = model.match(name: raw.name, coordinate: raw.coordinate) else {
                        throw EngineError.invalid("Fixture tidak memiliki satu padanan cabang pada pool: " + id)
                    }
                    return merged.id
                }
                guard Set(canonicalIDs).count == 3 else { throw EngineError.invalid("Fixture harus mewakili tiga tempat berbeda setelah deduplikasi.") }
                output["fixtureSourceIDs"] = input.venueIDs
                output["canonicalIDs"] = canonicalIDs
                var profile = Profile(); profile.themes = [.nature]
                model.profile = profile; model.selectArea("Kemayoran")
                output["kemayoranEligible"] = model.eligibleCount
                model.selectArea("Jakarta Selatan")
                output["jakselEligible"] = model.eligibleCount
                output["recommendationIDs"] = model.recommendations.map(\.id)
                model.choices = []; model.usesLunaAdvice = true
                let tomorrow = TripClock.calendar.date(byAdding: .day, value: 1, to: .now)!
                let morning = TripClock.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
                model.departure = morning; model.deadline = morning.addingTimeInterval(9 * 3600)
                model.flexibleDeparture = false; model.returnToOrigin = true; model.targetStops = 3
                guard let origin = model.venue(canonicalIDs[0]) else { throw EngineError.invalid("Tujuan tidak tersedia.") }
                model.setOrigin(name: "Integration fixture origin", point: origin.coordinate)
                model.choices = canonicalIDs.map { id in
                    StopChoice(venueID: id, required: true, durationMinutes: 30,
                               override: .init(day: TripClock.day(morning), opens: 540, closes: 1020, publicAccessConfirmed: true))
                }
                model.message = nil
                model.computePlan()
                let planningDeadline = Date().addingTimeInterval(200)
                while model.isPlanning && Date() < planningDeadline { try await Task.sleep(for: .milliseconds(200)) }
                guard !model.isPlanning else { model.cancelPlanning(); throw EngineError.invalid("Integration exceeded its time budget.") }
                if let plan = model.plan {
                    output["plan"] = try JSONSerialization.jsonObject(with: Codec.encoder().encode(plan))
                    output["success"] = true
                } else {
                    output["success"] = false; output["error"] = model.message ?? "No plan published"
                }
                output["adviceNotice"] = model.adviceNotice
                output["syncLabel"] = model.syncLabel
            } catch { output["success"] = false; output["error"] = error.localizedDescription }
            output["elapsedSeconds"] = Date().timeIntervalSince(started)
            try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appending(path: "flow-output.json"), options: .atomic)
            // Remove the one-use fixture token file; no credentials are written into output.
            try? FileManager.default.removeItem(at: directory.appending(path: "flow-input.json"))
        }
    }
#endif
