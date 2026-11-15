import SwiftUI

struct GroupRouteStatusView: View {
    let session: GroupRouteSession
    let now: Date
    let fitRoute: () -> Void
    @State private var details = false
    var body: some View {
        if session.active {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    if session.engine.isCalculating { ProgressView().controlSize(.small) }
                    Text("Rute ke \(session.targetName)").font(.subheadline.bold()).lineLimit(2)
                        .accessibilityIdentifier("map-routing-destination")
                    Spacer(minLength: 4)
                    Button("Hentikan rute", systemImage: "stop.circle") { session.stop() }
                        .labelStyle(.iconOnly).accessibilityIdentifier("map-stop-routing")
                }
                Text(session.waitingReason ?? session.engine.status).font(.caption)
                    .foregroundStyle(session.inputsReady ? Color.secondary : .orange).accessibilityIdentifier("map-routing-status")
                if let route = session.engine.route, let snapshot = session.engine.routeSnapshot {
                    Text("\(Int(route.distance)) m · ETA snapshot \(max(1, Int(ceil(route.expectedTravelTime / 60)))) mnt · \(Int(max(0, now.timeIntervalSince(snapshot.requestedAt)))) dtk lalu")
                        .font(.caption.monospacedDigit()).accessibilityIdentifier("map-routing-result")
                }
                if let error = session.engine.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
                HStack {
                    Button("Lihat rute", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath", action: fitRoute)
                        .disabled(session.engine.route == nil).accessibilityIdentifier("map-fit-route")
                    Spacer()
                    Button("Detail rute") { details = true }.accessibilityIdentifier("map-routing-details")
                }.font(.caption)
            }
            .sheet(isPresented: $details) {
                NavigationStack {
                    List {
                        Section("Snapshot") {
                            Text("Rute mengikuti posisi tujuan terakhir yang layak. ETA bukan prediksi waktu bertemu. Routing tidak mengubah pemeriksaan peserta.")
                            Text("Request \(session.engine.requests) · berhasil \(session.engine.successes) · gagal \(session.engine.failures)")
                            Text("Cooldown \(Int(ceil(session.engine.remainingCooldown))) dtk · dibatalkan \(session.engine.cancellations)")
                            Text("Alasan: \(session.engine.lastReason)")
                        }
                        Section("Petunjuk dari MapKit") {
                            ForEach(Array((session.engine.route?.instructions ?? []).enumerated()), id: \.offset) { _, instruction in Text(instruction) }
                        }
                        Section {
                            ShareLink("Bagikan laporan routing", item: session.report)
                            Text("CloudKit memakai polling yang sudah ada. Routing foreground memakai sampel ≤60 dtk, bukan pelacakan tujuan setiap detik.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.navigationTitle("Detail rute").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Selesai") { details = false } } }
                }
            }
        }
    }
}
