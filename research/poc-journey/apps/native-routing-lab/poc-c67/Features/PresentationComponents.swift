import SwiftUI

enum TourStyle {
    static let accent = Color("TourAccent")
    static let ink = Color(red: 0.04, green: 0.20, blue: 0.21)
    static let canvas = Color(uiColor: .systemGroupedBackground)
}

struct ModeBadge: View {
    let mode: RunMode
    var body: some View {
        Label(mode == .simulation ? "DEMO · SIMULASI" : "PERANGKAT NYATA", systemImage: mode == .simulation ? "play.rectangle" : "iphone")
            .font(.caption2.weight(.bold)).tracking(0.7)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(mode == .simulation ? Color.orange : TourStyle.accent)
            .background((mode == .simulation ? Color.orange : TourStyle.accent).opacity(0.10), in: Capsule())
    }
}

struct CountTile: View {
    let value: Int; let title: String; let symbol: String; var color: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(color).font(.caption)
                Text(value, format: .number).font(.title3.bold()).monospacedDigit()
            }
            Text(title).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}

struct SessionSummaryCard: View {
    let session: AttendanceSession
    let mode: RunMode
    private var counts: SessionCounts { session.counts }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Label(session.closedAt == nil ? "PEMERIKSAAN AKTIF" : "PEMERIKSAAN DITUTUP", systemImage: "list.bullet.clipboard").font(.caption2.weight(.bold)).tracking(0.8); Spacer() }
                .foregroundStyle(.white.opacity(0.8))
            Text(session.name).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(counts.verified)").font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                Text("/ \(counts.expected) diperiksa").font(.headline).foregroundStyle(.white.opacity(0.85))
            }.accessibilityElement(children: .ignore).accessibilityLabel(counts.summary).accessibilityIdentifier("counts")
            ProgressView(value: Double(counts.verified), total: Double(max(1, counts.expected)))
                .tint(Color(red: 0.60, green: 0.90, blue: 0.69)).accessibilityLabel("Peserta yang diharapkan diperiksa")
            Text(session.closedAt != nil ? (session.closureNote == nil ? "Ditutup setelah review TL" : "Ditutup dengan catatan") : counts.canCloseNormally ? "Pemeriksaan lengkap. Tinjau sebelum menutup sesi." : "\(counts.unresolved) peserta belum diperiksa pada perpindahan ini.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20).foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TourStyle.ink, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct ParticipantRow: View {
    let person: Participant
    var hasLocation = false
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(person.name.prefix(1)).font(.headline)
                .frame(width: 42, height: 42).foregroundStyle(TourStyle.accent)
                .background(TourStyle.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(person.name).font(.headline); Text(person.displayID).font(.caption).foregroundStyle(.secondary) }
                Label(person.expected ? (person.verified ? "Diperiksa TL" : "Belum diperiksa") : "Tidak ikut sesi ini",
                      systemImage: person.verified ? "checkmark.circle.fill" : person.expected ? "circle.dashed" : "minus.circle")
                    .font(.caption).foregroundStyle(person.verified ? TourStyle.accent : .secondary)
                if person.followUpOpen { Label("Tindak lanjut terbuka", systemImage: "flag.fill").font(.caption).foregroundStyle(.orange) }
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if hasLocation { Image(systemName: "location.circle").foregroundStyle(TourStyle.accent).accessibilityLabel("Lokasi tambahan tersedia") }
        }.padding(.vertical, 5)
    }
}

enum LeaderSheet: String, Identifiable {
    case setup, demo, review, leaderSharing, history, qr, manual
    var id: String { rawValue }
}

struct SheetCloseButton: ToolbarContent {
    @Environment(\.dismiss) private var dismiss
    var body: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) { Button("Selesai") { dismiss() } }
    }
}
