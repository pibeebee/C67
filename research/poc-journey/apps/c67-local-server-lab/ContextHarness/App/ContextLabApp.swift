import SwiftUI
import PlaceContextEngine
import DynamicTripContracts

@main struct ContextLabApp: App {
    @State private var model = ContextLabModel()
    @State private var personal = PersonalLabModel()
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--context-legacy") {
                ContextLabView(model: model).task { model.loadSelectionIfRequested() }
            } else if !personal.simpleLayout {
                PersonalRootView(model: personal, diagnostics: model)
            } else {
                SimplePersonalRoot(model: personal, diagnostics: model)
            }
        }
    }
}

struct ContextLabView: View {
    @Bindable var model: ContextLabModel
    @FocusState private var queryFocused: Bool
    var body: some View {
        TabView(selection: $model.selectedTab) {
            NavigationStack {
                Form {
                    Section {
                        Text(model.status).accessibilityIdentifier("operation-status")
                        if model.busy { ProgressView() }
                        if let error = model.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("operation-error") }
                    }
                    searchSection
                    if let pending = model.pending {
                        Section("Konfirmasi identitas Apple") {
                            Text(pending.name).font(.headline)
                            Text(pending.address).font(.caption)
                            Text("Google Maps · Jam \(pending.hours.state)").font(.caption)
                            Text(pending.hours.source).font(.caption2)
                            ForEach(Array(pending.hours.intervals.enumerated()), id: \.offset) { _, interval in
                                Text("\(ContextLabModel.time(interval.start))–\(ContextLabModel.time(interval.end)) WIB\(ContextClock.label(interval.start) != ContextClock.label(interval.end) ? " (hari berikutnya)" : "")").font(.caption)
                            }
                            ForEach(pending.hours.warnings, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }

                            if let url = pending.googleMapsURL.flatMap(URL.init(string:)) { Link("Lihat sumber Google", destination: url) }
                            if pending.appleCandidates.isEmpty { Text("Lokasi Apple belum ditemukan. Perjelas query Apple dan pilih hasil Google lagi.") }
                            ForEach(Array(pending.appleCandidates.enumerated()), id: \.element.id) { index, candidate in
                                Button { model.confirm(candidate) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(candidate.name)
                                        Text(candidate.address).font(.caption)
                                        Text("Jarak antar-pin \(Int(candidate.distanceFromGoogleMeters)) m · Konfirmasi lokasi ini").font(.caption2)
                                    }
                                }.accessibilityIdentifier("apple-option-\(index)").disabled(!candidate.canConfirm)
                            }
                        }
                    }
                    Section("Rencana perjalanan") {
                        if let origin = model.origin { Text("Awal dan kembali · \(origin.prepared.name)").accessibilityIdentifier("chosen-origin") }
                        else { Text("Lokasi awal belum dipilih") }
                        DatePicker("Tanggal", selection: $model.day, in: Date()..., displayedComponents: .date)
                        Picker("Berangkat WIB", selection: $model.departureMinute) {
                            ForEach([480, 540, 600, 660, 720], id: \.self) { Text(String(format: "%02d.00", $0 / 60)).tag($0) }
                        }
                        Picker("Kembali WIB", selection: $model.deadlineMinute) {
                            ForEach([960, 1080, 1140, 1200], id: \.self) { Text(String(format: "%02d.00", $0 / 60)).tag($0) }
                        }
                        Stepper("Maksimal menunggu \(model.waitingMinutes) menit", value: $model.waitingMinutes, in: 0 ... 120, step: 5)
                        Picker("Grid awal kunjungan", selection: $model.grid) { Text("5 menit").tag(5); Text("15 menit").tag(15) }
                        Picker("Metode", selection: $model.policy) {
                            Text("First-feasible").tag(ContextSearchPolicy.firstFeasible)
                            Text("Selektif").tag(ContextSearchPolicy.selectiveOrders)
                            Text("Beam").tag(ContextSearchPolicy.beam)
                        }
                    }
                    ForEach($model.stops) { $stop in
                        Section(stop.place.prepared.name) {
                            Picker("Durasi", selection: $stop.durationMinutes) {
                                ForEach([15, 30, 45, 60, 90, 120], id: \.self) { Text("\($0) menit").tag($0) }
                            }
                            Picker("Aktivitas", selection: $stop.exposure) {
                                Text("Belum diketahui").tag(ActivityExposure.unknown)
                                Text("Indoor").tag(ActivityExposure.indoor)
                                Text("Outdoor").tag(ActivityExposure.outdoor)
                                Text("Campuran").tag(ActivityExposure.mixed)
                            }
                            Toggle("Utamakan mulai 15–16 WIB", isOn: $stop.afternoon)
                            Toggle("Hindari hujan", isOn: $stop.avoidRain)
                            Button("Hapus tujuan", role: .destructive) { model.stops.removeAll { $0.id == stop.id } }
                        }
                    }
                    Section {
                        Button("Buat itinerary") { model.plan() }.accessibilityIdentifier("plan-button")
                            .disabled(model.busy || model.origin == nil || model.stops.isEmpty)
                        Button("Benchmark live grid 15 dan 5 menit") { model.runSelectedBenchmark() }
                            .accessibilityIdentifier("live-benchmark-button").disabled(model.busy || model.origin == nil || model.stops.isEmpty)
                    }
                    Text(model.benchmarkProgress).accessibilityIdentifier(model.benchmarkComplete ? "live-benchmark-complete" : "live-benchmark-progress")
                    if let output = model.output { resultSections(output) }
                }.navigationTitle("Context Lab")
            }.tabItem { Label("Cari & Rencana", systemImage: "magnifyingglass") }.tag(0)
            NavigationStack {
                List {
                    Section {
                        Text("Cuaca dan jam pada skenario ini merupakan data sintetis yang dikontrol.").font(.callout)
                        if let error = model.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("operation-error") }
                        Text(model.benchmarkProgress).accessibilityIdentifier(model.benchmarkComplete ? "benchmark-complete" : "benchmark-progress")
                        Button("Jalankan 54 pengujian") { model.runControlled() }.accessibilityIdentifier("controlled-benchmark-button").disabled(model.busy)
                    }
                    ForEach(Array(model.controlled.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.response.scenario.title)
                            Text("\(row.response.output.itinerary.status) · \(row.clientSeconds, specifier: "%.3f") dtk").font(.caption)
                            Text(row.response.output.itinerary.visits.map(\.placeID).joined(separator: " → ")).font(.caption2)
                        }
                    }
                }.navigationTitle("Eksperimen")
            }.tabItem { Label("Eksperimen", systemImage: "testtube.2") }.tag(1)
        }
    }

    private var searchSection: some View {
        Section("Cari tempat dari Google Places") {
            Toggle("Pilih sebagai lokasi awal", isOn: $model.choosingOrigin).accessibilityIdentifier("origin-toggle")
            TextField("Nama tempat, misalnya GBK", text: $model.query).autocorrectionDisabled().focused($queryFocused).accessibilityIdentifier("place-query")
            TextField("Query Apple opsional", text: $model.appleQuery).autocorrectionDisabled().accessibilityIdentifier("apple-query")
            Button("Cari tempat") { queryFocused = false; model.search() }.accessibilityIdentifier("search-button").disabled(model.busy || model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ForEach(Array(model.results.enumerated()), id: \.offset) { index, place in
                if let id = place.id {
                    Button { model.prepare(id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.displayName?.text ?? "Nama belum tersedia")
                            Text(place.formattedAddress ?? "").font(.caption)
                        }
                    }.accessibilityIdentifier("search-result-\(index)")
                }
            }
        }
    }
    @ViewBuilder private func resultSections(_ output: DynamicPlanResponse) -> some View {
        Section("Hasil · \(output.metrics.evidenceMode)") {
            Text(output.itinerary.status).accessibilityIdentifier("itinerary-status")
            Text("Rute \(output.metrics.routingSeconds, specifier: "%.2f") dtk · \(output.metrics.etaCalls) ETA")
            Text("Menunggu \(output.itinerary.waitingSeconds / 60, specifier: "%.1f") menit")
            if let penalty = output.itinerary.penaltyByPriority.first, penalty > 0 {
                Text("Preferensi waktu belum terpenuhi · total selisih \(Int(penalty)) menit dari rentang pilihan.")
                    .foregroundStyle(.orange).accessibilityIdentifier("unmet-time-preference")
            }
            if output.itinerary.searchTruncated { Text("Pencarian dibatasi; hasil ini belum tentu pilihan terbaik.").font(.caption) }
            ForEach(output.itinerary.warnings, id: \.self) { Text($0).font(.caption2) }

            if output.itinerary.visits.isEmpty {
                ForEach(output.itinerary.contexts, id: \.placeID) { context in Text("\(context.placeID) · \(context.status)").font(.caption) }
            }
            ForEach(output.itinerary.visits, id: \.placeID) { visit in
                let name = model.stops.first { $0.place.prepared.googlePlaceID == visit.placeID }?.place.prepared.name ?? visit.placeID
                VStack(alignment: .leading) {
                    Text(name).font(.headline)
                    Text("\(ContextLabModel.time(visit.visit.start))–\(ContextLabModel.time(visit.visit.end)) WIB")
                    ForEach(visit.visit.unknowns, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
            }
            ForEach(output.weatherAttributions, id: \.self) { Text($0).font(.caption2) }
            Text("Fakta tempat dari Google Maps. Kunjungan dan akses masuk masih perlu dikonfirmasi.").font(.caption2)
        }
    }
}
