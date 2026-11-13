import SwiftUI
import VisitTiming

struct VisitTimingLabView: View {
    @State private var model = VisitTimingModel()
    @State private var showHistory = false
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section {
                    Text("Fakta tempat → opsi waktu kunjungan")
                        .font(.headline)
                    Text(
                        "11 tempat Jakarta dari halaman resmi, diperiksa 5 November 2026. Ini snapshot publikasi; belum pemeriksaan di lokasi."
                    )
                    .font(.subheadline).foregroundStyle(.secondary)
                    Text(
                        "Jam layanan, prakiraan dan aturan aplikasi ditampilkan terpisah. Routing tetap pada PoC sebelumnya."
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                }
                if let catalog = model.catalog {
                    Section("Tempat dan rencana · WIB") {
                        Picker("Tempat", selection: $model.venueID) {
                            ForEach(catalog.venues) { Text($0.name).tag($0.id) }
                        }.accessibilityIdentifier("timing-venue")
                        DatePicker("Tanggal", selection: $model.date, displayedComponents: .date)
                        Stepper(
                            "Durasi asumsi: \(model.duration) menit", value: $model.duration, in: 15 ... 180,
                            step: 15)
                        Picker("Mulai tersedia", selection: $model.startMinute) {
                            ForEach(0 ..< 24) { Text(MinuteRange.clock($0 * 60)).tag($0 * 60) }
                        }
                        Picker("Batas selesai kunjungan", selection: $model.endMinute) {
                            ForEach(1 ... 24, id: \.self) { Text(MinuteRange.clock($0 * 60)).tag($0 * 60) }
                        }
                        Picker("Tujuan waktu", selection: $model.goal) {
                            ForEach(TimingGoal.allCases) { Text($0.label).tag($0) }
                        }.accessibilityIdentifier("timing-goal")
                        Text(
                            "Durasi adalah input perencanaan. Jam keramaian dan waktu kunjung terbaik venue belum diketahui."
                        )
                        .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let venue = model.venue {
                        TimingFactsSection(venue: venue, sources: catalog.sources)
                    }
                    Section {
                        Button("Hitung dari fakta") { model.calculate() }
                            .accessibilityIdentifier("timing-calculate")
                        if model.venue?.exposure == "outdoor" {
                            Button("Ambil prakiraan aktual & hitung") { model.calculate(live: true) }
                                .accessibilityIdentifier("timing-live")
                            Text(
                                "Satu pencarian MapKit dan satu request Open-Meteo. Prakiraan berlaku 15 menit; tidak meminta GPS pengguna."
                            )
                            .font(.footnote).foregroundStyle(.secondary)
                        }
                        if model.busy {
                            ProgressView(model.message)
                            Button("Batalkan", role: .cancel) { model.cancel() }.accessibilityIdentifier(
                                "timing-cancel")
                        }
                    }
                    if !model.message.isEmpty { Text(model.message).font(.footnote) }
                    if !model.error.isEmpty { Text(model.error).foregroundStyle(.red) }
                    if let run = model.run {
                        TimingResultSection(run: run)
                        Section("Ekspor") {
                            Button("Siapkan ekspor JSON & Markdown") { Task { await model.export() } }
                                .accessibilityIdentifier("timing-export")
                            if let folder = model.exportFolder {
                                ShareLink("Bagikan JSON", item: folder.appendingPathComponent("run.json"))
                                ShareLink("Bagikan Markdown", item: folder.appendingPathComponent("REPORT.md"))
                            }
                        }
                    }
                    Section("Kasus nyata · tanggal tetap") {
                        Text(
                            "Menguji aturan yang dipublikasikan, bukan bukti pengunjung masuk pada tanggal tersebut."
                        )
                        .font(.footnote).foregroundStyle(.secondary)
                        preset("Jeda check-in Jumat · Cikini", id: "friday")
                        preset("Akhir pekan · Jatinegara", id: "weekend")
                        preset("Jam akhir pekan belum tercantum", id: "unknown")
                        preset("Pengumuman tutup sementara · MACAN", id: "suspended")
                        preset("Senin tutup · Ragunan", id: "monday")
                        preset("Dua sesi · Hutan Kota GBK", id: "split")
                    }
                }
            }
            .navigationTitle("Waktu Kunjung")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Hitung", systemImage: "clock.badge.checkmark") { model.calculate() }
                        .accessibilityIdentifier("timing-calculate-toolbar")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Riwayat", systemImage: "clock.arrow.circlepath") { showHistory = true }
                        .accessibilityIdentifier("timing-history")
                }
            }
            .sheet(isPresented: $showHistory) {
                NavigationStack {
                    List(model.history) { run in
                        Button {
                            model.restore(run)
                            showHistory = false
                        } label: {
                            VStack(alignment: .leading) {
                                Text(run.venue.name)
                                Text("\(run.request.date) · \(run.status)").font(.caption)
                            }
                        }.accessibilityIdentifier("timing-history-\(run.id)")
                    }
                    .navigationTitle("Riwayat waktu")
                    .overlay {
                        if model.history.isEmpty {
                            ContentUnavailableView("Belum ada hasil", systemImage: "clock")
                        }
                    }
                    .toolbar { Button("Tutup") { showHistory = false } }
                }
            }
            .task { await model.load() }
            .onDisappear { model.stopPendingWork() }
        }.environment(\.timeZone, TimeZone(identifier: "Asia/Jakarta")!)
    }
    private func preset(_ title: String, id: String) -> some View {
        Button(title) { model.preset(id) }.accessibilityIdentifier("timing-preset-\(id)")
    }
}

private struct TimingFactsSection: View {
    let venue: VenueFacts
    let sources: [FactSource]
    var body: some View {
        Section("Fakta yang dipublikasikan") {
            DisclosureGroup("Jam layanan dan aturan masuk") {
                ForEach(venue.schedule, id: \.weekday) { day in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            "\(weekday(day.weekday)): \(day.sessions.isEmpty ? "tutup reguler" : day.sessions.map(\.label).joined(separator: ", "))"
                        )
                        if let last = day.lastEntry {
                            Text("Batas masuk \(MinuteRange.clock(last))").font(.caption)
                        }
                        ForEach(Array(day.entryPauses.enumerated()), id: \.offset) { _, pause in
                            Text("Check-in dijeda \(pause.label); bukan jam tutup seluruh venue.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Hari yang tidak tercantum berarti belum diketahui.").font(.caption)
            }
            if let notice = venue.notice { Label(notice, systemImage: "exclamationmark.circle") }
            DisclosureGroup("Sumber dan data yang belum diketahui") {
                Text(venue.address).font(.footnote)
                ForEach(sources.filter { venue.sourceIDs.contains($0.id) }) { source in
                    Link(source.title, destination: source.url)
                    Text(
                        "Diperiksa \(VenueClock.dateString(source.checkedAt)) \(VenueClock.label(source.checkedAt)) WIB"
                    )
                    .font(.caption)
                    Text(source.method).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(venue.unknowns, id: \.self) { Text("Belum diketahui: \($0)").font(.caption) }
            }
        }
    }
    private func weekday(_ day: Int) -> String {
        ["Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu", "Minggu"][day - 1]
    }
}

private struct TimingResultSection: View {
    let run: TimingRun
    var body: some View {
        Section("Hasil · \(run.request.date) WIB") {
            Text(status).font(.headline).accessibilityIdentifier("timing-result")
            if run.options.isEmpty { Text("Belum ada usulan waktu. Periksa alasan di bawah.") }
            ForEach(run.options) { option in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(VenueClock.label(option.start))–\(VenueClock.label(option.end)) WIB").font(
                        .headline)
                    Text(option.reason).font(.subheadline)
                    if let rain = option.maxRainChance {
                        Text("Peluang hujan tertinggi selama kunjungan: \(Int((rain * 100).rounded()))%")
                            .font(.caption)
                    }
                }
            }
            DisclosureGroup("Semua rentang mulai yang memenuhi jam layanan") {
                ForEach(Array(run.validStartRanges.enumerated()), id: \.offset) { _, range in
                    Text(range.label + " WIB (waktu mulai, interval 15 menit)").font(.caption)
                }
            }
            if let environment = run.environment {
                Text("Konteks aktual: \(environment.provider)").font(.subheadline)
                Text("Pin \(environment.locationName) · \(environment.latitude), \(environment.longitude)")
                    .font(.caption)
                Text(
                    "Diambil \(VenueClock.dateString(environment.fetchedAt)) \(VenueClock.label(environment.fetchedAt)) WIB · berlaku sampai \(VenueClock.label(environment.validUntil)) WIB"
                ).font(.caption)
                if let sunset = environment.sunset {
                    Text("Sunset provider: \(VenueClock.label(sunset)) WIB").font(.caption)
                }
                Link(environment.attribution, destination: environment.attributionURL).font(.caption)
            }
            ForEach(Array(run.warnings.enumerated()), id: \.offset) { _, warning in
                Text(warning).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    private var status: String {
        switch run.status {
        case "regular_hours_options": "Opsi menurut jam layanan"
        case "context_ranked": "Opsi menurut konteks yang tersedia"
        case "suspended": "Usulan ditahan: pengumuman penutupan"
        case "closed_regular": "Tutup menurut jadwal reguler"
        case "hours_unknown": "Jam layanan belum diketahui"
        case "needs_recheck": "Sumber perlu diperiksa ulang"
        case "no_window": "Belum ada waktu yang memenuhi batas"
        default: "Konteks belum cukup untuk tujuan ini"
        }
    }
}
