import SwiftUI
import TripIntegration

struct JourneyItinerary: View {
    @Bindable var model: JourneyModel
    let plan: IntegratedPlan
    @State private var selectedLeg: PlannedLeg?
    @State private var mapLegID: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(plan.feasible ? "Harimu sudah tersusun." : "Ada yang perlu disesuaikan.")
                    .font(JourneyTheme.font(30, relativeTo: .title).weight(.semibold)).accessibilityIdentifier("itinerary-status")
                Text("\(TripClock.day(plan.request.departure)) · \(plan.stops.count) tempat · \(plan.request.effectiveTransport.label)")
                    .foregroundStyle(.secondary)
                if model.session.accepted?.id == plan.id {
                    Label("Itinerary tersimpan", systemImage: "checkmark.circle.fill").foregroundStyle(.green).accessibilityIdentifier("itinerary-saved")
                }
            }
            JourneyMap(plan: plan, geometry: model.geometry, roads: model.roadRoutes, focusedLegID: mapLegID)
                .frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 24))
            if mapLegID != nil { Button("Tampilkan seluruh perjalanan") { mapLegID = nil } }
            if plan.request.effectiveTransport == .transjakartaBRT {
                Label("Jalur bus mengikuti GTFS. Jalur walking mengikuti rute jalan MapKit.", systemImage: "map")
                    .font(.caption).foregroundStyle(.secondary)
            } else { Text("Jalur mobil mengikuti rute jalan MapKit. Waktu perjalanan mengikuti itinerary.").font(.caption).foregroundStyle(.secondary) }
            JourneyPanel {
                JourneyInfo(symbol: "clock", title: "Berangkat → kembali", value: "\(JourneyTime.clock(plan.request.departure)) → \(plan.finish.map(JourneyTime.clock) ?? "belum lengkap") WIB")
                Divider()
                JourneyInfo(symbol: "arrow.triangle.swap", title: "Total transportasi", value: JourneyTime.minutes(plan.travelMinutes * 60))
                Text("Termasuk jalan kaki, buffer tunggu bus, dan perjalanan bus untuk moda TJ. Waktu kunjungan terpisah.").font(.footnote).foregroundStyle(.secondary)
            }
            Text("Rencana perjalanan").font(JourneyTheme.font(24, relativeTo: .title2).weight(.semibold))
            JourneyTimelineStop(time: JourneyTime.clock(plan.request.departure), title: "Berangkat dari \(plan.request.originQuery)", subtitle: "Titik awal dan akhir perjalanan", symbol: "location.circle.fill")
            ForEach(Array(plan.legs.enumerated()), id: \.element.id) { index, leg in
                Button {
                    mapLegID = leg.id; selectedLeg = leg
                } label: {
                    JourneyTransportCard(leg: leg)
                }.buttonStyle(.plain).accessibilityIdentifier("leg-\(index)")
                if index < plan.stops.count {
                    let stop = plan.stops[index]
                    JourneyPanel {
                        JourneyTimelineStop(time: "\(JourneyTime.clock(stop.visit))–\(JourneyTime.clock(stop.leave))", title: stop.name, subtitle: stop.area, symbol: "mappin.circle.fill")
                        if stop.visit > stop.arrival {
                            Text("Tiba \(JourneyTime.clock(stop.arrival)). Menunggu jendela kunjungan hingga \(JourneyTime.clock(stop.visit)).").font(.footnote).foregroundStyle(.secondary)
                        }
                        HStack {
                            Label("\(stop.duration) menit", systemImage: "clock")
                            Spacer()
                            if let rain = stop.rainChance {
                                Label("\(Int((rain * 100).rounded()))% hujan", systemImage: "cloud.rain")
                            }
                        }.font(.footnote).foregroundStyle(.secondary)
                        Button("Tambah durasi 30 menit", systemImage: "plus.circle") { model.extend(stop, in: plan) }
                            .disabled(stop.duration > 330).frame(minHeight: 44).accessibilityIdentifier("extend-" + stop.id)
                        DisclosureGroup("Jam kunjungan & sumber") {
                            ForEach(plan.timing.filter { $0.venue.id == stop.venueID }) { timing in
                                ForEach(timing.sources) { source in Link(source.title, destination: source.url).font(.footnote) }
                            }
                            ForEach(stop.notes, id: \.self) { Text($0).font(.footnote) }
                        }.font(.footnote)
                    }
                }
            }
            if let finish = plan.finish {
                JourneyTimelineStop(time: JourneyTime.clock(finish), title: "Kembali ke \(plan.request.originQuery)", subtitle: "Batas kembali \(JourneyTime.clock(plan.request.deadline)) WIB", symbol: "flag.checkered.circle.fill")
            }
            if !plan.conflicts.isEmpty {
                JourneyPanel {
                    Label("Perlu penyesuaian", systemImage: "exclamationmark.circle").font(.headline).foregroundStyle(.red)
                    ForEach(plan.conflicts, id: \.self) { Text($0).font(.callout) }
                    Button("Ubah batas perjalanan") { model.phase = .setup }
                    JourneyBudgetPanel(model: model)
                }
            }
            JourneyPanel {
                Text("Cuaca untuk perjalanan").font(JourneyTheme.font(21, relativeTo: .title3).weight(.semibold))
                ForEach(plan.weather) { value in JourneyWeatherEvidence(value: value) }
            }
            JourneyPanel {
                DisclosureGroup("Asumsi & hal yang perlu dicek") {
                    ForEach(plan.uncertainties, id: \.self) { Text($0).font(.footnote) }
                }
                Button("Siapkan ekspor", systemImage: "square.and.arrow.up") { model.export(plan) }
                    .frame(minHeight: 44).accessibilityIdentifier("export-itinerary")
                ForEach(model.exportURLs, id: \.self) { url in ShareLink(url.lastPathComponent, item: url).accessibilityIdentifier("share-" + url.pathExtension) }
                if model.session.proposal?.id == plan.id {
                    Button("Tolak usulan", role: .destructive, action: model.reject).frame(minHeight: 44)
                }
            }
        }.sheet(item: $selectedLeg) { leg in JourneyLegDetail(plan: plan, leg: leg, geometry: model.geometry, roads: model.roadRoutes) }
    }
}

struct JourneyTimelineStop: View {
    let time: String
    let title: String
    let subtitle: String
    let symbol: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).foregroundStyle(JourneyTheme.blue).font(.title2).frame(width: 32).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(time + " WIB").font(.subheadline.weight(.semibold)).foregroundStyle(JourneyTheme.blue)
                Text(title).font(JourneyTheme.font(20, relativeTo: .title3).weight(.semibold))
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct JourneyTransportCard: View {
    let leg: PlannedLeg
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: leg.busway?.ride != nil ? "bus.fill" : leg.mode == "walking" ? "figure.walk" : "car.fill")
                .font(.title3).foregroundStyle(JourneyTheme.blue).frame(width: 32).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(leg.busway?.ride != nil ? "TransJakarta · Koridor 1" : leg.mode == "walking" ? "Jalan kaki" : "Mobil/taksi")
                    .font(JourneyTheme.font(18).weight(.semibold))
                Text(leg.to).font(.footnote).foregroundStyle(.secondary)
                if let ride = leg.busway?.ride {
                    Text("\(ride.board.name) → \(ride.alight.name)").font(.footnote)
                    Text("Estimasi GTFS · arah \(ride.headsign)").font(.caption).foregroundStyle(.secondary)
                }
                Text("\(JourneyTime.clock(leg.departure)) → \(leg.arrival.map(JourneyTime.clock) ?? "?") · \(leg.seconds.map(JourneyTime.minutes) ?? "belum tersedia")")
                    .font(.footnote.weight(.medium))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(JourneyTheme.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(JourneyTheme.blue.opacity(0.12))).contentShape(Rectangle())
    }
}

struct JourneyWeatherEvidence: View {
    let value: WeatherEvidence
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value.representative.name).font(.subheadline.weight(.semibold))
            if value.provider == "synthetic_replay" {
                Text("Cuaca contoh · Demo").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text(value.complete ? "Data cuaca tersedia" : "Cuaca belum tersedia").font(.footnote)
                if let credit = value.credit {
                    if let url = scheme == .dark ? credit.markDarkURL : credit.markLightURL {
                        AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { Text(credit.name) }.frame(height: 24)
                    }
                    Link(credit.name, destination: credit.legalURL).font(.footnote)
                }
                Text("Diperiksa \(TripClock.label(value.retrievedAt))\(value.cached ? " · cache valid" : "")").font(.caption).foregroundStyle(.secondary)
                ForEach(value.errors, id: \.self) { Text($0).font(.footnote).foregroundStyle(.orange) }
            }
        }
    }
}
