import MapKit
import SwiftUI
import WeatherKit

struct NativeTripReportView: View {
    let report: NativeTripReport
    let attribution: WeatherAttribution?
    @State private var mapRoutes = NativeTripMapRouteStore()
    var body: some View {
        List {
            Section {
                Text(report.status).font(.headline)
                if report.draft.isJakartaProfile {
                    Text("Jakarta · ETA mobil/taksi").font(.footnote)
                }
                if let note = report.optimizerNote {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
                Text("\(report.draft.clock(report.draft.departure)) · \(report.draft.timeZoneID)")
                Text(report.draft.deadlineSummary).font(.footnote)
                Text("MapKit: \(report.requests) permintaan ETA. Tidak menggunakan AI.").font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                if let candidate = report.fastest {
                    NavigationLink {
                        NativeTripMapView(candidate: candidate, draft: report.draft, routes: mapRoutes)
                    } label: {
                        Label("Peta seluruh itinerary", systemImage: "map")
                    }
                    Text("\(candidate.legs.count) ruas · warna per ruas, ikon moda dan pin bernomor")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    DisclosureGroup("Peta tempat") {
                        Map {
                            ForEach(report.draft.allPoints) { point in
                                if let coordinate = point.coordinate { Marker(point.title, coordinate: coordinate) }
                            }
                        }
                        .mapControls {
                            MapCompass()
                            MapScaleView()
                        }
                        .frame(height: 240)
                    }
                }
            }
            if let fastest = report.fastest {
                Section("Durasi trip terpendek yang diperiksa") {
                    NativeTripCandidateSummary(candidate: fastest, draft: report.draft)
                    NavigationLink("Lihat rincian semua ruas") {
                        NativeTripCandidateView(candidate: fastest, draft: report.draft, mapRoutes: mapRoutes)
                    }
                }
            } else {
                Section("Data yang masih kurang") {
                    Text(
                        "Belum ada kandidat lengkap. Buka kandidat untuk melihat ruas yang memerlukan data atau moda lain."
                    )
                    ForEach(Array(Set(report.candidates.flatMap(\.conflicts))).sorted(), id: \.self) {
                        Text($0).font(.footnote).foregroundStyle(.red)
                    }
                    ForEach(report.candidates) { candidate in
                        NavigationLink("Kandidat · \(candidate.legs.count) ruas diperiksa") {
                            NativeTripCandidateView(
                                candidate: candidate, draft: report.draft, mapRoutes: mapRoutes)
                        }
                    }
                }
            }
            Section {
                DisclosureGroup("Cuaca") {
                    Text(report.weatherNote)
                    if let candidate = report.weatherChoice {
                        NativeTripCandidateSummary(candidate: candidate, draft: report.draft)
                        NavigationLink("Rincian kandidat cuaca") {
                            NativeTripCandidateView(
                                candidate: candidate, draft: report.draft, mapRoutes: mapRoutes)
                        }
                    }
                    ForEach(report.forecasts, id: \.pointID) { forecast in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(
                                report.draft.allPoints.first(where: { $0.id == forecast.pointID })?.title
                                    ?? forecast.pointID
                            ).font(.subheadline)
                            Text(forecast.status).font(.caption.monospaced())
                            if let provider = forecast.provider {
                                Text("Sumber: \(provider.title)").font(.caption)
                            }
                            Text(forecast.note).font(.caption).foregroundStyle(.secondary)
                            if let at = forecast.fetchedAt {
                                Text("Sumber diperbarui \(report.draft.clock(at))").font(.caption)
                            } else if let at = forecast.retrievedAt {
                                Text("Diambil \(report.draft.clock(at))").font(.caption)
                            }
                        }
                    }
                    if report.forecasts.contains(where: { $0.provider == .weatherKit }), let attribution {
                        NativeTripWeatherAttribution(attribution: attribution)
                    } else if report.forecasts.contains(where: { $0.provider == .weatherKit }),
                              let credit = report.storedWeatherCredit
                    {
                        NativeTripSavedWeatherAttribution(credit: credit)
                    }
                    if report.forecasts.contains(where: { $0.provider == .openMeteo }) {
                        NativeTripOpenMeteoAttribution()
                    }
                }
            }
            Section {
                DisclosureGroup("Tentang hasil PoC") {
                    Text(
                        "Kandidat yang diperiksa dibandingkan berdasarkan kelayakan lalu total perjalanan, menunggu dan singgah. ETA mengikuti jam tiap ruas; data terbatas belum membuktikan optimum global."
                    )
                    Text(
                        "Transit berupa ETA; nama jalur, detail transfer, dan jadwal kereta belum diverifikasi. Paparan cuaca saat transit masih unknown sehingga rekomendasi cuaca dapat ditunda."
                    )
                    Text(
                        "Default 30 menit, batas berjalan, paparan campuran, bobot hujan dan tambahan waktu merupakan asumsi yang dapat diubah. Jam operasional hanya diperiksa jika diisi manual."
                    )
                }.font(.footnote)
            }
        }
        .navigationTitle("Hasil itinerary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ShareLink(item: report.textReport) { Label("Bagikan", systemImage: "square.and.arrow.up") }
        }
    }
}

private struct NativeTripCandidateSummary: View {
    let candidate: NativeTripCandidate
    let draft: NativeTripDraft
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                candidate.feasible ? "Memenuhi batas yang diketahui" : "Ada konflik / data belum lengkap",
                systemImage: candidate.feasible ? "checkmark.circle" : "exclamationmark.triangle")
            if candidate.complete {
                Text(
                    "Perpindahan \(candidate.travelMinutes, specifier: "%.1f") menit · singgah \(candidate.dwellMinutes) menit"
                )
                Text("Durasi trip \(candidate.elapsedMinutes, specifier: "%.1f") menit")
                if candidate.waitingMinutes > 0 {
                    Text("Menunggu buka \(candidate.waitingMinutes, specifier: "%.1f") menit")
                }
                if let finish = candidate.finish { Text("Selesai \(draft.clock(finish))") }
            } else {
                Text("Durasi total belum diketahui · jadwal belum lengkap")
                Text("Periksa ruas yang gagal, lalu kembali ke Rencana untuk menghitung ulang.").font(
                    .footnote)
            }
        }.font(.subheadline)
    }
}

private struct NativeTripCandidateView: View {
    let candidate: NativeTripCandidate
    let draft: NativeTripDraft
    let mapRoutes: NativeTripMapRouteStore
    var body: some View {
        List {
            Section { NativeTripCandidateSummary(candidate: candidate, draft: draft) }
            Section {
                NavigationLink {
                    NativeTripMapView(candidate: candidate, draft: draft, routes: mapRoutes)
                } label: {
                    Label("Peta kandidat ini", systemImage: "map")
                }
            }
            Section("Urutan dan perpindahan") {
                ForEach(Array(candidate.legs.enumerated()), id: \.element.id) { index, leg in
                    NavigationLink {
                        NativeTripLegView(leg: leg, draft: draft)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(
                                "\(index + 1). \(leg.to.title)\(leg.isReturn ? (draft.returnsToOrigin ? " · kembali" : " · titik akhir") : "")"
                            ).font(
                                .headline)
                            if let chosen = leg.chosen, let seconds = chosen.seconds {
                                Label(
                                    "\(chosen.mode.title) · \(Int(ceil(seconds / 60))) menit",
                                    systemImage: chosen.mode.symbol)
                            } else {
                                Label("Data moda belum cukup", systemImage: "exclamationmark.triangle")
                            }
                            if let arrival = leg.arrival {
                                Text(
                                    "Tiba \(draft.clock(arrival)) · singgah \(leg.dwellMinutes) menit (\(leg.dwellSource))"
                                )
                                if let visit = leg.visit, visit > arrival {
                                    Text(
                                        "Menunggu buka \(visit.timeIntervalSince(arrival) / 60, specifier: "%.1f") menit"
                                    )
                                }
                            }
                            if let chance = leg.rainChance {
                                Text(
                                    "Peluang hujan saat kunjungan \(chance, format: .percent.precision(.fractionLength(0)))"
                                )
                                if leg.weatherProvider == .openMeteo { NativeTripOpenMeteoAttribution() }
                            }
                        }.font(.subheadline)
                    }
                }
            }
            if !candidate.complete {
                Section("Belum dijadwalkan") {
                    let visited = Set(
                        candidate.legs.filter { $0.arrival != nil && !$0.isReturn }.map { $0.to.id })
                    ForEach(draft.stops.filter { !visited.contains($0.id) }) { Text($0.point.title) }
                    Text(
                        "Semua tujuan tetap dipertahankan pada input. Perhitungan berhenti saat data atau waktu tidak mencukupi."
                    ).font(.footnote)
                }
            }
            if !candidate.conflicts.isEmpty {
                Section("Konflik") {
                    ForEach(candidate.conflicts, id: \.self) { Text($0).foregroundStyle(.red) }
                }
            }
            if !candidate.uncertainties.isEmpty {
                Section("Data bersyarat") {
                    ForEach(Array(Set(candidate.uncertainties)).sorted(), id: \.self) {
                        Text($0).font(.footnote)
                    }
                }
            }
        }
        .navigationTitle("Rincian kandidat")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NativeTripLegView: View {
    let leg: NativeTripLeg
    let draft: NativeTripDraft
    var body: some View {
        List {
            Section("Perpindahan") {
                LabeledContent("Dari", value: leg.from.title)
                LabeledContent("Ke", value: leg.to.title)
                LabeledContent("Berangkat", value: draft.clock(leg.departure))
                if let arrival = leg.arrival { LabeledContent("Tiba", value: draft.clock(arrival)) }
                if let visit = leg.visit { LabeledContent("Mulai singgah", value: draft.clock(visit)) }
                if let arrival = leg.arrival, let visit = leg.visit, visit > arrival {
                    LabeledContent(
                        "Menunggu buka",
                        value: String(format: "%.1f menit", visit.timeIntervalSince(arrival) / 60))
                }
                if let leave = leg.leave { LabeledContent("Lanjut", value: draft.clock(leave)) }
                LabeledContent("Singgah", value: "\(leg.dwellMinutes) menit · \(leg.dwellSource)")
            }
            if !leg.isReturn, let stop = draft.stops.first(where: { $0.id == leg.to.id }),
               stop.role == .visit
            {
                Section("Jam operasional tujuan") {
                    Text(stop.opening?.summary ?? "Belum diisi; ketersediaan saat tiba belum dipastikan.")
                    Text("Input manual untuk tanggal trip · \(draft.timeZoneID)")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let note = stop.opening?.sourceNote { Text(note).font(.footnote) }
                }
            }
            ForEach(leg.options) { option in
                Section(option.mode.title) {
                    if let seconds = option.seconds {
                        LabeledContent("Estimasi waktu", value: "\(Int(ceil(seconds / 60))) menit")
                    }
                    Text(option.status).font(.caption.monospaced())
                    Text(option.note).font(.footnote)
                    Button("Periksa di Apple Maps", systemImage: "map") {
                        NativeTripAppleServices.openMaps(from: leg.from, to: leg.to, mode: option.mode)
                    }
                }
            }
            if !leg.notes.isEmpty {
                Section("Catatan") { ForEach(leg.notes, id: \.self) { Text($0).font(.footnote) } }
            }
        }
        .navigationTitle(leg.to.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NativeTripWeatherAttribution: View {
    let attribution: WeatherAttribution
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(
                url: colorScheme == .dark
                    ? attribution.combinedMarkLightURL : attribution.combinedMarkDarkURL
            ) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Text(attribution.serviceName)
            }
            .frame(height: 22)
            Link("Sumber data cuaca dan atribusi", destination: attribution.legalPageURL)
                .font(.caption)
        }
    }
}

struct NativeTripOpenMeteoAttribution: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Link("Data cuaca: Open-Meteo", destination: URL(string: "https://open-meteo.com/")!)
            Link(
                "Lisensi CC BY 4.0",
                destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
            Text(
                "Peluang presipitasi dikonversi ke 0–1 dan interval satu jam sebelumnya untuk perhitungan paparan."
            )
            .foregroundStyle(.secondary)
        }.font(.caption)
    }
}

private struct NativeTripSavedWeatherAttribution: View {
    let credit: NativeTripWeatherCredit
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(
                url: colorScheme == .dark ? credit.combinedMarkLightURL : credit.combinedMarkDarkURL
            ) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Text(credit.serviceName)
            }
            .frame(height: 22)
            Link("Sumber data cuaca dan atribusi", destination: credit.legalPageURL).font(.caption)
        }
    }
}
