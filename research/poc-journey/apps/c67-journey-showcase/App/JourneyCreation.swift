import SwiftUI
import PreferenceQuality
import TripIntegration
import VisitTiming

struct JourneySetup: View {
    @Bindable var model: JourneyModel
    private func binding<T>(_ path: WritableKeyPath<TripRequest, T>) -> Binding<T> {
        .init(get: { model.request[keyPath: path] }, set: { value in model.edit { $0[keyPath: path] = value } })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Kapan kita berangkat?").font(JourneyTheme.font(30, relativeTo: .title).weight(.semibold))
            Text("Pilih katalog bersumber dan atur perjalanan satu hari.").foregroundStyle(.secondary)
            Picker("Area katalog", selection: Binding(get: { model.request.useCityCatalog == true }, set: { model.switchArea(city: $0) })) {
                Text("Blok M").tag(false)
                Text("Jakarta").tag(true)
            }.pickerStyle(.segmented).accessibilityIdentifier("catalog-area")
            Text(model.request.useCityCatalog == true ? "Katalog gabungan Blok M, Cikini, Tebet, Senayan, Ragunan, dan area lain. Pilih area dan spot pada langkah berikutnya." : "Pilihan tempat di sekitar Blok M.").font(.footnote).foregroundStyle(.secondary)
            JourneyOriginPicker(model: model)
            JourneyPanel {
                DatePicker("Tanggal", selection: Binding(get: { model.request.departure }, set: { value in
                    model.edit { input in
                        let departure = TripClock.calendar.dateComponents([.hour, .minute], from: input.departure)
                        let finish = TripClock.calendar.dateComponents([.hour, .minute], from: input.deadline)
                        input.departure = TripClock.calendar.date(bySettingHour: departure.hour!, minute: departure.minute!, second: 0, of: value)!
                        input.deadline = TripClock.calendar.date(bySettingHour: finish.hour!, minute: finish.minute!, second: 0, of: value)!
                    }
                }), in: model.dateRange, displayedComponents: .date)
                Divider()
                DatePicker("Berangkat", selection: binding(\.departure), displayedComponents: .hourAndMinute)
                DatePicker("Kembali sebelum", selection: binding(\.deadline), displayedComponents: .hourAndMinute)
                Text("Semua waktu menggunakan WIB.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Bagaimana perjalanannya?").font(JourneyTheme.font(23, relativeTo: .title2).weight(.semibold))
            ForEach(TripTransport.allCases) { transport in
                Button {
                    model.edit { $0.transport = transport }
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: transport == .transjakartaBRT ? "bus.fill" : "car.fill")
                            .font(.title2).frame(width: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(transport.label).font(JourneyTheme.font(18).weight(.semibold))
                            Text(transport == .transjakartaBRT ? "Jaringan TJ + walking · hingga satu transfer" : "Estimasi perjalanan mobil/taksi")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: model.request.effectiveTransport == transport ? "checkmark.circle.fill" : "circle")
                    }.padding(20).frame(maxWidth: .infinity, minHeight: 88, alignment: .leading).contentShape(Rectangle())
                        .background(JourneyTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(model.request.effectiveTransport == transport ? JourneyTheme.blue : Color.clear, lineWidth: 2))
                }.buttonStyle(.plain).foregroundStyle(.primary)
                    .accessibilityAddTraits(model.request.effectiveTransport == transport ? .isSelected : [])
                    .accessibilityIdentifier("transport-" + transport.rawValue)
            }
            JourneyPanel {
                Stepper("\(model.request.desiredCount) tempat", value: binding(\.desiredCount), in: 1 ... 6)
                    .accessibilityIdentifier("place-count")
                Divider()
                Stepper("\(model.request.defaultDuration) menit per tempat", value: binding(\.defaultDuration), in: 15 ... 360, step: 15)
                Text("Kamu bisa menambah durasi tiap tempat setelah itinerary dibuat.").font(.footnote).foregroundStyle(.secondary)
            }
            if model.request.effectiveTransport == .transjakartaBRT {
                Label("Estimasi bus memakai GTFS dengan buffer satu headway penuh. Akses dan tiap ruas jalan kaki dibatasi 20 menit.", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            JourneyBudgetPanel(model: model)
        }
    }
}

struct JourneyPreferences: View {
    @Bindable var model: JourneyModel
    private let features: [QualityFeature] = [.coffee, .wifi, .reading, .art, .culture, .nature, .outdoor, .quietPolicy]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Isi harimu dengan hal yang kamu suka.").font(JourneyTheme.font(30, relativeTo: .title).weight(.semibold))
            Text("Pilih beberapa minat, atau lanjutkan untuk melihat pilihan umum.").foregroundStyle(.secondary)
            JourneyDestinationPreferences(model: model)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                ForEach(features) { feature in
                    let chosen = model.request.profile.prefer.contains(feature)
                    Button {
                        model.edit { input in
                            input.profile.must.remove(feature); input.profile.avoid.remove(feature)
                            if chosen { input.profile.prefer.remove(feature) } else { input.profile.prefer.insert(feature) }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: feature.journeySymbol).font(.title2)
                                Spacer()
                                if chosen { Image(systemName: "checkmark.circle.fill").foregroundStyle(JourneyTheme.blue) }
                            }
                            Text(feature.journeyTitle).font(JourneyTheme.font(18).weight(.semibold))
                        }.frame(maxWidth: .infinity, minHeight: 78, alignment: .leading).padding(18)
                            .background(JourneyTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(chosen ? JourneyTheme.blue : Color.clear, lineWidth: 2))
                    }.buttonStyle(.plain).accessibilityIdentifier("interest-" + feature.rawValue)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            JourneyPanel {
                DisclosureGroup("Syarat wajib & yang dihindari") {
                    ForEach(QualityFeature.allCases) { feature in
                        Picker(feature.journeyTitle, selection: Binding(get: {
                            model.request.profile.must.contains(feature) ? "must" : model.request.profile.avoid.contains(feature) ? "avoid" : "neutral"
                        }, set: { value in
                            model.edit { input in
                                input.profile.must.remove(feature); input.profile.avoid.remove(feature)
                                if value != "neutral" { input.profile.prefer.remove(feature) }
                                if value == "must" { input.profile.must.insert(feature) }
                                if value == "avoid" { input.profile.avoid.insert(feature) }
                            }
                        })) {
                            Text("Bebas").tag("neutral")
                            Text("Wajib").tag("must")
                            Text("Hindari").tag("avoid")
                        }
                    }
                }
                Text("Atribut yang belum punya bukti tetap ditampilkan sebagai belum diketahui.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct JourneyPlaces: View {
    @Bindable var model: JourneyModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("\(model.selected.count) tempat untuk harimu").font(JourneyTheme.font(30, relativeTo: .title).weight(.semibold))
            Text(model.request.profile.hasSignal ? "Rekomendasi mengikuti minat, area, spot wajib, dan fakta tempat yang tersedia. Tinjau pilihanmu sebelum lanjut." : (!(model.request.targetAreas ?? []).isEmpty || !model.request.requiredCandidateIDs.isEmpty) ? "Pilihan mengikuti area dan spot wajibmu. Tambahkan minat untuk menyesuaikan jenis tempat." : "Ini pilihan umum dari katalog \(model.request.useCityCatalog == true ? "Jakarta" : "Blok M"). Kamu bisa kembali untuk menambahkan minat.")
                .foregroundStyle(.secondary)
            JourneyBudgetPanel(model: model)
            if let review = model.review {
                let proposed = review.suggestions.filter { $0.recommended || $0.required || model.selected.contains($0.id) }
                if proposed.isEmpty {
                    ContentUnavailableView("Belum ada tempat yang cocok", systemImage: "magnifyingglass", description: Text("Coba ubah syarat wajib atau lihat atribut yang belum diketahui pada alternatif."))
                }
                ForEach(proposed) { item in JourneyPlaceCard(model: model, item: item) }
                DisclosureGroup("Lihat alternatif & ketersediaannya") {
                    VStack(spacing: 16) {
                        ForEach(review.suggestions.filter { !$0.recommended && !$0.required && !model.selected.contains($0.id) }) { item in
                            JourneyPlaceCard(model: model, item: item)
                        }
                    }.padding(.top, 12)
                }.font(JourneyTheme.font(17))
            }
        }
    }
}

private struct JourneyPlaceCard: View {
    @Bindable var model: JourneyModel
    let item: PlaceSuggestion
    var body: some View {
        JourneyPanel {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol).font(.title2).foregroundStyle(JourneyTheme.blue)
                    .frame(width: 48, height: 48).background(JourneyTheme.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 16)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(JourneyTheme.font(21, relativeTo: .title3).weight(.semibold))
                    Text(item.area).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { model.select(item) } label: {
                    Image(systemName: model.selected.contains(item.id) ? "checkmark.circle.fill" : "plus.circle")
                        .font(.title2).frame(minWidth: 44, minHeight: 44)
                }.disabled(!item.selectable || item.required)
                    .accessibilityLabel(model.selected.contains(item.id) ? "Lepas \(item.name)" : "Pilih \(item.name)")
                    .accessibilityIdentifier("select-" + item.id)
            }
            if item.selectable {
                Label("Jam kunjungan tersedia", systemImage: "clock").font(.footnote).foregroundStyle(.secondary)
            }
            let matches = model.request.profile.must.union(model.request.profile.prefer).filter { model.catalog.candidate(item.id)?.value($0) == .yes }
            if !matches.isEmpty {
                Text("Cocok dengan \(matches.sorted { $0.rawValue < $1.rawValue }.map(\.journeyTitle).joined(separator: ", "))")
                    .font(.footnote).foregroundStyle(JourneyTheme.blue)
            }
            ForEach(item.issues, id: \.self) { Text($0).font(.footnote).foregroundStyle(.orange) }
            HStack {
                Button(item.required ? "Wajib dikunjungi" : "Jadikan wajib", systemImage: item.required ? "pin.fill" : "pin") { model.toggleRequired(item) }
                    .font(.footnote).disabled(!item.selectable).frame(minHeight: 44)
                Spacer()
                Text("\(model.request.duration(item.venueID)) menit").font(.footnote).foregroundStyle(.secondary)
            }
            DisclosureGroup("Alasan dan sumber") {
                ForEach(item.reasons, id: \.self) { Text($0).font(.footnote) }
                ForEach(model.catalog.quality.sources.filter { item.sourceIDs.contains($0.id) }) { source in
                    Link(source.title, destination: source.url).font(.footnote)
                }
            }.font(.footnote)
        }
    }
    private var symbol: String {
        let candidate = model.catalog.candidate(item.id)
        if candidate?.value(.coffee) == .yes { return "cup.and.saucer" }
        if candidate?.value(.nature) == .yes { return "leaf" }
        if candidate?.value(.art) == .yes { return "paintpalette" }
        return "building.columns"
    }
}

struct JourneyReview: View {
    @Bindable var model: JourneyModel
    @State private var location: LocationReview?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Satu hari, \(model.selected.count) tempat.").font(JourneyTheme.font(30, relativeTo: .title).weight(.semibold))
            JourneyPanel {
                JourneyInfo(symbol: "calendar", title: "Tanggal", value: TripClock.day(model.request.departure))
                JourneyInfo(symbol: "clock", title: "Waktu", value: "\(JourneyTime.clock(model.request.departure))–\(JourneyTime.clock(model.request.deadline)) WIB")
                JourneyInfo(symbol: "arrow.triangle.swap", title: "Pulang-pergi", value: model.request.originQuery)
                if let areas = model.request.targetAreas, !areas.isEmpty {
                    JourneyInfo(symbol: "mappin.and.ellipse", title: "Area pilihan", value: areas.map(\.label).joined(separator: ", "))
                }
                JourneyInfo(symbol: model.request.effectiveTransport == .transjakartaBRT ? "bus" : "car", title: "Transportasi", value: model.request.effectiveTransport.label)
            }
            Text("Lokasi pilihan").font(JourneyTheme.font(23, relativeTo: .title2).weight(.semibold))
            JourneyBudgetPanel(model: model)
            if let prepared = model.prepared {
                ForEach(prepared.locations) { value in
                    JourneyPanel {
                        Text(model.catalog.candidate(value.id)?.name ?? model.request.originQuery).font(JourneyTheme.font(19).weight(.semibold))
                        if let pin = value.selected {
                            Label(pin.name, systemImage: "checkmark.circle").font(.callout)
                            Text(pin.address).font(.footnote).foregroundStyle(.secondary)
                            Text(model.mode == .demo ? "Lokasi contoh untuk demo" : value.manualConfirmation ? "Dikonfirmasi pengguna" : "Kecocokan lokasi dari MapKit").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(value.issue ?? "Konfirmasi lokasi terlebih dahulu.").font(.footnote).foregroundStyle(.orange)
                        }
                        if !value.candidates.isEmpty {
                            Button(value.selected == nil ? "Pilih cabang/lokasi" : "Tinjau lokasi") { location = value }.frame(minHeight: 44)
                        } else { Button("Coba periksa ulang", action: model.verify) }
                    }
                }
            }
            Text("Cuaca, waktu kunjungan, dan waktu kembali akan diperiksa ketika itinerary disusun.").font(.footnote).foregroundStyle(.secondary)
        }.sheet(item: $location) { item in
            NavigationStack {
                List(item.candidates) { pin in
                    Button {
                        model.choose(pin.id, locationID: item.id); location = nil
                    } label: {
                        VStack(alignment: .leading, spacing: 6) { Text(pin.name).font(.headline); Text(pin.address).font(.footnote) }
                    }.padding(.vertical, 8)
                }.navigationTitle("Konfirmasi lokasi").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { location = nil } } }
            }
        }
    }
}

struct JourneyBudgetPanel: View {
    @Bindable var model: JourneyModel
    var body: some View {
        JourneyPanel {
            Text("Waktu untuk perjalanan").font(.headline)
            Text(model.timeBudget.message).font(.footnote)
                .foregroundStyle(model.timeBudget.visitsExceedBudget ? Color.orange : Color.secondary)
                .accessibilityIdentifier("time-budget")
            Text("Waktu transportasi dan jam tempat diperiksa saat kalkulasi.").font(.caption).foregroundStyle(.secondary)
            Button("Tambah waktu trip 1 jam") { model.adjustTimeBudget(longerDay: true) }
                .disabled(TripClock.minute(model.request.deadline) >= 1439)
                .accessibilityIdentifier("budget-longer")
            Button("Kurangi tiap kunjungan 15 menit") { model.adjustTimeBudget(longerDay: false) }
                .disabled(model.request.defaultDuration == 15 && model.request.durationByVenue.values.allSatisfy { $0 == 15 })
                .accessibilityIdentifier("budget-shorter")
        }
    }
}
