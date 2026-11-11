import SwiftUI
import DynamicTripContracts
import PlaceContextEngine

struct ItineraryEditorView: View {
    @Bindable var editor: ItineraryEditorModel
    let model: PersonalLabModel
    @State private var deleting: RevisionStop?
    var body: some View {
        NavigationStack {
            List {
                if let draft = editor.state.draft {
                    Section("Perjalanan baru") {
                        Text("Urutan mengikuti pilihan Anda. Hitung ulang untuk memeriksa jadwal dan transportasi.").font(.footnote)
                        if !editor.fixture { Text("Draft dan riwayat hanya tersedia selama aplikasi terbuka. Setelah aplikasi ditutup, susun ulang perjalanan Anda.").font(.footnote) }
                        Picker("Transportasi", selection: Binding(get: { draft.transport }, set: { mode in editor.edit { $0.transport = mode } })) {
                            Text("Mobil").tag(ContextTransport.automobile)
                            Text("TJ + jalan kaki").tag(ContextTransport.transjakarta)
                        }.accessibilityIdentifier("revision-transport")
                        Text("\(draft.stops.count)/6 tujuan · kembali ke \(draft.origin.prepared.name)").font(.caption)
                        Button("Segarkan lokasi awal") { editor.refresh(nil) }
                    }
                    Section("Urutan tujuan") {
                        ForEach(Array(draft.stops.enumerated()), id: \.element.id) { index, stop in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(index + 1). \(stop.place.prepared.name)").font(.headline).accessibilityIdentifier("revision-stop-\(index)")
                                Text(stop.source.origin == .recommendation ? "Rekomendasi personal" : (stop.source.origin == .previousPlan ? "Pilihan dari versi sebelumnya" : "Pilihan Anda · bukan hasil ranking personal")).font(.caption).foregroundStyle(.secondary)
                                Toggle("Wajib dikunjungi", isOn: Binding(get: { stop.required }, set: { value in editor.edit { draft in draft.stops[index].required = value } }))
                                Stepper("Durasi \(stop.durationMinutes) menit", value: Binding(get: { stop.durationMinutes }, set: { value in editor.edit { $0.stops[index].durationMinutes = value } }), in: 15 ... 240, step: 15)
                                Picker("Kegiatan", selection: Binding(get: { stop.exposure }, set: { value in editor.edit { $0.stops[index].exposure = value } })) {
                                    Text("Belum diketahui").tag(ActivityExposure.unknown)
                                    Text("Dalam ruang").tag(ActivityExposure.indoor)
                                    Text("Luar ruang").tag(ActivityExposure.outdoor)
                                    Text("Campuran").tag(ActivityExposure.mixed)
                                }
                                Toggle("Hindari hujan saat kunjungan", isOn: Binding(get: { stop.avoidRain }, set: { value in editor.edit { $0.stops[index].avoidRain = value } }))
                                HStack {
                                    Button("Naik", systemImage: "arrow.up") { editor.move(index, by: -1) }.disabled(index == 0).accessibilityIdentifier("revision-up-\(index)")
                                    Button("Turun", systemImage: "arrow.down") { editor.move(index, by: 1) }.disabled(index + 1 == draft.stops.count).accessibilityIdentifier("revision-down-\(index)")
                                }.buttonStyle(.bordered)
                                HStack {
                                    Button("Ganti tempat") { editor.pick(replacing: stop.id) }.accessibilityIdentifier("revision-replace-\(index)")
                                    Spacer()
                                    Button("Hapus", role: .destructive) {
                                        if stop.required { deleting = stop } else { editor.remove(stop.id) }
                                    }.accessibilityIdentifier("revision-delete-\(index)")
                                }.buttonStyle(.bordered)
                                Button("Segarkan konteks dan identitas") { editor.refresh(stop.id) }.font(.caption)
                                if stop.place.prepared.expiresAt <= Date() { Text("Konteks kedaluwarsa; segarkan sebelum menghitung ulang").font(.caption).foregroundStyle(.orange) }
                            }.padding(.vertical, 5)
                        }.onMove { editor.move($0, to: $1) }
                        Button("Tambah tempat", systemImage: "plus") { editor.pick() }.disabled(draft.stops.count >= 6).accessibilityIdentifier("revision-add")
                        if draft.stops.isEmpty { Text("Draft kosong. Tambahkan tempat untuk menghitung perjalanan.") }
                    }
                    if !draft.omittedStops.isEmpty {
                        Section("Sebelumnya belum terjadwal") {
                            ForEach(draft.omittedStops) { row in
                                Button("Tambahkan \(row.place.prepared.name)") { editor.edit { draft in if draft.stops.count < 6 { draft.stops.append(row); draft.omittedStops.removeAll { $0.id == row.id } } } }.disabled(draft.stops.count >= 6)
                            }
                        }
                    }
                    Section("Batas perjalanan") {
                        DatePicker("Berangkat", selection: Binding(get: { draft.departure }, set: { value in editor.edit { $0.departure = value } }))
                        DatePicker("Pulang paling lambat", selection: Binding(get: { draft.deadline }, set: { value in editor.edit { $0.deadline = value } }))
                        Stepper("Total menunggu maks. \(draft.maximumWaitingMinutes) menit", value: Binding(get: { draft.maximumWaitingMinutes }, set: { value in editor.edit { $0.maximumWaitingMinutes = value } }), in: 0 ... 240, step: 5)
                        Text("Termasuk menunggu di tempat dan naik/pindah TJ. Waktu TJ berdasarkan snapshot GTFS, bukan posisi bus real-time.").font(.caption)
                    }
                    Section {
                        if editor.busy { ProgressView("Menghitung ulang…") }
                        Button("Hitung ulang") { editor.calculate() }.disabled(draft.stops.isEmpty || editor.busy).accessibilityIdentifier("revision-calculate")
                        if let error = editor.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("revision-error") }
                    }
                    if let preview = editor.state.preview {
                        ItineraryRevisionComparison(editor: editor, draft: draft, preview: preview)
                    }
                }
            }
            .environment(\.timeZone, TimeZone(identifier: "Asia/Jakarta")!)
            .navigationTitle("Edit perjalanan")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Batalkan") { editor.cancel() }.accessibilityIdentifier("revision-cancel") }
                ToolbarItem(placement: .topBarTrailing) { Button(editor.fixture ? "Simpan draft" : "Tutup draft") { editor.close() }.accessibilityIdentifier("revision-save-draft") }
                ToolbarItem(placement: .bottomBar) { EditButton() }
            }
            .alert("Hapus tujuan wajib?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Hapus tujuan", role: .destructive) { if let row = deleting { editor.remove(row.id) }; deleting = nil }
                Button("Kembali", role: .cancel) { deleting = nil }
            } message: { Text("Tempat ini akan dikeluarkan dari draft. Versi tersimpan tetap tersedia.") }
            .sheet(isPresented: $editor.picking, onDismiss: { editor.invalidateOperation(); editor.pending = nil }) {
                ItineraryPlacePicker(editor: editor, model: model)
            }
        }.interactiveDismissDisabled()
    }
}

private struct ItineraryPlacePicker: View {
    @Bindable var editor: ItineraryEditorModel
    let model: PersonalLabModel
    @FocusState private var searching: Bool
    var body: some View {
        NavigationStack {
            List {
                if let pending = editor.pending {
                    Section("Konfirmasi tempat baru") {
                        Text(pending.name).font(.headline)
                        Text(pending.address)
                        Text("Cocokkan nama, alamat, dan lokasi Apple. Kedekatan pin saja tidak membuktikan identitas.").font(.caption)
                        TextField("Cari padanan Apple lain", text: $editor.appleQuery)
                        Button("Cari ulang padanan Apple") { editor.retryIdentity() }.disabled(editor.busy || editor.appleQuery.isEmpty)
                        ForEach(pending.appleCandidates) { candidate in
                            Button { editor.confirm(candidate) } label: {
                                VStack(alignment: .leading) { Text(candidate.name); Text(candidate.address).font(.caption); Text("Jarak pin \(Int(candidate.distanceFromGoogleMeters)) m").font(.caption) }
                            }.disabled(!candidate.canConfirm).accessibilityIdentifier("revision-confirm-place")
                        }
                    }
                } else {
                    Section("Cari tempat sendiri") {
                        TextField("Nama tempat", text: $editor.query).focused($searching).submitLabel(.search).onSubmit { searching = false; editor.search() }.accessibilityIdentifier("revision-search-text")
                        Button("Cari tempat") { searching = false; editor.search() }.disabled(editor.busy).accessibilityIdentifier("revision-search")
                        if editor.replacingID == nil && editor.refreshingID == nil && !editor.refreshingOrigin { Toggle("Wajib dikunjungi", isOn: $editor.required) }
                        ForEach(Array(editor.results.enumerated()), id: \.offset) { index, place in
                            Button(place.displayName?.text ?? "Tempat") { if let id = place.id { editor.prepare(id) } }.accessibilityIdentifier("revision-search-result-\(index)")
                        }
                    }
                    if !model.browsePlaces.isEmpty && editor.refreshingID == nil && !editor.refreshingOrigin {
                        Section("Rekomendasi personal") {
                            ForEach(model.browsePlaces) { row in
                                Button(row.candidate.name) { editor.prepare(row.id, source: model.revisionSource(row.id)) }
                            }
                        }
                    }
                }
                if editor.busy { ProgressView() }
                if let error = editor.error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(editor.replacingID == nil ? "Pilih tempat" : "Ganti tempat")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Tutup") { editor.invalidateOperation(); editor.pending = nil; editor.picking = false } } }
        }
    }
}

private struct ItineraryRevisionComparison: View {
    @Bindable var editor: ItineraryEditorModel
    let draft: ItineraryEditDraft
    let preview: ItineraryRevisionPreview
    private func minutes(_ seconds: Double) -> String { "\(Int((seconds / 60).rounded(.up))) menit" }
    var body: some View {
        Section("Tinjau perubahan") {
            if let old = editor.state.current {
                Text("Sebelumnya: " + old.result.result.itinerary.visits.map { visit in old.draft.stops.first { $0.place.prepared.googlePlaceID == visit.placeID }?.place.prepared.name ?? visit.placeID }.joined(separator: " → ")).font(.caption)
                Text("Selesai sebelumnya: " + (old.result.result.itinerary.finish?.formatted(date: .omitted, time: .shortened) ?? "—")).font(.caption)
                Text("Sebelumnya: perjalanan \(minutes(old.result.result.itinerary.travelSeconds)) · jalan \(minutes(old.result.result.itinerary.walkingSeconds)) · total tunggu \(minutes(old.result.result.itinerary.totalWaitingSeconds))").font(.caption)
                ForEach(Array(old.result.result.itinerary.visits.enumerated()), id: \.offset) { _, visit in
                    Text((old.draft.stops.first { $0.place.prepared.googlePlaceID == visit.placeID }?.place.prepared.name ?? visit.placeID) + " · " + visit.visit.start.formatted(date: .omitted, time: .shortened) + "–" + visit.visit.end.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(preview.canApply ? "Revisi siap ditinjau" : "Revisi belum memenuhi batas perjalanan").font(.headline).accessibilityIdentifier("revision-preview-status")
            let trip = preview.result.result.itinerary
            ForEach(Array(trip.visits.enumerated()), id: \.offset) { index, visit in
                VStack(alignment: .leading) {
                    Text("\(index + 1). " + (draft.stops.first { $0.place.prepared.googlePlaceID == visit.placeID }?.place.prepared.name ?? visit.placeID))
                    Text("\(visit.visit.start.formatted(date: .omitted, time: .shortened))–\(visit.visit.end.formatted(date: .omitted, time: .shortened))").font(.caption)
                }
            }
            Text("Selesai baru: " + (trip.finish?.formatted(date: .omitted, time: .shortened) ?? "Belum ada jadwal layak"))
            Text("Perjalanan \(minutes(trip.travelSeconds)) · jalan \(minutes(trip.walkingSeconds)) · total tunggu \(minutes(trip.totalWaitingSeconds))").font(.caption)
            Text("Status: \(trip.status) · \(trip.travelCalls) evaluasi ruas").font(.caption)
            if !preview.canApply {
                Text(trip.status == "incomplete_travel_data" ? "Bukti perjalanan belum lengkap. Periksa rute/provider; tujuan wajib tetap dipertahankan." : "Belum ditemukan jadwal yang memenuhi jam buka, durasi, batas menunggu, dan waktu pulang dalam batas pencarian. Sesuaikan pilihan dan hitung ulang.").font(.footnote).foregroundStyle(.orange)
            }
            if let calls = preview.result.result.metrics.providerCalls { Text("\(calls) panggilan provider · \(preview.result.result.metrics.providerCells ?? 0) sel ETA").font(.caption) }
            ForEach(Array(preview.result.omitted.enumerated()), id: \.offset) { _, omission in
                Text("\(omission.required ? "Wajib belum masuk" : "Opsional belum masuk"): \(draft.stops.first { $0.place.prepared.googlePlaceID == omission.id }?.place.prepared.name ?? omission.id). \(omission.reason)").foregroundStyle(.orange)
            }
            ForEach(Array(trip.warnings.enumerated()), id: \.offset) { _, warning in Text(warning).font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(trip.legs.enumerated()), id: \.offset) { index, leg in
                if let detail = leg.evidence.details {
                    DisclosureGroup("Ruas \(index + 1): \(detail.mode == "walking" ? "Jalan kaki" : "TJ")") {
                        Text(detail.summary).font(.caption)
                        ForEach(detail.segments) { segment in
                            Text(segment.label).font(.caption)
                            if let start = segment.departure, let end = segment.arrival { Text("\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))").font(.caption) }
                        }
                        Text(leg.evidence.source).font(.caption2)
                        if let publisher = detail.sourcePublisher { Text("Sumber: " + publisher).font(.caption2) }
                        if let checked = detail.sourceCheckedAt { Text("Snapshot diperiksa " + checked.formatted(date: .abbreviated, time: .omitted)).font(.caption2) }
                        if let url = detail.attributionURL { Link("Atribusi data TJ", destination: url).font(.caption) }
                        if let url = detail.licenseURL { Link("Lisensi data", destination: url).font(.caption) }
                    }
                }
            }
            if let map = PersonalRouteMapData(draft: draft, trip: trip) { PersonalRouteMap(data: map, identifier: "revision-preview-map").id(preview.draftID) }
            Button("Terapkan itinerary baru") { editor.apply() }.disabled(!editor.state.canApply()).accessibilityIdentifier("revision-apply")
        }
    }
}

struct ItineraryHistoryView: View {
    let state: ItineraryRevisionState
    var body: some View {
        List {
            ForEach(Array(state.revisions.enumerated().reversed()), id: \.element.id) { index, revision in
                Section("Versi \(index + 1) · \(revision.savedAt.formatted(date: .abbreviated, time: .shortened))") {
                    Text(revision.id == state.current?.id ? "Versi yang diterapkan" : "Riwayat · konteks perlu disegarkan untuk perhitungan baru").font(.caption)
                    ForEach(Array(revision.result.result.itinerary.visits.enumerated()), id: \.offset) { number, visit in
                        Text("\(number + 1). " + (revision.draft.stops.first { $0.place.prepared.googlePlaceID == visit.placeID }?.place.prepared.name ?? visit.placeID))
                        Text("\(visit.visit.start.formatted(date: .omitted, time: .shortened))–\(visit.visit.end.formatted(date: .omitted, time: .shortened))").font(.caption)
                    }
                    Text(revision.draft.transport == .transjakarta ? "TJ + jalan kaki" : "Mobil")
                    if let map = PersonalRouteMapData(draft: revision.draft, trip: revision.result.result.itinerary) { PersonalRouteMap(data: map).id(revision.id) }
                }
            }
        }.navigationTitle("Riwayat itinerary")
    }
}
