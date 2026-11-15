import SwiftUI
import TripIntegration

struct JourneyLegDetail: View {
    let plan: IntegratedPlan
    let leg: PlannedLeg
    let geometry: BuswayGeometryCatalog?
    let roads: JourneyRoadRoutes
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let journey = leg.busway, let ride = journey.ride {
                        busContent(journey, ride: ride)
                    } else {
                        Text(leg.mode == "walking" ? "Jalan kaki ke tujuan berikutnya" : "Perjalanan mobil/taksi")
                            .font(JourneyTheme.font(30, relativeTo: .title).weight(.semibold))
                        Text("\(leg.from) → \(leg.to)").foregroundStyle(.secondary)
                        JourneyMap(plan: plan, geometry: geometry, roads: roads, focusedLegID: leg.id).frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 24))
                        Text("Jalur mengikuti rute jalan yang tersedia.").font(.footnote).foregroundStyle(.secondary)
                        JourneyPanel {
                            JourneyInfo(symbol: "clock", title: "Estimasi durasi", value: leg.seconds.map(JourneyTime.minutes) ?? "Belum tersedia")
                            JourneyInfo(symbol: "arrow.right", title: "Waktu", value: "\(JourneyTime.clock(leg.departure)) → \(leg.arrival.map(JourneyTime.clock) ?? "?") WIB")
                            Text(plan.evidenceMode == "synthetic_replay" ? "Waktu dan lokasi contoh untuk Demo." : "Estimasi perjalanan dari MapKit.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }.background(JourneyTheme.canvas).navigationTitle("Detail perjalanan").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Selesai") { dismiss() }.accessibilityIdentifier("close-leg") } }
                .tint(JourneyTheme.blue)
        }
    }
    @ViewBuilder private func busContent(_ journey: BuswayJourney, ride: BuswayRide) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(ride.pattern.effectiveRouteID).font(JourneyTheme.font(32, relativeTo: .title).weight(.semibold))
                .foregroundStyle(.white).padding(18).background(JourneyTheme.blue, in: RoundedRectangle(cornerRadius: 20))
            VStack(alignment: .leading, spacing: 6) {
                Text("TransJakarta").font(JourneyTheme.font(28, relativeTo: .title).weight(.semibold))
                Text("\(ride.pattern.effectiveCategory) · arah \(ride.headsign)").font(.callout)
                Text("Estimasi GTFS\(plan.evidenceMode == "synthetic_replay" ? " · Demo" : "")").font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier("tj-detail")
        JourneyMap(plan: plan, geometry: geometry, roads: roads, focusedLegID: leg.id).frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 24))
        if let segment = try? geometry?.segment(for: ride, source: journey.source) {
            Text("\(segment.stops.count - 1) perpindahan halte · geometri GTFS sesuai arah bus").font(.footnote).foregroundStyle(.secondary)
        } else { Text("Geometri bus belum tersedia untuk sumber ini. Peta menampilkan pin halte.").font(.footnote).foregroundStyle(.orange) }
        Text("Jalur walking mengikuti geometri MapKit yang tersedia.").font(.caption).foregroundStyle(.secondary)
        JourneyPanel {
            JourneyInfo(symbol: "clock", title: "Total ruas", value: JourneyTime.minutes(journey.seconds))
            Divider()
            JourneyInfo(symbol: "figure.walk", title: "Jalan kaki", value: JourneyTime.minutes(journey.walkingSeconds))
            JourneyInfo(symbol: "hourglass", title: "Buffer tunggu bus", value: JourneyTime.minutes(journey.waitingSeconds))
            JourneyInfo(symbol: "bus", title: "Di dalam bus", value: JourneyTime.minutes(journey.ridingSeconds))
        }
        JourneyTimelineStop(time: JourneyTime.clock(journey.departure), title: "Jalan ke \(ride.board.name)", subtitle: "\(JourneyTime.minutes(journey.access.seconds)) · dari \(leg.from)", symbol: "figure.walk")
        JourneyTimelineStop(time: JourneyTime.clock(ride.boardAt), title: "Naik di \(ride.board.name)", subtitle: "Platform \(ride.board.platform.isEmpty ? "belum dicantumkan" : ride.board.platform) · \(ride.board.id)", symbol: "bus.fill")
        Text("Buffer satu headway penuh \(JourneyTime.minutes(Double(ride.frequency.headway))) setelah tiba di halte atau layanan dimulai.")
            .font(.footnote).foregroundStyle(.secondary)
        if let segment = try? geometry?.segment(for: ride, source: journey.source) {
            DisclosureGroup("Halte yang dilewati") {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(segment.stops.enumerated()), id: \.offset) { index, stop in
                        Label(stop.name, systemImage: index == 0 || index == segment.stops.count - 1 ? "circle.inset.filled" : "circle")
                            .font(.callout).foregroundStyle(index == 0 || index == segment.stops.count - 1 ? Color.primary : Color.secondary)
                    }
                }.padding(.vertical, 12)
            }.accessibilityIdentifier("tj-stop-list")
        }
        JourneyTimelineStop(time: JourneyTime.clock(ride.alightAt), title: "Turun di \(ride.alight.name)", subtitle: "Platform \(ride.alight.platform.isEmpty ? "belum dicantumkan" : ride.alight.platform) · \(ride.alight.id)", symbol: "bus.fill")
        if let connection = journey.connection {
            JourneyPanel {
                Text("Pindah ke TJ \(connection.ride.pattern.effectiveRouteID)").font(.headline)
                Text("Walking \(JourneyTime.minutes(connection.walk.seconds)), buffer perpindahan \(JourneyTime.minutes(connection.bufferSeconds)), kemudian satu headway penuh.").font(.footnote)
                Text(connection.evidence).font(.caption).foregroundStyle(.secondary)
                Text("\(connection.ride.pattern.effectiveCategory) · arah \(connection.ride.headsign)").font(.callout)
                JourneyInfo(symbol: "bus", title: "Naik di \(connection.ride.board.name)", value: JourneyTime.clock(connection.ride.boardAt))
                JourneyInfo(symbol: "bus", title: "Turun di \(connection.ride.alight.name)", value: JourneyTime.clock(connection.ride.alightAt))
                Text("Platform \(connection.ride.board.platform) · \(connection.ride.board.id) → \(connection.ride.alight.id)").font(.caption)
                DisclosureGroup("Halte bus lanjutan") {
                    ForEach(connection.ride.pattern.calls.filter { $0.sequence >= connection.ride.boardSequence && $0.sequence <= connection.ride.alightSequence }, id: \.sequence) { call in
                        Text(call.stopID).font(.caption)
                    }
                }
                Text("Pintu masuk, aksesibilitas dan penyeberangan perlu diperiksa. Geometri bus lanjutan mungkin belum tersedia.").font(.footnote).foregroundStyle(.secondary)
            }.accessibilityIdentifier("tj-transfer")
        }
        JourneyTimelineStop(time: JourneyTime.clock(journey.arrival), title: "Tiba di \(leg.to)", subtitle: "\(JourneyTime.minutes(journey.egress?.seconds ?? 0)) jalan kaki dari halte turun", symbol: "mappin.circle.fill")
        JourneyPanel {
            Text("Periksa arah dan akses halte sebelum berangkat.").font(.callout.weight(.semibold))
            Text("Estimasi mengikuti jadwal GTFS. Kondisi bus, penyeberangan, pintu masuk, dan layanan hari libur dapat berubah.").font(.footnote).foregroundStyle(.secondary)
            Link(journey.source.publisher + " · sumber GTFS", destination: journey.source.attributionURL)
            Link("CC BY 4.0", destination: journey.source.licenseURL).font(.footnote)
            Text("Data diperiksa \(TripClock.label(journey.source.checkedAt))").font(.caption).foregroundStyle(.secondary)
        }
    }
}
