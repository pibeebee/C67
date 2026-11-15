import SwiftUI
import PlaceContextEngine
import DynamicTripContracts
import RecommendationContracts

struct PersonalRootView: View {
    @Bindable var model: PersonalLabModel
    let diagnostics: ContextLabModel
    var body: some View {
        if !model.onboarded { NavigationStack { PersonalOnboarding(model: model) } }
        else {
            TabView(selection: $model.selectedTab) {
                NavigationStack { PersonalRecommendationView(model: model) }.tabItem{Label("Rekomendasi", systemImage: "sparkles")}.tag(0)
                NavigationStack { PersonalPlanView(model: model) }.tabItem{Label("Rencana", systemImage: "list.bullet.rectangle")}.tag(1)
                NavigationStack { PersonalProfileView(model: model) }.tabItem{Label("Profil", systemImage: "person.crop.circle")}.tag(2)
                ContextLabView(model: diagnostics).tabItem{Label("Lab", systemImage: "testtube.2")}.tag(3)
            }
            .sheet(item: $model.pending){_ in NavigationStack{PersonalAppleConfirmation(model: model)}}
            .sheet(item: $model.candidateDetail){row in NavigationStack{PersonalCandidateDetail(model: model, row: row)}}
        }
    }
}
struct PersonalInterestEditor: View {
    @Bindable var model: PersonalLabModel
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(PersonalInterest.allCases) { interest in
                let selected = model.learning.profile.interests.contains(interest)
                Button { model.toggle(interest) } label: {
                    Label(interest.label, systemImage: selected ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                }.buttonStyle(.bordered).tint(selected ? .accentColor : .secondary)
                    .accessibilityIdentifier("interest-" + interest.rawValue).accessibilityValue(selected ? "Dipilih" : "Belum dipilih")
            }
        }
        Picker("Ritme perjalanan", selection: Binding(get: {model.learning.profile.pace}, set: {model.setPace($0)})) {
            ForEach(PersonalPace.allCases, id: \.self){Text($0.label).tag($0)}
        }.pickerStyle(.segmented).accessibilityIdentifier("personal-pace")
        Text("Ritme menjadi arahan umum. Durasi dan batas menunggu tetap Anda periksa saat menyusun rencana.").font(.caption).foregroundStyle(.secondary)
    }
}
struct PersonalOnboarding: View {
    @Bindable var model: PersonalLabModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Pengalaman apa yang Anda sukai?").font(.title2.bold())
                Text("Pilih minat sebagai profil awal. Pilihan ini otomatis dipakai untuk perjalanan berikutnya dan bisa diubah.").foregroundStyle(.secondary)
                PersonalInterestEditor(model: model)
                Button("Simpan dan lanjutkan") { model.finishOnboarding() }.buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("personal-onboarding-done")
                Button("Lewati untuk menjelajah umum") { model.finishOnboarding() }.font(.footnote)
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }.padding(20)
        }.navigationTitle("Preferensi Anda")
    }
}
private struct PersonalStatus: View {
    let model: PersonalLabModel
    var body: some View {
        Text(model.status).accessibilityIdentifier("personal-status")
        if model.busy { ProgressView() }
        if let error = model.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("personal-error")
            .accessibilityValue(ProcessInfo.processInfo.arguments.contains("--personal-ui-test") ? model.operationIdentity : "") }
    }
}
private struct PersonalRecommendationView: View {
    @Bindable var model: PersonalLabModel
    @FocusState private var focused: Bool
    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section { PersonalStatus(model: model) }.id("personal-status-anchor")
                Section("Perjalanan ini") {
                    TextField("Area di Jakarta", text: $model.area).focused($focused).accessibilityIdentifier("personal-area")
                    DatePicker("Tanggal", selection: $model.day, in: Date()..., displayedComponents: .date).accessibilityIdentifier("personal-day")
                    Picker("Mulai WIB", selection: $model.departureMinute) {
                        ForEach([480, 540, 600, 660, 720, 780, 840], id: \.self){Text(String(format: "%02d.00", $0 / 60)).tag($0)}
                    }
                    Picker("Selesai WIB", selection: $model.deadlineMinute) {
                        ForEach([960, 1020, 1080, 1140, 1200, 1260], id: \.self){Text(String(format: "%02d.00", $0 / 60)).tag($0)}
                    }
                    Text("Profil otomatis: \(model.learning.profile.interests.isEmpty ? "jelajah umum" : model.learning.profile.interests.map(\.label).joined(separator: ", ")) · \(model.learning.profile.pace.label)")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("personal-profile-summary")
                    Button(model.error == nil ? "Tampilkan rekomendasi" : "Coba lagi rekomendasi") {
                        focused = false; model.recommend()
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("personal-recommend").disabled(model.busy)
                }.disabled(model.busy)
                if let result = model.recommendation {
                    Section("Pilihan berdasarkan minat Anda") {
                        ForEach(Array(result.places.enumerated()), id: \.element.id) { index, row in
                            Button { model.open(row) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(row.candidate.name).font(.headline).foregroundStyle(.primary)
                                    Text(row.candidate.categories.map(\.label).joined(separator: " · ")).font(.caption)
                                    Text(row.reasons.first ?? "Periksa detail dan sumber").font(.caption).foregroundStyle(.secondary)
                                    if row.candidate.hoursState != "available" { Text("Bersyarat · jam belum terverifikasi").font(.caption).foregroundStyle(.orange) }
                                }.padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("personal-candidate-\(index)")
                                .accessibilityValue(ProcessInfo.processInfo.arguments.contains("--personal-ui-test") ? result.id.uuidString : row.candidate.hoursState)
                                .id("personal-first-candidate-\(index)").onAppear{model.candidateAppeared(row)}
                        }
                        Text(result.places.allSatisfy{$0.id.hasPrefix("fixture-")} ? "SIMULASI: tempat dan jam buatan." : "Jam dan akses mengikuti bukti per cabang.").font(.caption2).foregroundStyle(.secondary)
                    }
                    Section("Lanjutkan") {
                        Button("Tinjau \(model.stops.count) tujuan pilihan") { model.selectedTab = 1 }.accessibilityIdentifier("personal-review-selection")
                    }
                    DisclosureGroup("Pengukuran dan batas eksperimen") {
                        Text("LLM \(result.metrics.llmModel) · biaya $\(result.metrics.costUSD, specifier: "%.4f")")
                        Text("Akuisisi \(result.metrics.acquisitionSeconds, specifier: "%.2f") dtk · E5 \(result.metrics.embeddingSeconds, specifier: "%.2f") dtk · LLM \(result.metrics.llmSeconds, specifier: "%.2f") dtk")
                        Text(model.embeddingInfo)
                        ForEach(Array(result.warnings.enumerated()), id: \.offset){_, warning in Text(warning).font(.caption2)}
                    }.font(.caption)
                }
                Section("Eksperimen terkontrol") {
                    Text("Tempat dan jam buatan; E5 lokal dan LLM tetap dijalankan asli. Kandidat ini tidak dipakai untuk routing live.").font(.caption)
                    Button("Uji AI dengan data tetap") { focused = false; model.recommend(fixture: "balanced") }
                        .accessibilityIdentifier("personal-fixture").disabled(model.busy)
                    Button("Uji jam belum diketahui") { focused = false; model.recommend(fixture: "unknown_hours") }
                        .accessibilityIdentifier("personal-fixture-unknown").disabled(model.busy)
                }
            }.navigationTitle("Temukan pengalaman")
                .onChange(of: model.context){_, _ in model.invalidate()}
                .onChange(of: model.recommendation?.id){_, id in
                    if let id { Task { @MainActor in
                        await Task.yield()
                        if model.recommendation?.id == id { proxy.scrollTo("personal-first-candidate-0", anchor: .top) }
                    }}
                }
                .onChange(of: model.error){_, error in
                    if error != nil { proxy.scrollTo("personal-status-anchor", anchor: .top) }
                }
        }
    }
}
private struct PersonalCandidateDetail: View {
    @Bindable var model: PersonalLabModel
    let row: PersonalRecommendedPlace
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Section {
                Text(row.candidate.name).font(.title2.bold())
                Text(row.candidate.address).font(.subheadline)
                ForEach(row.reasons, id: \.self){Text($0)}
            }
            Section("Jam dan bukti") {
                Text("Jam provider: \(row.candidate.hoursState)")
                ForEach(Array(row.candidate.hours.enumerated()), id: \.offset){_, interval in
                    Text("\(ContextLabModel.time(interval.start))–\(ContextLabModel.time(interval.end)) WIB")
                }
                ForEach(row.candidate.evidence, id: \.id){evidence in
                    VStack(alignment: .leading){Text(evidence.text).font(.caption); Text(evidence.source).font(.caption2).foregroundStyle(.secondary)}
                }
                if let text = row.candidate.evidenceURL, let url = URL(string: text){Link("Lihat sumber fakta", destination: url)}
            }
            Section("Belum diketahui") { ForEach(row.candidate.unknowns, id: \.self){Text($0).font(.caption)} }
            Section("Pilihan Anda") {
                Button("Wajib dikunjungi") { model.choose(row, required: true) }.accessibilityIdentifier("personal-select-required")
                Button("Menarik jika sempat") { model.choose(row, required: false) }.accessibilityIdentifier("personal-select-optional")
                Button("Simpan sebagai sinyal minat") { model.record(.saved, row.candidate); dismiss() }.accessibilityIdentifier("personal-save")
                Button("Lewati untuk perjalanan ini") { model.record(.skipped, row.candidate); dismiss() }.accessibilityIdentifier("personal-skip")
            }
        }.navigationTitle("Detail tempat").navigationBarTitleDisplayMode(.inline)
            .toolbar{Button("Tutup"){dismiss()}}
    }
}
struct PersonalAppleConfirmation: View {
    @Bindable var model: PersonalLabModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            if let pending = model.pending {
                Section("Konfirmasi lokasi untuk rute") {
                    Text(pending.name).font(.headline); Text(pending.address).font(.caption)
                    Text("Pilih hasil Apple yang benar-benar sama. Kedekatan pin belum membuktikan pintu masuk.").font(.caption)
                }
                Section("Hasil Apple Maps") {
                    VenueSearchMap(candidates: pending.appleCandidates)
                    if pending.appleCandidates.isEmpty { Text("Belum ada identitas Apple. Tutup dan gunakan pencarian diagnosis di Lab untuk memeriksa nama/area.") }
                    ForEach(Array(pending.appleCandidates.enumerated()), id: \.element.id){index, candidate in
                        Button { model.confirm(candidate) } label: {
                            VStack(alignment: .leading){Text(candidate.name); Text(candidate.address).font(.caption); Text("Selisih pin \(Int(candidate.distanceFromReferenceMeters)) m").font(.caption2)}
                        }.accessibilityIdentifier("personal-apple-\(index)").disabled(!candidate.canConfirm)
                        if !candidate.canConfirm { Text(candidate.nameSupported == false ? "Ditolak: nama khas tempat belum cocok. Kedekatan pin tidak cukup." : "Ditolak: terlalu jauh untuk padanan tempat pada pilot ini. Cari nama/alamat lain.").font(.caption).foregroundStyle(.red) }
                    }
                }
                Section("Jika hasil belum cocok") {
                    TextField("Nama atau alamat untuk pencarian Apple", text: $model.appleQuery).accessibilityIdentifier("personal-apple-query")
                    Button("Cari ulang identitas Apple"){model.retryAppleIdentity()}.accessibilityIdentifier("personal-apple-retry").disabled(model.busy || model.appleQuery.isEmpty)
                    if let error = model.error { Text(error).foregroundStyle(.red) }
                }
            }
        }.navigationTitle("Identitas tempat").toolbar{Button("Batal"){model.pending = nil; dismiss()}}
    }
}
private struct PersonalPlanView: View {
    @Bindable var model: PersonalLabModel
    @FocusState private var originFocused: Bool
    var body: some View {
        Form {
            Section { PersonalStatus(model: model) }
            Section("Awal dan kembali") {
                if let origin = model.origin { Text(origin.prepared.name).accessibilityIdentifier("personal-chosen-origin") }
                TextField("Cari lokasi awal", text: $model.originQuery).focused($originFocused).accessibilityIdentifier("personal-origin-query")
                Button("Cari lokasi awal") { originFocused = false; model.searchOrigin() }.accessibilityIdentifier("personal-origin-search").disabled(model.busy || model.originQuery.isEmpty)
                VenueSearchMap(places: model.originResults)
                ForEach(Array(model.originResults.enumerated()), id: \.offset){index, place in
                    if let id = place.id { Button(place.displayName?.text ?? id){model.prepareOrigin(id)}.accessibilityIdentifier("personal-origin-result-\(index)") }
                }
                Text("Pilot memakai perjalanan mobil dan kembali ke lokasi awal.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach($model.stops){$row in
                Section(row.stop.place.prepared.name) {
                    Toggle("Wajib dikunjungi", isOn: $row.required).accessibilityIdentifier("personal-required-" + row.stop.place.prepared.placeID)
                    Picker("Durasi", selection: $row.stop.durationMinutes) { ForEach([15, 30, 45, 60, 90, 120], id: \.self){Text("\($0) menit").tag($0)} }
                    Picker("Paparan aktivitas", selection: $row.stop.exposure) {
                        Text("Belum diketahui").tag(ActivityExposure.unknown); Text("Indoor").tag(ActivityExposure.indoor)
                        Text("Outdoor").tag(ActivityExposure.outdoor); Text("Campuran").tag(ActivityExposure.mixed)
                    }
                    Toggle("Utamakan mulai 15–16 WIB", isOn: $row.stop.afternoon)
                    Toggle("Hindari hujan", isOn: $row.stop.avoidRain)
                    Button("Hapus tujuan", role: .destructive){model.remove(row.id)}
                }.disabled(model.busy)
            }
            Section("Batas yang Anda tinjau") {
                Text("\(model.context.day) · \(model.departureMinute / 60).00–\(model.deadlineMinute / 60).00 WIB")
                Stepper("Total menunggu maksimal \(model.waitingMinutes) menit", value: $model.waitingMinutes, in: 0 ... 120, step: 5)
                Picker("Ketelitian waktu", selection: $model.grid){Text("15 menit").tag(15); Text("5 menit").tag(5)}
                Text("Durasi awal 60 menit per tempat dan batas menunggu 30 menit adalah isian yang perlu ditinjau; tidak diturunkan dari ritme Anda.").font(.caption2)
                Button("Susun itinerary") { model.makePlan() }.buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("personal-plan").disabled(model.busy || model.stops.isEmpty || model.origin == nil)
            }.disabled(model.busy)
            if let value = model.planOutput { result(value) }
        }.navigationTitle("Pilihan perjalanan")
    }
    @ViewBuilder private func result(_ value: PersonalPlanResult) -> some View {
        Section("Hasil jadwal") {
            Text(value.result.itinerary.status).accessibilityIdentifier("personal-plan-status")
            Text("\(value.result.itinerary.visits.count) kunjungan · menunggu \(value.result.itinerary.waitingSeconds / 60, specifier: "%.1f") menit")
            ForEach(value.result.itinerary.visits, id: \.placeID){visit in
                VStack(alignment: .leading){Text(model.stops.first{$0.stop.place.prepared.placeID == visit.placeID}?.stop.place.prepared.name ?? visit.placeID).font(.headline)
                    Text("\(ContextLabModel.time(visit.visit.start))–\(ContextLabModel.time(visit.visit.end)) WIB")
                    ForEach(visit.visit.unknowns, id: \.self){Text($0).font(.caption).foregroundStyle(.secondary)}}
            }
            ForEach(value.omitted, id: \.id){item in
                VStack(alignment: .leading){Text(item.required ? "Wajib belum terjadwal" : "Opsional belum dimasukkan").font(.headline)
                    Text(model.stops.first{$0.stop.place.prepared.placeID == item.id}?.stop.place.prepared.name ?? item.id)
                    Text(item.reason).font(.caption)}.foregroundStyle(item.required ? .red : .secondary)
            }
            ForEach(Array(value.result.itinerary.warnings.enumerated()), id: \.offset){_, warning in Text(warning).font(.caption2)}
            ForEach(value.result.weatherAttributions, id: \.self){Text($0).font(.caption2)}
            Text("Jam dan akses mengikuti bukti per cabang.").font(.caption2)
        }
    }
}
private struct PersonalProfileView: View {
    @Bindable var model: PersonalLabModel
    var body: some View {
        Form {
            Section("Minat eksplisit Anda") { PersonalInterestEditor(model: model) }.disabled(model.busy)
            Section("Belajar dari penggunaan") {
                Text("\(model.learning.events.count) interaksi tercatat di perangkat").accessibilityIdentifier("personal-event-count")
                Text("\(model.learning.profile.facetAffinity.count) detail selera dalam minat yang dipilih").accessibilityIdentifier("personal-facet-count")
                Text("Melewati atau menghapus tempat tidak dianggap otomatis tidak suka. Prioritas antarminat hanya berubah melalui pilihan Anda.").font(.caption)
                Text("Pembelajaran awal memakai tipe tempat yang bersumber; bobotnya masih kebijakan eksperimen.").font(.caption2).foregroundStyle(.secondary)
            }
        }.navigationTitle("Profil Anda")
    }
}
