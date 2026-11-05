import MapKit
import SwiftUI

struct NativeTripPlannerView: View {
    @State private var model = NativeTripModel()
    @State private var searchPoint: NativeTripPoint?
    @State private var showsExampleConfirmation = false
    @State private var confirmsJakarta = false
    @State private var showsNewTripConfirmation = false
    @State private var showsListInput = false
    @State private var importingDraft = false
    @State private var importError: String?
    @State private var inputJSON = ""
    @State private var showsRestoreConfirmation = false
    @State private var showsImportConfirmation = false
    @State private var showsAcceptConfirmation = false
    @State private var showsStorageExampleConfirmation = false
    @State private var showsActiveExampleConfirmation = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                NativeTripLocalSection(
                    model: model, onRestore: { showsRestoreConfirmation = true },
                    onAccept: { showsAcceptConfirmation = true })
                Section("PoC Jakarta") {
                    Text("Tempat di Jakarta · WIB · perjalanan mobil/taksi")
                    Text(NativeTripJakarta.motorNotice).font(.footnote)
                    if !model.draft.isJakartaProfile {
                        Text(
                            "Rencana lama tetap tersedia. Pilih profil Jakarta sebelum menghitung itinerary baru."
                        )
                        .font(.footnote)
                        Button("Gunakan profil Jakarta dan mobil/taksi") { confirmsJakarta = true }
                            .disabled(model.isBusy || model.hasActiveTrip)
                    }
                }
                NativeTripEndpointsSection(model: model) { searchPoint = $0 }
                    .disabled(model.isBusy || model.hasActiveTrip)
                NativeTripStopsSection(
                    model: model,
                    onAdd: {
                        searchPoint = .init(
                            id: UUID().uuidString, title: "Tempat baru", query: "",
                            searchRegion: model.draft.isJakartaProfile ? NativeTripJakarta.region : nil)
                    }, onPaste: { showsListInput = true }
                ).disabled(model.isBusy || model.hasActiveTrip)
                if !model.draft.locationWarnings.isEmpty {
                    Section("Periksa lokasi") {
                        ForEach(model.draft.locationWarnings, id: \.self) {
                            Text($0).font(.footnote).foregroundStyle(.orange)
                        }
                    }
                }
                Section {
                    Button("Muat input JSON") { importingDraft = true }.disabled(
                        model.isBusy || model.hasActiveTrip)
                    if let importError { Text(importError).font(.footnote).foregroundStyle(.red) }
                    NavigationLink("Pengaturan") { NativeTripPreferencesView(draft: $model.draft) }
                        .disabled(model.isBusy || model.hasActiveTrip)
                    NavigationLink("Bandingkan algoritme") { NativeTripRoutingLabView(draft: model.draft) }
                        .disabled(model.isBusy || model.hasActiveTrip || !model.draft.isJakartaProfile)
                }
                NativeTripActionsSection(model: model)
                if let report = model.report {
                    Section {
                        NavigationLink {
                            NativeTripReportView(report: report, attribution: model.attribution)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Lihat itinerary")
                                Text(report.status).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Rencana")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Log") { NativeTripLogView(store: model.logs) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Muat simulasi trip aktif", systemImage: "clock.arrow.circlepath") {
                            showsActiveExampleConfirmation = true
                        }
                        Button("Rencana baru", systemImage: "square.and.pencil") {
                            showsNewTripConfirmation = true
                        }
                        Button("Muat simulasi penyimpanan", systemImage: "internaldrive") {
                            showsStorageExampleConfirmation = true
                        }
                        Button("Muat kasus Jakarta · 5 tujuan", systemImage: "list.bullet.rectangle") {
                            showsExampleConfirmation = true
                        }
                    } label: {
                        Label("Kelola rencana", systemImage: "ellipsis.circle")
                    }
                    .disabled(model.isBusy || model.hasActiveTrip)
                }
            }
            .confirmationDialog(
                "Muat simulasi trip aktif? Jam, lokasi dan ETA sintetis; rencana tersimpan baru diganti setelah Simpan itinerary pilihan.",
                isPresented: $showsActiveExampleConfirmation, titleVisibility: .visible
            ) {
                Button("Muat contoh trip aktif") { model.useActiveExample() }
            }
            .confirmationDialog(
                "Ganti input dengan simulasi lokal? Lokasi dan ETA sintetis, tanpa request jaringan. Data tersimpan tidak diganti sampai Anda menekan Simpan.",
                isPresented: $showsStorageExampleConfirmation, titleVisibility: .visible
            ) {
                Button("Muat simulasi lokal") { model.useStorageExample() }
            }
            .confirmationDialog(
                "Muat lima tujuan Jakarta dari log? Pin perlu diperiksa, tanggal besok pukul 08.00–18.00 WIB. Data tersimpan baru diganti jika Anda menyimpan.",
                isPresented: $showsExampleConfirmation,
                titleVisibility: .visible
            ) {
                Button("Muat kasus Jakarta") { model.useJakartaExample() }
            }
            .confirmationDialog(
                "Pakai profil Jakarta, WIB dan mobil/taksi? Koordinat serta tujuan dipertahankan; rencana lama tersimpan belum diganti.",
                isPresented: $confirmsJakarta, titleVisibility: .visible
            ) {
                Button("Gunakan profil Jakarta") { model.adoptJakartaProfile() }
            }
            .confirmationDialog(
                "Mulai rencana kosong? Input di layar akan diganti.",
                isPresented: $showsNewTripConfirmation, titleVisibility: .visible
            ) {
                Button("Mulai rencana kosong", role: .destructive) { model.startNewTrip() }
            }
            .confirmationDialog(
                "Simpan sebagai itinerary pilihan? Pilihan tersimpan sebelumnya akan diganti; data tetap hanya di perangkat ini.",
                isPresented: $showsAcceptConfirmation, titleVisibility: .visible
            ) {
                Button("Simpan itinerary pilihan") { model.saveLocal(acceptReport: true) }
            }
            .confirmationDialog(
                "Buka kembali data tersimpan? Perubahan yang belum disimpan akan dilepas.",
                isPresented: $showsRestoreConfirmation, titleVisibility: .visible
            ) {
                Button("Buka data tersimpan") { model.restoreLocal() }
            }
            .sheet(isPresented: $importingDraft) {
                NavigationStack {
                    Form {
                        Section("Pulihkan kasus dari log input.snapshot") {
                            TextField("Tempel JSON rencana", text: $inputJSON)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .accessibilityLabel("JSON rencana")
                            Text(
                                "Tempel objek JSON rencana. Seluruh koordinat, tanggal dan zona waktu divalidasi sebelum mengganti input di layar."
                            )
                            .font(.footnote)
                            Button("Gunakan input JSON") {
                                do {
                                    // Validation happens before asking to replace the current draft.
                                    let decoder = JSONDecoder()
                                    decoder.dateDecodingStrategy = .iso8601
                                    let value = try decoder.decode(NativeTripDraft.self, from: Data(inputJSON.utf8))
                                    try value.validate()
                                    showsImportConfirmation = true
                                } catch { importError = error.localizedDescription }
                            }.disabled(inputJSON.isEmpty)
                            if let importError { Text(importError).font(.footnote).foregroundStyle(.red) }
                        }
                    }.navigationTitle("Input diagnostik")
                        .confirmationDialog(
                            "Ganti input di layar? Rencana tersimpan tetap tersedia sampai Anda menyimpan perubahan.",
                            isPresented: $showsImportConfirmation, titleVisibility: .visible
                        ) {
                            Button("Ganti input") {
                                do {
                                    try model.importDraft(Data(inputJSON.utf8))
                                    importError = nil
                                    importingDraft = false
                                } catch { importError = error.localizedDescription }
                            }
                        }
                }
            }
            .sheet(isPresented: $showsListInput) {
                NativeTripListInputSheet(
                    remaining: NativeTripListInput.maximumStops - model.draft.stops.count
                ) { try model.appendPlaces($0) }
            }
            .sheet(item: $searchPoint) { point in
                NativeTripSearchSheet(
                    point: point, initialMatches: model.matches[point.id] ?? [],
                    searchContext: model.draft.searchContext, jakartaOnly: true
                ) { model.select($0) }
            }
            .onChange(of: model.draft) { _, _ in model.inputChanged() }
            .onChange(of: scenePhase) { _, value in
                model.logs.record(
                    "app.phase_changed", category: "app", fields: ["phase": String(describing: value)])
                if value != .active { model.cancel(reason: "app_\(String(describing: value))") }
                Task { await model.logs.flush() }
            }
        }
    }
}

private struct NativeTripLocalSection: View {
    let model: NativeTripModel
    let onRestore: () -> Void
    let onAccept: () -> Void
    var body: some View {
        Section("Di perangkat ini") {
            Text(model.hasUnsavedDraft ? "Draft belum disimpan" : "Draft tersimpan")
                .font(.subheadline)
            Button {
                model.saveLocal()
            } label: {
                Text("Simpan draft").frame(maxWidth: .infinity, alignment: .leading).contentShape(
                    Rectangle())
            }
            .disabled(model.isBusy || model.storageBlocked)
            if model.canAcceptReport {
                Button(action: onAccept) {
                    Text("Simpan itinerary pilihan").frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .disabled(model.isBusy || model.storageBlocked)
            }
            if let session = model.localSession {
                if session.acceptedReport != nil {
                    NavigationLink(model.hasActiveTrip ? "Lanjutkan trip aktif" : "Mulai / lihat perjalanan")
                        {
                            NativeTripActiveView(controller: model.makeActiveController()) { model.restoreLocal() }
                        }
                }
                Text("Disimpan \(session.draft.clock(session.savedAt))").font(.caption).foregroundStyle(
                    .secondary)
                if let saved = session.acceptedReport {
                    NavigationLink("Itinerary tersimpan") {
                        NativeTripReportView(report: saved, attribution: nil)
                    }
                    Text(
                        "Data rute/cuaca berasal dari \(saved.draft.clock(saved.generatedAt)). Hitung ulang untuk kondisi terbaru."
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Button(action: onRestore) {
                Text("Buka kembali data tersimpan").frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .disabled(model.isBusy || model.hasActiveTrip)
            if let notice = model.storageNotice { Text(notice).font(.footnote) }
            if let error = model.storageError { Text(error).font(.footnote).foregroundStyle(.red) }
            DisclosureGroup("Uji penyimpanan lokal") {
                Button {
                    model.failNextLocalSave()
                } label: {
                    Text("Gagalkan satu simpan berikutnya").frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .disabled(model.isBusy || model.storageBlocked)
                Text(
                    "Data hanya tersimpan di perangkat ini. Simpan sebelum menutup aplikasi; uninstall menghapus data lokal."
                )
                .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private struct NativeTripEndpointsSection: View {
    @Bindable var model: NativeTripModel
    let onSearch: (NativeTripPoint) -> Void

    var body: some View {
        Section("Perjalanan") {
            NativeTripPointButton(
                point: model.draft.origin, alternatives: model.matches[model.draft.origin.id]?.count ?? 0,
                lookup: model.lookupStates[model.draft.origin.id]
            ) { onSearch(model.draft.origin) }
            Toggle("Kembali ke titik awal", isOn: $model.draft.returnsToOrigin)
            if !model.draft.returnsToOrigin {
                NativeTripPointButton(
                    point: model.draft.end, alternatives: model.matches[model.draft.end.id]?.count ?? 0,
                    lookup: model.lookupStates[model.draft.end.id]
                ) { onSearch(model.draft.end) }
            }
            DatePicker("Berangkat", selection: $model.draft.departure).environment(
                \.timeZone, model.draft.timeZone)
            Toggle(
                "Tentukan batas tiba di titik akhir",
                isOn: Binding(
                    get: { model.draft.finishBy != nil },
                    set: { model.draft.finishBy = $0 ? model.draft.endOfDay.addingTimeInterval(-1) : nil }))
            if model.draft.finishBy != nil {
                DatePicker(
                    "Tiba paling lambat",
                    selection: Binding(
                        get: { model.draft.finishBy ?? model.draft.endOfDay },
                        set: { model.draft.finishBy = $0 })
                ).environment(\.timeZone, model.draft.timeZone)
            }
            Text(model.draft.deadlineSummary).font(.footnote).foregroundStyle(.secondary)
            Text(model.draft.timeZoneID).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct NativeTripStopsSection: View {
    let model: NativeTripModel
    let onAdd: () -> Void
    let onPaste: () -> Void

    var body: some View {
        Section("Tujuan · \(model.draft.stops.count)") {
            ForEach(model.draft.stops) { stop in
                NavigationLink {
                    NativeTripStopEditor(
                        value: stop, draft: model.draft, initialMatches: model.matches[stop.id] ?? [],
                        lookup: model.lookupStates[stop.id]
                    ) { model.saveStop($0) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stop.point.title)
                        Text(
                            "\(stop.dwell(defaultMinutes: model.draft.defaultDwell)) menit · \(stop.point.resolvedName ?? model.lookupStates[stop.id]?.kind.title ?? "Pilih lokasi")"
                        )
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        if let address = stop.point.address {
                            Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                        if stop.role == .visit {
                            Label(stop.opening?.summary ?? "Jam operasional belum diisi", systemImage: "clock")
                                .font(.caption).foregroundStyle(.secondary)
                            if let issue = stop.opening?.issue(
                                for: model.draft.departure, timeZone: model.draft.timeZone)
                            {
                                Text(issue).font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }.onDelete { model.removeStops(at: $0) }
            Menu("Tambah tempat") {
                Button("Satu tempat", action: onAdd)
                Button("Tempel daftar", action: onPaste)
            }.disabled(model.draft.stops.count >= NativeTripListInput.maximumStops)
            if model.draft.stops.contains(where: { $0.role == .visit }) {
                Text("Ketuk tujuan untuk mengisi jam buka/tutup sesuai tanggal dan zona waktu trip.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private struct NativeTripActionsSection: View {
    let model: NativeTripModel

    var body: some View {
        Section {
            if model.isBusy {
                ProgressView(model.phase)
                Button("Batalkan", role: .cancel) { model.cancel() }
            } else {
                Button("Temukan lokasi") { model.resolveMissing() }.disabled(model.pendingSearchCount == 0)
                Button(model.report == nil ? "Hitung itinerary" : "Hitung ulang itinerary") {
                    model.calculate()
                }
                .disabled(model.unresolvedCount > 0 || model.draft.stops.isEmpty)
                if model.unresolvedCount > 0 {
                    Text("\(model.unresolvedCount) lokasi belum dipilih.").font(.caption).foregroundStyle(
                        .secondary)
                }
            }
            if let error = model.error { Text(error).font(.footnote).foregroundStyle(.red) }
            if let error = model.logs.storageError { Text(error).font(.footnote).foregroundStyle(.red) }
        }
    }
}

private struct NativeTripPreferencesView: View {
    @Binding var draft: NativeTripDraft

    var body: some View {
        Form {
            NativeTripSettingsSection(draft: $draft)
            Section("Algoritme itinerary") {
                Picker(
                    "Metode",
                    selection: Binding(
                        get: { draft.selectedRoutingAlgorithm.rawValue }, set: { draft.routingAlgorithm = $0 })
                ) {
                    ForEach(TripRoutingAlgorithm.native) { Text($0.title).tag($0.rawValue) }
                }
                Stepper(
                    "Batas request ETA: \(draft.routingRequestLimit ?? 96)",
                    value: Binding(
                        get: { draft.routingRequestLimit ?? 96 }, set: { draft.routingRequestLimit = $0 }),
                    in: 32 ... 1024, step: 32)
                Text(
                    "Hybrid mengutamakan kelayakan lalu durasi trip termasuk menunggu dan singgah. Baseline live dipertahankan, lalu kandidat tambahan diperiksa sesuai jam tiap ruas. Anggaran kecil dapat menghasilkan matriks parsial. Enumerasi maksimal 8 tujuan; OR-Tools melalui layar pembanding."
                ).font(.footnote)
            }
        }
        .navigationTitle("Pengaturan").navigationBarTitleDisplayMode(.inline)
    }
}

private struct NativeTripSettingsSection: View {
    @Binding var draft: NativeTripDraft
    var body: some View {
        if draft.isJakartaProfile {
            Section("Jakarta · mobil/taksi") {
                LabeledContent("Zona waktu", value: "Asia/Jakarta (WIB)")
                LabeledContent("Kendaraan", value: "Mobil · taksi / ride-hailing")
                Text(
                    "Rute dan ETA mobil dari MapKit. Waktu menunggu kendaraan, parkir dan akses masuk belum dimodelkan."
                )
                .font(.footnote)
                Text(NativeTripJakarta.motorNotice).font(.footnote)
                Text(
                    "Pencarian dan pin dibatasi cakupan Jakarta pada PoC. Periksa cabang, alamat dan jam operasional."
                )
                .font(.footnote)
                Stepper(
                    "Default singgah: \(draft.defaultDwell) menit", value: $draft.defaultDwell, in: 5 ... 240,
                    step: 5)
                LabeledContent("Cuaca", value: "Open-Meteo")
                Text(
                    "Pin dekat batas wilayah perlu diperiksa; cakupan PoC memakai data batas yang disederhanakan."
                ).font(.footnote)
                Link(
                    "Data batas wilayah: OpenStreetMap / geoBoundaries",
                    destination: URL(string: "https://www.openstreetmap.org/copyright")!
                )
                .font(.footnote)
            }
        } else {
            Section("Waktu dan preferensi") {
                NavigationLink {
                    NativeTripTimeZonePicker(
                        selection: Binding(get: { draft.timeZoneID }, set: { draft.changeTimeZone(to: $0) }))
                } label: {
                    LabeledContent("Zona waktu trip", value: draft.timeZoneID)
                }
                TextField("Kota/negara pencarian (opsional)", text: $draft.searchContext)
                    .textInputAutocapitalization(.words)
                Text("Konteks ini ditambahkan ke pencarian nama, bukan koordinat yang sudah terverifikasi.")
                    .font(.footnote).foregroundStyle(.secondary)
                Stepper(
                    "Default singgah: \(draft.defaultDwell) menit", value: $draft.defaultDwell, in: 5 ... 240,
                    step: 5)
                Toggle("Bandingkan jalan kaki", isOn: $draft.walking)
                Toggle("Bandingkan transit · ETA", isOn: $draft.transit)
                Toggle(
                    "Bandingkan mobil · ETA",
                    isOn: Binding(get: { draft.automobile == true }, set: { draft.automobile = $0 }))
                if draft.automobile == true {
                    Picker(
                        "Akses mobil",
                        selection: Binding(get: { draft.carUse ?? "privateCar" }, set: { draft.carUse = $0 })
                    ) {
                        ForEach(NativeTripCarUse.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Text(
                        "Mobil pribadi: satu trip memakai mobil seluruh ruas atau tanpa mobil. Taksi dapat dipilih per ruas; waktu pesan/tunggu kendaraan belum dimodelkan."
                    ).font(.footnote).foregroundStyle(.secondary)
                }
                Text(
                    "Mobil harus diaktifkan sendiri. ETA belum mencakup parkir atau akses kendaraan. Transit bergantung cakupan MapKit di wilayah trip."
                )
                .font(.footnote).foregroundStyle(.secondary)
                Stepper(
                    "Batas berjalan: \(draft.maximumWalkingMinutes) menit/ruas",
                    value: $draft.maximumWalkingMinutes, in: 5 ... 240, step: 5)
                Stepper(
                    "Tambahan waktu karena preferensi cuaca: maks. \(draft.extraWeatherMinutes) menit",
                    value: $draft.extraWeatherMinutes, in: 0 ... 120, step: 5)
                Text(
                    "Trip satu hari, berakhir sebelum tengah malam pada zona waktu di atas. Batas berjalan dan tambahan waktu adalah pengaturan PoC yang dapat diubah."
                )
                .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private struct NativeTripPointButton: View {
    let point: NativeTripPoint
    let alternatives: Int
    var lookup: NativeTripLookupState? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Label(point.title, systemImage: "mappin.and.ellipse")
                Text(
                    point.resolvedName
                        ?? (alternatives > 1
                            ? "Pilih dari \(alternatives) kandidat"
                            : lookup?.kind.title ?? "Cari atau pilih pin pada peta")
                )
                .font(.caption).foregroundStyle(.secondary)
                if let address = point.address {
                    Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
        }
    }
}

private struct NativeTripStopEditor: View {
    @State private var stop: NativeTripStop
    @State private var showsSearch = false
    let draft: NativeTripDraft
    let initialMatches: [NativeTripMatch]
    let lookup: NativeTripLookupState?
    let onSave: (NativeTripStop) -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        value: NativeTripStop, draft: NativeTripDraft, initialMatches: [NativeTripMatch],
        lookup: NativeTripLookupState?,
        onSave: @escaping (NativeTripStop) -> Void
    ) {
        _stop = State(initialValue: value)
        self.draft = draft
        self.initialMatches = initialMatches
        self.lookup = lookup
        self.onSave = onSave
    }
    private var customDwell: Binding<Bool> {
        Binding(
            get: { stop.dwellOverride != nil },
            set: { stop.dwellOverride = $0 ? draft.defaultDwell : nil })
    }
    var body: some View {
        Form {
            Section("Tempat") {
                TextField("Nama kegiatan", text: $stop.point.title)
                NativeTripPointButton(point: stop.point, alternatives: initialMatches.count, lookup: lookup)
                    { showsSearch = true }
                if let note = stop.point.referenceNote {
                    Text(note).font(.footnote).foregroundStyle(.orange)
                }
            }
            Section("Kunjungan") {
                Picker("Peran tempat", selection: $stop.role) {
                    ForEach(NativeTripRole.allCases) { Text($0.title).tag($0) }
                }
                if stop.role == .visit {
                    Toggle("Atur lama singgah sendiri", isOn: customDwell)
                    if stop.dwellOverride != nil {
                        Stepper(
                            "Singgah \(stop.dwellOverride ?? draft.defaultDwell) menit",
                            value: Binding(
                                get: { stop.dwellOverride ?? draft.defaultDwell }, set: { stop.dwellOverride = $0 }),
                            in: 5 ... 480, step: 5)
                    } else {
                        Text("Menggunakan default \(draft.defaultDwell) menit")
                    }
                } else {
                    Text(
                        "Nol menit kunjungan tambahan. Waktu perjalanan/transfer tetap mengikuti estimasi provider."
                    )
                }
                Picker("Paparan cuaca", selection: $stop.exposure) {
                    ForEach(NativeTripExposure.allCases) { Text($0.title).tag($0) }
                }
            }
            if stop.role == .visit {
                NativeTripOpeningSection(
                    opening: $stop.opening, departure: draft.departure, timeZone: draft.timeZone)
            }
        }
        .navigationTitle("Detail tujuan")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Simpan") {
                    if stop.role == .visit, stop.opening != nil {
                        stop.opening?.serviceDate = NativeTripOpening.dateKey(
                            draft.departure, timeZone: draft.timeZone)
                        stop.opening?.timeZoneID = draft.timeZoneID
                        let source = stop.opening?.sourceNote?.trimmingCharacters(in: .whitespacesAndNewlines)
                        stop.opening?.sourceNote = source?.isEmpty == true ? nil : source
                    }
                    onSave(stop)
                    dismiss()
                }
                .disabled(
                    stop.role == .visit
                        && stop.opening?.issue(for: draft.departure, timeZone: draft.timeZone) != nil)
            }
        }
        .sheet(isPresented: $showsSearch) {
            NativeTripSearchSheet(
                point: stop.point, initialMatches: initialMatches, searchContext: draft.searchContext,
                jakartaOnly: true
            ) { stop.point = $0 }
        }
    }
}

struct NativeTripSearchSheet: View {
    let point: NativeTripPoint
    let searchContext: String
    let jakartaOnly: Bool
    let onSelect: (NativeTripPoint) -> Void
    @State private var query: String
    @State private var matches: [NativeTripMatch]
    @State private var busy = false
    @State private var error: String?
    @State private var reference: Bool
    @State private var useRegion = true
    @State private var service = NativeTripAppleServices()
    @State private var searchTask: Task<Void, Never>?
    @State private var identity = UUID()
    @Environment(\.dismiss) private var dismiss

    init(
        point: NativeTripPoint, initialMatches: [NativeTripMatch] = [], searchContext: String = "",
        jakartaOnly: Bool = false,
        onSelect: @escaping (NativeTripPoint) -> Void
    ) {
        self.point = point
        self.searchContext = jakartaOnly ? NativeTripJakarta.context : searchContext
        self.jakartaOnly = jakartaOnly
        self.onSelect = onSelect
        _query = State(initialValue: point.query)
        _matches = State(
            initialValue: jakartaOnly
                ? initialMatches.filter {
                    NativeTripJakarta.contains(latitude: $0.latitude, longitude: $0.longitude)
                } : initialMatches)
        _reference = State(initialValue: point.referenceNote != nil)
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Nama atau alamat tempat", text: $query).onSubmit { search() }
                    Button("Simpan nama dulu", systemImage: "text.badge.plus") {
                        var named = inputPoint
                        named.latitude = nil
                        named.longitude = nil
                        named.resolvedName = nil
                        named.address = nil
                        named.selectionSource = nil
                        select(named)
                    }
                    .disabled(busy || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !searchContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Konteks pencarian: \(searchContext)").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Cari di MapKit", systemImage: "magnifyingglass") { search() }.disabled(
                        busy || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !jakartaOnly, let region = point.searchRegion {
                        Toggle("Prioritaskan area \(region.label)", isOn: $useRegion)
                    }
                    if let aliases = point.queryAliases {
                        ForEach(aliases.filter { $0 != query }, id: \.self) { alias in
                            Button("Pakai nama alternatif: \(alias)") { query = alias }
                        }
                    }
                    NavigationLink {
                        NativeTripPinPicker(point: inputPoint, jakartaOnly: jakartaOnly) { selected in
                            select(selected)
                        }
                    } label: {
                        Label("Pilih titik pada peta", systemImage: "mappin.and.ellipse")
                    }
                    .disabled(busy || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if point.referenceNote != nil { Toggle("Masih titik pendekatan area", isOn: $reference) }
                    if busy { ProgressView("Mencari…") }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                Section("Pilih lokasi yang benar") {
                    ForEach(matches) { match in
                        Button {
                            var selected = NativeTripModel.applying(match, to: inputPoint)
                            if point.title == "Tempat baru" { selected.title = match.name }
                            if !reference { selected.referenceNote = nil }
                            select(selected)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(match.name)
                                Text(match.address).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pilih tempat")
            .onChange(of: query) { _, _ in
                identity = UUID()
                searchTask?.cancel()
                service.cancel()
                matches = []
                error = nil
                busy = false
            }
            .onChange(of: useRegion) { _, _ in
                identity = UUID()
                searchTask?.cancel()
                service.cancel()
                matches = []
                error = nil
                busy = false
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Log") { NativeTripLogView(store: service.logs) }
                }
            }
            .onDisappear {
                identity = UUID()
                searchTask?.cancel()
                service.cancel()
            }
        }
    }
    private var inputPoint: NativeTripPoint {
        var value = point
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        value.query = text
        if point.query.isEmpty || point.title == point.query { value.title = text }
        value.searchRegion =
            jakartaOnly ? NativeTripJakarta.region : useRegion ? point.searchRegion : nil
        if text != point.query {
            value.queryAliases = nil
            value.latitude = nil
            value.longitude = nil
            value.resolvedName = nil
            value.address = nil
            value.selectionSource = nil
        }
        if !reference { value.referenceNote = nil }
        return value
    }
    private func select(_ selected: NativeTripPoint) {
        if jakartaOnly, let latitude = selected.latitude, let longitude = selected.longitude,
           !NativeTripJakarta.contains(latitude: latitude, longitude: longitude)
        {
            error = "Pin di luar cakupan Jakarta. Pilih lokasi atau cabang yang sesuai."
            return
        }
        service.logs.recordJSON(
            "location.selected", category: "input", operationID: service.operationID, value: selected)
        onSelect(selected)
        dismiss()
    }
    private func search() {
        guard !busy, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        searchTask?.cancel()
        service.cancel()
        identity = UUID()
        let token = identity
        let text = query
        error = nil
        busy = true
        matches = []
        searchTask = Task { @MainActor in
            do {
                let result = try await service.searchPlaces(
                    NativeTripListInput.searchQuery(name: text, context: searchContext),
                    region: jakartaOnly ? NativeTripJakarta.region : useRegion ? point.searchRegion : nil)
                guard !Task.isCancelled, identity == token else { return }
                matches =
                    jakartaOnly
                        ? result.filter {
                            NativeTripJakarta.contains(latitude: $0.latitude, longitude: $0.longitude)
                        }
                        : result
                busy = false
                if matches.isEmpty {
                    error =
                        jakartaOnly
                            ? "Belum ada hasil di cakupan Jakarta. Coba nama cabang/alamat yang lebih spesifik atau pilih pin."
                            : "Tidak ada hasil. Coba nama atau alamat yang lebih spesifik."
                }
            } catch {
                guard !Task.isCancelled, identity == token else { return }
                let failure = NativeTripLookupFailure.classify(error)
                self.error = failure.detail
                busy = false
            }
        }
    }
}
