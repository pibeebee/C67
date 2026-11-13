import SwiftUI
import RecommendationContracts
import DynamicTripContracts
import PlaceContextEngine

private func clockLabel(_ minute: Int) -> String {
    String(format: "%02d.%02d", minute / 60, minute % 60)
}

private enum SimplePersonalSheet: String, Identifiable {
    case trip, profile, origin, adjustments
    var id: String { rawValue }
}

struct SimplePersonalRoot: View {
    @Bindable var model: PersonalLabModel
    let diagnostics: ContextLabModel
    @State private var sheet: SimplePersonalSheet?
    var body: some View {
        if !model.onboarded { NavigationStack { PersonalOnboarding(model: model) } }
        else {
            TabView(selection: $model.selectedTab) {
                NavigationStack { SimpleDiscoverView(model: model, sheet: $sheet) }
                    .tabItem { Label("Jelajah", systemImage: "sparkles") }.tag(0)
                NavigationStack { SimplePlanView(model: model, sheet: $sheet) }
                    .tabItem { Label("Rencana", systemImage: "list.bullet.rectangle") }.tag(1)
            }
            .environment(\.timeZone, ContextClock.calendar.timeZone)
            .sheet(item: $sheet) { item in
                NavigationStack {
                    switch item {
                    case .trip: SimpleTripEditor(model: model)
                    case .profile: SimpleProfileEditor(model: model, diagnostics: diagnostics)
                    case .origin: SimpleOriginEditor(model: model)
                    case .adjustments: SimpleAdjustments(model: model)
                    }
                }
            }
            .sheet(isPresented: Binding(get: { model.editor.presented }, set: { model.editor.presented = $0 }), onDismiss: { model.restoreRevision() }) {
                ItineraryEditorView(editor: model.editor, model: model)
            }
            .sheet(item: $model.candidateDetail){row in NavigationStack { SimplePlaceDetail(model: model, row: row) }}
            .sheet(item: Binding(get: {model.pendingOrigin ? nil : model.pending}, set: {model.pending = $0})){
                _ in NavigationStack { PersonalAppleConfirmation(model: model) }
            }
        }
    }
}

private struct SimpleDiscoverView: View {
    @Bindable var model: PersonalLabModel
    @Binding var sheet: SimplePersonalSheet?
    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    Button { sheet = .trip } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.area).font(.headline)
                                Text("\(model.day.formatted(.dateTime.day().month())) · \(clockLabel(model.departureMinute))–\(clockLabel(model.deadlineMinute)) WIB")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "pencil").foregroundStyle(.secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("simple-trip").disabled(model.busy)
                    if model.browsePlaces.isEmpty {
                        Button("Temukan tempat"){model.recommend()}
                            .buttonStyle(.borderedProminent).disabled(model.busy).accessibilityIdentifier("simple-find")
                    }
                }
                if let error = model.error {
                    Section { Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red) }
                        .id("simple-discovery-error").accessibilityIdentifier("simple-discovery-error")
                }
                if !model.browsePlaces.isEmpty {
                    Section("Pilihan untuk Anda") {
                        ForEach(Array(model.browsePlaces.enumerated()), id: \.element.id) { index, row in
                            Button{ model.open(row) } label: { SimplePlaceRow(model: model, row: row) }
                                .buttonStyle(.plain).disabled(model.busy).accessibilityIdentifier("simple-candidate-\(index)")
                                .id(row.id).onAppear { model.candidateAppeared(row) }
                        }
                    }
                    Section {
                        if model.canLoadMore {
                            Button { model.recommend(more: true) } label: { Label("Cari lainnya", systemImage: "plus.circle") }
                                .disabled(model.busy).accessibilityIdentifier("simple-more")
                        } else { Text("Belum ada pilihan lain untuk area dan waktu ini.").font(.footnote).foregroundStyle(.secondary) }
                        if model.status.hasPrefix("Belum ada pilihan baru") { Text(model.status).font(.footnote) }
                    }
                }
                if model.busy {
                    Section { HStack { ProgressView(); Text("Memeriksa pilihan…").foregroundStyle(.secondary) } }
                        .accessibilityIdentifier("simple-search-progress")
                }
            }
            .navigationTitle("Jelajah")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing){Button("Preferensi", systemImage: "person.crop.circle"){sheet = .profile}.labelStyle(.iconOnly).disabled(model.busy)}
            }
            .safeAreaInset(edge: .bottom) {
                if !model.stops.isEmpty {
                    Button { model.selectedTab = 1 } label: {
                        HStack{Text("Tinjau \(model.stops.count) pilihan"); Spacer(); Image(systemName: "arrow.right")}.frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.large).padding(.horizontal).padding(.vertical, 8)
                        .background(.bar).accessibilityIdentifier("simple-review")
                }
            }
            .onChange(of: model.recommendation?.id) { _, _ in
                if let first = model.recommendation?.places.first?.id {
                    Task { @MainActor in await Task.yield(); proxy.scrollTo(first, anchor: .top) }
                }
            }
            .onChange(of: model.error) { _, value in if value != nil { proxy.scrollTo("simple-discovery-error", anchor: .top) } }
        }
    }
}

private struct SimplePlaceRow: View {
    let model: PersonalLabModel
    let row: PersonalRecommendedPlace
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(row.candidate.name).font(.headline)
                Text(row.candidate.categories.map(\.label).joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                if row.candidate.hoursState != "available" { Text("Jam belum pasti").font(.caption).foregroundStyle(.orange) }
            }
            Spacer(minLength: 4)
            if let selected = model.stops.first(where: {$0.stop.place.prepared.googlePlaceID == row.id}) {
                Label(selected.required ? "Wajib" : "Jika sempat", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tint).labelStyle(.iconOnly)
            } else { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
        }.padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}

private struct SimplePlaceDetail: View {
    let model: PersonalLabModel
    let row: PersonalRecommendedPlace
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Section {
                Text(row.candidate.name).font(.title2.bold())
                Text(row.candidate.categories.map(\.label).joined(separator: " · ")).foregroundStyle(.secondary)
                if let reason = row.reasons.first { Text(reason).font(.subheadline) }
                if row.candidate.hoursState != "available" { Label("Jam kunjungan belum pasti", systemImage: "clock.badge.questionmark").foregroundStyle(.orange) }
            }
            Section {
                Button("Wajib dikunjungi"){ model.choose(row, required: true) }.accessibilityIdentifier("personal-select-required")
                Button("Jika sempat"){ model.choose(row, required: false) }.accessibilityIdentifier("personal-select-optional")
            }
            Section {
                DisclosureGroup("Alamat, jam, dan sumber") {
                    Text(row.candidate.address)
                    ForEach(Array(row.candidate.hours.enumerated()), id: \.offset) { _, interval in
                        let start = ContextLabModel.time(interval.start), end = ContextLabModel.time(interval.end)
                        Text(interval.end.timeIntervalSince(interval.start) == 86400 ? "Buka 24 jam" : "\(start)–\(end) WIB")
                    }
                    if let raw = row.candidate.googleMapsURL, let url = URL(string: raw) { Link("Lihat sumber Google Maps", destination: url) }
                    ForEach(row.candidate.unknowns, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }.navigationTitle("Detail tempat").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction){Button("Tutup"){dismiss()}} }
    }
}

private struct SimpleTripEditor: View {
    let model: PersonalLabModel
    @State private var area: String
    @State private var day: Date
    @State private var start: Int
    @State private var end: Int
    @State private var problem: String?
    @State private var reset = false
    @Environment(\.dismiss) private var dismiss
    init(model: PersonalLabModel) {
        self.model = model; _area = State(initialValue: model.area); _day = State(initialValue: model.day)
        _start = State(initialValue: model.departureMinute); _end = State(initialValue: model.deadlineMinute)
    }
    var body: some View {
        Form {
            TextField("Area di Jakarta", text: $area).autocorrectionDisabled().accessibilityIdentifier("simple-area")
            DatePicker("Tanggal", selection: $day, in: ContextClock.calendar.startOfDay(for: .now)..., displayedComponents: .date)
            Picker("Mulai WIB", selection: $start) {
                ForEach(Array(stride(from: 480, through: 1080, by: 30)), id: \.self) { Text(clockLabel($0)).tag($0) }
            }.accessibilityIdentifier("simple-start-time")
            Picker("Selesai WIB", selection: $end) {
                ForEach(Array(stride(from: 960, through: 1260, by: 30)), id: \.self) { Text(clockLabel($0)).tag($0) }
            }
            if !model.stops.isEmpty { Text("Mengubah area, tanggal, atau jam akan memulai pencarian baru.").font(.footnote).foregroundStyle(.secondary) }
            if let problem { Text(problem).foregroundStyle(.red) }
            if !model.browsePlaces.isEmpty {
                Section { Button("Mulai pencarian baru", role: .destructive){reset = true} }
            }
        }.navigationTitle("Perjalanan")
            .confirmationDialog("Mulai pencarian dari awal?", isPresented: $reset, titleVisibility: .visible) {
                Button("Mulai ulang", role: .destructive){model.invalidate(); dismiss()}
            } message: { Text("Daftar rekomendasi dan pilihan tujuan saat ini akan dikosongkan.") }
            .toolbar {
                ToolbarItem(placement: .cancellationAction){Button("Batal"){dismiss()}}
                ToolbarItem(placement: .confirmationAction){Button("Simpan"){
                    let context = PersonalTripContext(area: area.trimmingCharacters(in: .whitespacesAndNewlines), day: ContextClock.label(day), departureMinute: start, deadlineMinute: end)
                    do { try context.validate() }catch{problem = error.localizedDescription; return}
                    if context != model.context {
                        model.area = context.area; model.day = day; model.departureMinute = start; model.deadlineMinute = end
                        model.invalidate(); model.origin = nil; model.originResults = []
                    }
                    dismiss()
                }}
            }
    }
}

private struct SimpleProfileEditor: View {
    @Bindable var model: PersonalLabModel
    let diagnostics: ContextLabModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section("Minat Anda") { PersonalInterestEditor(model: model) }
            Section { NavigationLink("Buka lab pengujian"){ContextLabView(model: diagnostics)}.foregroundStyle(.secondary) }
        }.navigationTitle("Preferensi")
            .toolbar{ToolbarItem(placement: .confirmationAction){Button("Selesai"){dismiss()}}}
    }
}

private struct SimpleOriginEditor: View {
    @Bindable var model: PersonalLabModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    var body: some View {
        Form {
            Section {
                TextField("Nama tempat awal", text: $model.originQuery).autocorrectionDisabled().focused($focused)
                    .accessibilityIdentifier("personal-origin-query")
                Button("Cari lokasi awal") { focused = false; model.searchOrigin() }
                    .disabled(model.busy || model.originQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("personal-origin-search")
                if model.busy { ProgressView() }
                if let error = model.error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            ForEach(Array(model.originResults.enumerated()), id: \.offset){index, place in
                if let id = place.id {
                    Button {
                        model.prepareOrigin(id)
                    } label: {
                        VStack(alignment: .leading){Text(place.displayName?.text ?? "Lokasi awal"); Text(place.formattedAddress ?? "").font(.caption).foregroundStyle(.secondary)}
                    }.disabled(model.busy).accessibilityIdentifier("personal-origin-result-\(index)")
                }
            }
        }.navigationTitle("Lokasi awal")
            .toolbar{ToolbarItem(placement: .cancellationAction){Button("Tutup"){dismiss()}}}
            .sheet(item: $model.pending, onDismiss: {
                if model.originResults.isEmpty && model.origin != nil { dismiss() }
            }){_ in NavigationStack { PersonalAppleConfirmation(model: model) }}
    }
}

private struct SimpleAdjustments: View {
    @Bindable var model: PersonalLabModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section("Perjalanan") {
                Stepper("Menunggu maksimal \(model.waitingMinutes) menit", value: $model.waitingMinutes, in: 0 ... 120, step: 5)
                Toggle("Sesuaikan dengan hujan", isOn: $model.rainAdjustmentEnabled)
                Text("Untuk kegiatan yang diketahui berada di luar ruang. Cuaca yang belum tersedia tetap belum diketahui.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach($model.stops) { $row in
                Section(row.stop.place.prepared.name) {
                    Toggle("Wajib dikunjungi", isOn: $row.required)
                    Picker("Durasi", selection: $row.stop.durationMinutes) { ForEach([15, 30, 45, 60, 90, 120], id: \.self){Text("\($0) menit").tag($0)} }
                    DisclosureGroup("Pengaturan kegiatan") {
                        Picker("Tempat kegiatan", selection: $row.stop.exposure){
                            Text("Belum diketahui").tag(ActivityExposure.unknown); Text("Indoor").tag(ActivityExposure.indoor)
                            Text("Outdoor").tag(ActivityExposure.outdoor); Text("Campuran").tag(ActivityExposure.mixed)
                        }
                        Toggle("Utamakan mulai 15–16 WIB", isOn: $row.stop.afternoon)
                    }
                    Button("Hapus tujuan", role: .destructive){model.remove(row.id)}
                }
            }
        }.navigationTitle("Sesuaikan rencana")
            .toolbar{ToolbarItem(placement: .confirmationAction){Button("Selesai"){dismiss()}}}
    }
}

private struct SimplePlanView: View {
    @Bindable var model: PersonalLabModel
    @Binding var sheet: SimplePersonalSheet?
    var body: some View {
        ScrollViewReader { proxy in
            List {
                if model.planOutput == nil, model.editor.state.current != nil {
                    Button("Buka itinerary tersimpan") { model.restoreRevision() }.disabled(model.busy)
                }
                if let output = model.planOutput {
                    SimplePlanResult(model: model, output: output).id("simple-result")
                }
                Section("Tujuan Anda") {
                    if model.stops.isEmpty {
                        Text("Pilih tempat di Jelajah untuk mulai menyusun perjalanan.").foregroundStyle(.secondary)
                        Button("Jelajahi tempat"){model.selectedTab = 0}
                    }
                    ForEach(model.stops){row in
                        VStack(alignment: .leading, spacing: 4){
                            Text(row.stop.place.prepared.name).font(.headline)
                            Text("\(row.required ? "Wajib" : "Jika sempat") · \(row.stop.durationMinutes) menit")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.accessibilityIdentifier("simple-selected-stop")
                    }
                    if !model.stops.isEmpty { Button("Sesuaikan durasi dan batas"){sheet = .adjustments}.disabled(model.busy) }
                }
                if !model.stops.isEmpty {
                    Section {
                        Button { sheet = .origin } label: {
                            HStack{Text(model.origin?.prepared.name ?? "Pilih lokasi awal"); Spacer(); Image(systemName: "chevron.right").font(.caption)}
                        }.disabled(model.busy).accessibilityIdentifier("simple-origin")
                        Picker("Transportasi", selection: $model.transport) {
                            Text("Mobil").tag(ContextTransport.automobile)
                            Text("TJ + jalan kaki").tag(ContextTransport.transjakarta)
                        }.disabled(model.busy)
                        Text("Kembali ke lokasi awal · total menunggu maks. \(model.waitingMinutes) menit")
                            .font(.footnote).foregroundStyle(.secondary)
                        if model.rainAdjustmentEnabled { Label("Cuaca otomatis untuk kegiatan luar ruang", systemImage: "cloud.sun.rain").font(.footnote).foregroundStyle(.secondary) }
                        if model.busy { HStack{ProgressView(); Text("Menyusun perjalanan…")} }
                        if let error = model.error { Text(error).foregroundStyle(.red).font(.footnote) }
                        Button("Susun rencana"){model.makePlan()}.buttonStyle(.borderedProminent)
                            .disabled(model.busy || model.origin == nil).accessibilityIdentifier("personal-plan")
                    }
                }
            }.navigationTitle("Rencana")
                .onChange(of: model.planID){_, _ in Task { @MainActor in await Task.yield(); proxy.scrollTo("simple-result", anchor: .top) }}
                .onChange(of: model.planSettings){_, value in if value != model.appliedSettings { model.planOutput = nil } }
        }
    }
}

private struct SimplePlanResult: View {
    let model: PersonalLabModel
    let output: PersonalPlanResult
    var body: some View {
        let trip = output.result.itinerary
        Section("Perjalanan Anda") {
            if let error = model.editor.error { Text(error).foregroundStyle(.red) }
            Button(model.editor.state.draft == nil ? "Edit perjalanan" : "Lanjutkan edit perjalanan") { model.editor.begin() }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("revision-open")
            if !model.editor.state.revisions.isEmpty {
                NavigationLink("Riwayat versi (\(model.editor.state.revisions.count))") { ItineraryHistoryView(state: model.editor.state) }.accessibilityIdentifier("revision-history")
            }

            if trip.visits.isEmpty {
                Label("Jadwal belum dapat disusun", systemImage: "calendar.badge.exclamationmark")
                    .accessibilityIdentifier("personal-plan-status")
            } else {
                Text("\(trip.visits.count) tujuan · pulang \(trip.finish.map(ContextLabModel.time) ?? "–") WIB")
                    .font(.headline).accessibilityIdentifier("personal-plan-status")
                Text("Menunggu \(trip.totalWaitingSeconds / 60, specifier: "%.1f") menit").font(.subheadline).foregroundStyle(.secondary)
                if let moment = output.result.moment {
                    let place = model.stops.first { $0.stop.place.prepared.googlePlaceID == moment.placeID }?.stop.place.prepared.name
                    if let place { TripMomentCard(moment: moment, place: place) }
                }
                if let map = PersonalRouteMapData(model: model, trip: trip) { PersonalRouteMap(data: map).id(model.planID) }
                ForEach(Array(trip.visits.enumerated()), id: \.element.placeID){index, visit in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)").font(.caption.bold()).frame(width: 26, height: 26).background(Color.accentColor.opacity(0.13), in: Circle())
                        VStack(alignment: .leading, spacing: 4) {

                            Text(model.stops.first{$0.stop.place.prepared.googlePlaceID == visit.placeID}?.stop.place.prepared.name ?? "Tujuan").font(.headline)
                            Text("\(ContextLabModel.time(visit.visit.start))–\(ContextLabModel.time(visit.visit.end)) WIB").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            DisclosureGroup("Mengapa susunannya seperti ini?") {
                if !trip.visits.isEmpty { Text("Durasi kunjungan muat dalam jam buka yang tersedia. Perjalanan dan menunggu diperiksa terhadap batas pulang Anda.") }
                ForEach(output.omitted, id: \.id){item in
                    let name = model.stops.first{$0.stop.place.prepared.googlePlaceID == item.id}?.stop.place.prepared.name ?? "Tujuan"
                    VStack(alignment: .leading){
                        Text(item.required ? "Wajib belum terjadwal: \(name)" : "Jika sempat, belum masuk: \(name)")
                        Text(item.reason == "closed" ? "Tempat diketahui tutup." : "Belum terpilih dalam jadwal yang dapat disusun.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(trip.visits, id: \.placeID){visit in
                    if let rain = visit.visit.assessments.first(where: {$0.goal == .lowerRain}) {
                        Text(rain.penalty.map{"Peluang hujan tertinggi saat kunjungan luar ruang: \(Int($0))%."} ?? "Prakiraan hujan untuk kunjungan ini belum lengkap.").font(.footnote)
                    }
                }
                if model.rainAdjustmentEnabled && model.stops.contains(where: {$0.stop.exposure == .unknown || $0.stop.exposure == .mixed}) {
                    Text("Dampak hujan belum dinilai untuk kegiatan dengan paparan yang belum jelas.").font(.footnote)
                }
                if trip.searchTruncated { Text("Pemeriksaan terbatas pada beberapa pilihan jadwal.").font(.footnote) }
                ForEach(output.result.weatherAttributions, id: \.self){Text($0).font(.caption2)}
                Text("Jam tempat: Google Maps. Tiket dan akses masuk masih perlu diperiksa.").font(.caption2)
            }
        }
    }
}

struct TripMomentCard: View {
    let moment: VisitOpportunity
    let place: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Momen perjalanan", systemImage: "sunset")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Menjelang matahari terbenam di \(place)")
                .font(.headline)
                .accessibilityIdentifier("personal-trip-moment")
            Text("Jadwal menyisakan waktu di sini dalam rentang \(ContextLabModel.time(moment.start))–\(ContextLabModel.time(moment.end)) WIB. Cahaya bergantung pada kondisi saat tiba.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Link("Sumber lokasi", destination: moment.sourceURL)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}
