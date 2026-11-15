import SwiftUI

private enum ParticipantEdit: String, Identifiable {
    case undo, exclude, followUp, resolve
    var id: String { rawValue }
    var title: String {
        switch self { case .undo: "Batalkan pemeriksaan"; case .exclude: "Tidak ikut sesi ini"; case .followUp: "Tindak lanjut peserta"; case .resolve: "Selesaikan tindak lanjut" }
    }
    var action: AttendanceAction {
        switch self { case .undo: .undoVerification; case .exclude: .exclude; case .followUp: .openFollowUp; case .resolve: .resolveFollowUp }
    }
}

struct ParticipantDetailView: View {
    let app: POCController
    let sessionID: UUID
    let participantID: String
    @State private var edit: ParticipantEdit?
    private var session: AttendanceSession? { app.store.state.sessions.first { $0.id == sessionID } }
    private var person: Participant? { session?.participants.first { $0.id == participantID } }
    var body: some View {
        List {
            ErrorNotice(app: app)
            if let p = person {
                Section {
                    ParticipantRow(person: p)
                    if let at = p.verifiedAt { Text("Pemeriksaan TL tercatat \(at.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary) }
                    if !p.expected { Label(p.exclusionReason, systemImage: "note.text"); Text(p.arrangement).font(.subheadline).foregroundStyle(.secondary) }
                }
                if session?.closedAt == nil {
                    Section {
                        Button {
                            app.attempt { try app.store.apply(.verify, participantID: participantID) }
                        } label: {
                            Label(p.verified ? "Sudah diperiksa TL" : "Tandai diperiksa", systemImage: "checkmark.circle")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                        }.buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 14))
                            .disabled(!p.expected || p.verified).accessibilityIdentifier("verify-\(p.id)")
                        Text("Gunakan setelah melihat dan memeriksa peserta langsung pada titik pemeriksaan sesi ini.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Tindak lanjut") {
                        if p.followUpOpen {
                            Label("Kasus terbuka", systemImage: "flag.fill").foregroundStyle(.orange)
                            Text(p.followUp)
                            Button("Selesaikan dengan hasil", systemImage: "checkmark.bubble") { edit = .resolve }
                        } else {
                            if !p.followUpOutcome.isEmpty { Label(p.followUpOutcome, systemImage: "checkmark.bubble") }
                            Button("Buka tindak lanjut", systemImage: "flag") { edit = .followUp }.accessibilityIdentifier("open-follow-up")
                        }
                        Text("Pemeriksaan dan penyelesaian kasus dicatat secara terpisah.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Keikutsertaan & koreksi") {
                        if p.expected { Button("Tidak ikut sesi ini", systemImage: "minus.circle") { edit = .exclude }.accessibilityIdentifier("exclude-participant") }
                        else { Button("Kembali Diharapkan", systemImage: "arrow.uturn.backward") { app.attempt { try app.store.apply(.include, participantID: participantID) } } }
                        if p.verified { Button("Batalkan pemeriksaan", systemImage: "arrow.uturn.backward", role: .destructive) { edit = .undo } }
                    }
                } else { Section { Label("Sesi ditutup · hanya baca", systemImage: "lock") } }
                if app.store.state.mode == .simulation && p.id == "P01" || app.store.state.cloudBindings.contains(where: { $0.participantID == p.id }) {
                    Section("Lokasi tambahan") { LocationReadout(sample: app.sample(for: p.id), receivedAt: app.store.state.mode == .simulation ? app.receivedAt : app.locations[p.id]?.receivedAt, expiresAt: app.store.state.mode == .simulation ? app.remoteExpires : app.locations[p.id]?.expiresAt) }
                }
            }
        }.navigationTitle(person?.name ?? participantID).navigationBarTitleDisplayMode(.inline)
            .sheet(item: $edit) { operation in ParticipantActionSheet(app: app, sessionID: sessionID, participantID: participantID, operation: operation) }
    }
}

private struct ParticipantActionSheet: View {
    let app: POCController
    let sessionID: UUID
    let participantID: String
    let operation: ParticipantEdit
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var arrangement = ""
    var body: some View {
        NavigationStack {
            Form {
                ErrorNotice(app: app)
                Section {
                    Text(app.store.state.sessions.first(where: { $0.id == sessionID })?.participants.first(where: { $0.id == participantID }).map { "\($0.name) · \($0.displayID)" } ?? "Peserta").font(.headline)
                    TextField(operation == .resolve ? "Hasil tindak lanjut" : "Alasan / konteks", text: $reason, axis: .vertical)
                        .lineLimit(3 ... 6).accessibilityIdentifier("action-reason")
                    if operation == .exclude { TextField("Pengaturan yang dicatat TL", text: $arrangement, axis: .vertical).lineLimit(2 ... 4).accessibilityIdentifier("action-arrangement") }
                } footer: { Text(operation == .exclude ? "Catat alasan dan pengaturan peserta, bukan sekadar mengurangi angka yang diharapkan." : "Catatan disimpan pada riwayat sesi ini. Tidak mengubah status lain secara otomatis.") }
                Button("Simpan catatan") {
                    app.attempt {
                        guard app.store.state.activeIndex.map({ app.store.state.sessions[$0].id }) == sessionID else { throw POCError.message("Sesi berubah; buka kembali peserta dari sesi aktif.") }
                        try app.store.apply(operation.action, participantID: participantID, reason: reason, arrangement: arrangement)
                        dismiss()
                    }
                }.disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (operation == .exclude && arrangement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    .accessibilityIdentifier("save-participant-action")
            }.navigationTitle(operation.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } } }
        }
    }
}

struct ReviewSessionView: View {
    let app: POCController
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    private var session: AttendanceSession { app.store.state.sessions.last! }
    var body: some View {
        NavigationStack {
            Form {
                ErrorNotice(app: app)
                Section {
                    Text(session.counts.canCloseNormally ? "Pemeriksaan lengkap." : "Masih ada yang perlu ditinjau.").font(.title2.bold())
                    Text("\(session.counts.verified) dari \(session.counts.expected) peserta yang diharapkan diperiksa.")
                    Text("Penutupan ini mencatat pemeriksaan, bukan izin bus berangkat atau pernyataan keselamatan.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Belum diperiksa · \(session.counts.unresolved)") {
                    ForEach(session.participants.filter { $0.expected && !$0.verified }) { p in ParticipantRow(person: p) }
                    if session.counts.unresolved == 0 { Label("Semua yang diharapkan sudah diperiksa", systemImage: "checkmark.circle").foregroundStyle(TourStyle.accent) }
                }
                if session.counts.excluded > 0 {
                    Section("Tidak ikut · \(session.counts.excluded)") { ForEach(session.participants.filter { !$0.expected }) { p in
                        VStack(alignment: .leading, spacing: 6) { Text("\(p.id) · \(p.name)").font(.headline); Text(p.exclusionReason); Text(p.arrangement).font(.caption).foregroundStyle(.secondary) }
                    } }
                }
                if session.counts.openCases > 0 {
                    Section("Kasus terbuka · \(session.counts.openCases)") { ForEach(session.participants.filter(\.followUpOpen)) { p in Label("\(p.id) · \(p.followUp)", systemImage: "flag").foregroundStyle(.orange) } }
                }
                Section {
                    if session.counts.canCloseNormally {
                        Button("Tutup pemeriksaan normal") { close(.close) }.buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("close-normal")
                    }
                    TextField("Alasan Tutup dengan catatan", text: $note, axis: .vertical).lineLimit(2 ... 5).accessibilityIdentifier("closure-note")
                    Button("Tutup dengan catatan") { close(.closeWithNote) }.accessibilityIdentifier("close-with-note")
                        .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: { Text("Daftar peserta dan kasus yang belum selesai akan tetap tercatat saat ditutup dengan catatan.") }
            }.navigationTitle("Review").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } } }
        }
    }
    private func close(_ action: AttendanceAction) {
        app.attempt { try app.store.apply(action, reason: note) }
        if app.store.state.sessions.last?.closedAt != nil { dismiss() }
    }
}
