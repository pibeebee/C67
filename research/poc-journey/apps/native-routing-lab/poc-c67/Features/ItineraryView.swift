import SwiftUI

struct ActivityEditorPresentation: Identifiable {
    var id: UUID { activity.id }
    let activity: TourActivity
}
struct ActivityMapPresentation: Identifiable {
    var id: UUID { activity.id }
    let activity: TourActivity
}

struct ItineraryView: View {
    let app: POCController
    let audience: MapAudience
    @State private var editor: ActivityEditorPresentation?
    private var plan: JourneyPlan { app.store.state.effectivePlan }
    private var editable: Bool { audience == .leader && app.store.state.joinedQR == nil }
    var body: some View {
        List {
            ErrorNotice(app: app)
            Section {
                Text("Rundown perjalanan").font(.title2.bold())
                Text(audience == .participant && app.store.state.mode == .real && app.store.state.leaderBinding == nil ? "Tanpa koneksi TL · salinan tersimpan mungkin lama" : app.planSync.status).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("itinerary-sync-status")
                if let active = plan.activeActivity {
                    Label("Titik aktif: \(active.title)", systemImage: "flag.fill").foregroundStyle(.orange).accessibilityIdentifier("itinerary-active")
                    Text(active.timeLabel).font(.caption)
                }
                Button("Sinkronkan sekarang", systemImage: "arrow.clockwise") { Task { if editable { await app.planSync.publish() } else { await app.planSync.fetch() } } }
                    .disabled(app.planSync.publishing || app.planSync.fetching).accessibilityIdentifier("sync-itinerary")
            }
            Section("Kegiatan · \(plan.activities.count)/50") {
                ForEach(plan.sortedActivities) { activity in
                    NavigationLink {
                        ActivityDetailView(app: app, activityID: activity.id, audience: audience)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(activity.title, systemImage: activity.id == plan.activeActivityID ? "flag.fill" : "calendar")
                                .font(.headline)
                            Text(activity.timeLabel).font(.caption).foregroundStyle(.secondary)
                            Text(activity.place?.name ?? "Lokasi belum ditentukan").font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 5)
                    }.accessibilityIdentifier("activity-row-\(activity.id)")
                }
                if plan.activities.isEmpty {
                    ContentUnavailableView("Belum ada kegiatan", systemImage: "calendar.badge.plus", description: Text(editable ? "Tambahkan jadwal dan pilih lokasinya pada peta." : "Rundown akan muncul setelah TL menambahkan dan menyinkronkannya."))
                }
            }
        }.navigationTitle("Rundown").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if editable {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Tambah kegiatan", systemImage: "plus") {
                            editor = ActivityEditorPresentation(activity: TourActivity(title: "", start: .now, end: .now.addingTimeInterval(3600)))
                        }.disabled(plan.activities.count >= 50).accessibilityIdentifier("add-activity")
                    }
                }
            }
            .sheet(item: $editor) { draft in ActivityEditorView(app: app, initial: draft.activity) }
    }
}

struct ActivityEditorView: View {
    let app: POCController
    let initial: TourActivity
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TourActivity
    @State private var picker: ScannerPresentation?
    @State private var message: String?
    @State private var originalRun: UUID
    init(app: POCController, initial: TourActivity) {
        self.app = app; self.initial = initial
        _draft = State(initialValue: initial); _originalRun = State(initialValue: app.store.state.runID)
    }
    var body: some View {
        NavigationStack {
            Form {
                if let message { Section { Text(message).foregroundStyle(.red).accessibilityIdentifier("activity-editor-error") } }
                Section("Kegiatan") {
                    TextField("Nama kegiatan", text: $draft.title).accessibilityIdentifier("activity-title")
                    DatePicker("Mulai", selection: $draft.start).accessibilityIdentifier("activity-start")
                    DatePicker("Selesai", selection: $draft.end).accessibilityIdentifier("activity-end")
                    Text("Zona waktu: \(draft.timeZoneID)").font(.caption).foregroundStyle(.secondary)
                    TextField("Catatan (opsional)", text: $draft.notes, axis: .vertical).lineLimit(3 ... 6).accessibilityIdentifier("activity-notes")
                }
                Section("Lokasi (opsional)") {
                    if let place = draft.place { Label(place.name, systemImage: "mappin.and.ellipse").accessibilityIdentifier("activity-place") }
                    else { Text("Belum ditentukan").foregroundStyle(.secondary) }
                    Button(draft.place == nil ? "Pilih lokasi di peta" : "Ubah lokasi di peta", systemImage: "map") { picker = ScannerPresentation() }
                        .accessibilityIdentifier("activity-pick-location")
                    if draft.place != nil { Button("Hapus lokasi", role: .destructive) { draft.place = nil } }
                }
                Section { Text("Perubahan disimpan di aplikasi lalu dikirim ke kanal privat peserta. Calendar diperbarui hanya jika Anda menambahkan salinan baru.").font(.caption).foregroundStyle(.secondary) }
            }.environment(\.timeZone, TimeZone(identifier: draft.timeZoneID) ?? .current)
                .navigationTitle(initial.title.isEmpty ? "Tambah kegiatan" : "Edit kegiatan").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Simpan") { save() }.disabled(!draft.valid).accessibilityIdentifier("save-activity")
                    }
                }
                .sheet(item: $picker) { _ in MapLocationPicker(initial: draft.place, runID: originalRun, allowGPS: app.store.state.mode == .real) { draft.place = $0 } }
        }
    }
    private func save() {
        do {
            guard app.store.state.runID == originalRun else { throw POCError.message("Perjalanan berubah. Buka ulang editor kegiatan.") }
            draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            try app.store.commit { try $0.saveActivity(draft) }
            dismiss()
        } catch { message = error.localizedDescription }
    }
}

struct ActivityDetailView: View {
    let app: POCController
    let activityID: UUID
    let audience: MapAudience
    var showsMapButton = true
    @Environment(\.dismiss) private var dismiss
    @State private var editor: ActivityEditorPresentation?
    @State private var map: ActivityMapPresentation?
    @State private var calendar: CalendarDraft?
    @State private var activate = false
    @State private var remove = false
    @State private var replaceCalendar = false
    @State private var calendarStatus: String?
    private var activity: TourActivity? { app.store.state.effectivePlan.activities.first { $0.id == activityID } }
    private var editable: Bool { audience == .leader && app.store.state.joinedQR == nil }
    private var receipt: CalendarExportReceipt? { app.store.state.calendarExports?.last { $0.activityID == activityID } }
    var body: some View {
        List {
            ErrorNotice(app: app)
            if let activity {
                Section {
                    Text(activity.title).font(.title2.bold()).accessibilityIdentifier("activity-detail-title")
                    Text(activity.timeLabel).font(.subheadline)
                    if !activity.notes.isEmpty { Text(activity.notes) }
                    Label(activity.place?.name ?? "Lokasi belum ditentukan", systemImage: "mappin.and.ellipse")
                    if activity.id == app.store.state.effectivePlan.activeActivityID { Label("Titik berkumpul aktif", systemImage: "flag.fill").foregroundStyle(.orange) }
                }
                Section {
                    if activity.place != nil {
                        if showsMapButton { Button("Lihat pada peta", systemImage: "map") { map = ActivityMapPresentation(activity: activity) }.accessibilityIdentifier("activity-show-map") }
                        if editable {
                            Button("Jadikan titik berkumpul aktif", systemImage: "flag") { activate = true }.accessibilityIdentifier("activate-activity")
                        }
                    }
                    if editable { Button("Edit kegiatan", systemImage: "pencil") { editor = ActivityEditorPresentation(activity: activity) }.accessibilityIdentifier("edit-activity") }
                }
                Section("Apple Calendar") {
                    if let calendarStatus { Text(calendarStatus).font(.caption).accessibilityIdentifier("calendar-export-status") }
                    if let receipt {
                        Text(receipt.fingerprint == activity.calendarFingerprint ? "Salinan pernah ditambahkan dari iPhone ini. Aplikasi tidak membaca apakah event masih ada di Calendar." : "Kegiatan berubah sejak ekspor terakhir. Salinan Calendar belum diperbarui.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button(receipt == nil ? "Tambahkan ke Calendar" : "Tambahkan salinan baru ke Calendar", systemImage: "calendar.badge.plus") {
                        if receipt != nil { replaceCalendar = true } else { openCalendar(activity) }
                    }.accessibilityIdentifier("export-activity-calendar")
                    Text("Editor Calendar meminta konfirmasi Anda. Perubahan/hapus pada salah satu aplikasi tidak otomatis mengubah salinan lainnya.").font(.caption).foregroundStyle(.secondary)
                }
                if editable { Section { Button("Hapus kegiatan", role: .destructive) { remove = true }.accessibilityIdentifier("delete-activity") } }
            } else { ContentUnavailableView("Kegiatan tidak tersedia", systemImage: "calendar.badge.exclamationmark", description: Text("TL mungkin sudah menghapus kegiatan ini.")) }
        }.navigationTitle("Detail kegiatan").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editor) { draft in ActivityEditorView(app: app, initial: draft.activity) }
            .fullScreenCover(item: $map) { item in GroupMapScreen(app: app, audience: audience, initialActivityID: item.id) }
            .sheet(item: $calendar) { draft in
                CalendarEventSheet(draft: draft) { saved in
                    calendar = nil
                    if saved {
                        app.attempt {
                            guard app.store.state.runID == draft.runID else { throw POCError.message("Calendar tersimpan; perjalanan lokal sudah berubah.") }
                            try app.store.commit {
                                if $0.calendarExports == nil { $0.calendarExports = [] }
                                $0.calendarExports?.removeAll { $0.activityID == draft.activity.id }
                                $0.calendarExports?.append(CalendarExportReceipt(activityID: draft.activity.id, fingerprint: draft.activity.calendarFingerprint, savedAt: .now))
                            }
                        }
                        calendarStatus = "Editor Calendar mengonfirmasi penyimpanan."
                    } else { calendarStatus = "Ekspor dibatalkan; tidak ada penyimpanan yang dikonfirmasi." }
                }
            }
            .alert("Jadikan kegiatan sebagai titik berkumpul?", isPresented: $activate) {
                Button("Jadikan aktif") { app.attempt { try app.store.commit { try $0.activateActivity(activityID) } } }
                Button("Batal", role: .cancel) {}
            } message: { Text("Lokasi kegiatan menjadi meeting point dan waktu mulai ditampilkan sebagai waktu berkumpul. Pemeriksaan kehadiran tidak berubah.") }
            .alert("Hapus kegiatan?", isPresented: $remove) {
                Button("Hapus", role: .destructive) { app.attempt { try app.store.commit { try $0.deleteActivity(activityID) }; dismiss() } }
                Button("Batal", role: .cancel) {}
            } message: { Text("Jika kegiatan ini aktif, meeting point juga dikosongkan. Event yang sudah diekspor ke Calendar tidak ikut dihapus.") }
            .alert("Buat salinan Calendar lagi?", isPresented: $replaceCalendar) {
                Button("Lanjutkan ke Calendar") { if let activity { openCalendar(activity) } }
                Button("Batal", role: .cancel) {}
            } message: { Text("Event sebelumnya tetap ada. Penambahan berikutnya dapat membuat duplikat; kelola salinan lama melalui Calendar.") }
    }
    private func openCalendar(_ activity: TourActivity) {
        calendar = CalendarDraft(activity: activity, journey: (app.store.state.mode == .simulation ? "SIMULASI · " : "") + (app.store.state.qrJourneyName ?? app.store.state.joinedQR?.journey ?? "Perjalanan C67"), runID: app.store.state.runID)
    }
}
