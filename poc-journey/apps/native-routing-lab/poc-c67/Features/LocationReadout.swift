import CoreLocation
import MapKit
import SwiftUI

struct LocationReadout: View {
    let sample: LocationSample?
    var receivedAt: Date?
    var expiresAt: Date?
    var meeting: CLLocationCoordinate2D?
    var radius: Double = 100
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(alignment: .leading, spacing: 6) {
                Text(LocationRules.freshness(sample, now: timeline.date)).font(.headline).accessibilityIdentifier("location-freshness")
                if let expiresAt, timeline.date >= expiresAt { Label("Sesi berbagi berakhir", systemImage: "clock.badge.exclamationmark") }
                if let sample {
                    if sample.simulated { Label("SIMULASI — bukan GPS perangkat", systemImage: "testtube.2").foregroundStyle(.orange) }
                    Text("Diukur: \(sample.measuredAt.formatted(date: .abbreviated, time: .standard))")
                    if let receivedAt { Text("Diterima: \(receivedAt.formatted(date: .omitted, time: .standard))") }
                    Text("Akurasi dilaporkan ±\(sample.accuracy, specifier: "%.0f") m")
                    if sample.reduced { Label("Presisi terbatas", systemImage: "scope").foregroundStyle(.orange) }
                    if let meeting {
                        let distance = CLLocation(latitude: sample.latitude, longitude: sample.longitude).distance(from: CLLocation(latitude: meeting.latitude, longitude: meeting.longitude))
                        Text("Jarak perkiraan ke pin: \(distance, specifier: "%.0f") m")
                        Text(expiresAt.map { timeline.date >= $0 } == true ? "Kedekatan tidak dapat dinilai" : LocationRules.proximity(distance: distance, radius: radius, sample: sample, now: timeline.date))
                    }
                    DisclosureGroup("Detail pengukuran") {
                        Text("Koordinat: \(sample.latitude, specifier: "%.5f"), \(sample.longitude, specifier: "%.5f")")
                        Text("Sequence \(sample.sequence)")
                    }.font(.caption)
                }
                Text("Lokasi tidak otomatis mengonfirmasi kehadiran.").font(.caption).foregroundStyle(.secondary)
            }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
