import SwiftUI
import MapKit
import WeatherKit
import PocketEngine

struct PlanScreen: View {
    @Bindable var model: PocketModel
    var body: some View {
        NavigationStack {
            List {
                TripControls(model: model)
                Section("Tujuan · \(model.choices.count)/6") {
                    if model.choices.isEmpty { Text("Tambahkan tujuan dari Jelajah.").foregroundStyle(.secondary) }
                    ForEach(model.choices) { choice in
                        if let venue = model.venue(choice.venueID) { ChosenStopRow(choice: choice, venue: venue, model: model) }
                    }
                }
                Section {
                    if model.isPlanning {
                        HStack { ProgressView(); Text("Memeriksa jadwal dan ETA Apple…") }
                        Button("Batalkan penyusunan", role: .cancel) { model.cancelPlanning() }
                    } else {
                        Button("Susun rencana di iPhone", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { model.computePlan() }
                            .disabled(model.choices.isEmpty || model.origin == nil)
                    }
                    Text("Satu hari WIB · mobil · maksimal enam tujuan. Tujuan wajib dipertahankan. Waktu pulang mencakup perjalanan kembali jika diaktifkan.").font(.caption).foregroundStyle(.secondary)
                }
                if let waiting = model.waitingPlan {
                    Section("Pilihan dengan waktu tunggu") {
                        ForEach(waiting.stops.filter { $0.visitStart > $0.arrival }) { stop in
                            Text("\(stop.name) membutuhkan tunggu \(Int(ceil(stop.visitStart.timeIntervalSince(stop.arrival) / 60))) menit.")
                        }
                        Text("\(waiting.stops.count) kunjungan, selesai \(TripClock.time(waiting.finish)).")
                        Button("Izinkan waktu tunggu dan lihat tawaran") { model.acceptWaitingPlan() }
                        Button("Lewati tujuan yang perlu ditunggu") { model.waitingPlan = nil; model.computePlan() }
                    }
                }
                if let candidate = model.candidatePlan {
                    Section("Tawaran jadwal") {
                        Text("\(candidate.stops.count) dari \(model.targetStops) kunjungan berhasil disusun.")
                        ForEach(candidate.omitted, id: \.self) { Text($0).font(.caption) }
                        ForEach(candidate.stops) { stop in Text("\(stop.name) · \(TripClock.time(stop.visitStart))") }
                        Text("Selesai \(TripClock.time(candidate.finish)).")
                        Button("Gunakan jadwal ini") { model.acceptCandidatePlan() }
                    }
                }
                if model.plan == nil && !model.isPlanning && !model.waitConsent && !model.choices.isEmpty {
                    Section {
                        Button("Periksa pilihan dengan waktu tunggu") { model.computePlan(suggestWait: true) }
                        Text("Pilihan ini memeriksa tambahan waktu tunggu sampai 30 menit per tujuan untuk Anda pertimbangkan.").font(.caption)
                    }
                }
                if !model.adviceNotice.isEmpty { Section("Saran waktu") { Text(model.adviceNotice).font(.caption) } }
                if let plan = model.plan { ItinerarySections(plan: plan, model: model) }
            }
            .navigationTitle("Rencana")
            .environment(\.timeZone, TripClock.calendar.timeZone)
        }
    }
}

struct TripControls: View {
    @Bindable var model: PocketModel
    var body: some View {
        Section("Perjalanan Anda") {
            LabeledContent("Titik awal", value: model.originName)
            Button("Gunakan lokasi saya", systemImage: "location.fill") { model.locate() }.disabled(model.isLocating)
            if model.isLocating { ProgressView("Meminta lokasi…") }
            Toggle("Jam berangkat fleksibel", isOn: $model.flexibleDeparture)
            DatePicker(model.flexibleDeparture ? "Berangkat paling awal" : "Berangkat",
                       selection: $model.departure, displayedComponents: [.date, .hourAndMinute])
            DatePicker("Batas pulang", selection: $model.deadline, displayedComponents: [.date, .hourAndMinute])
            Toggle("Kembali ke titik awal", isOn: $model.returnToOrigin)
            Stepper("Target \(model.targetStops) kunjungan", value: $model.targetStops, in: 1 ... 6)
            if !model.choices.isEmpty {
                Picker("Tujuan terakhir", selection: $model.lastVenueID) {
                    Text("Bebas").tag(String?.none)
                    ForEach(model.choices) { choice in
                        Text(model.venue(choice.venueID)?.name ?? choice.venueID).tag(Optional(choice.venueID))
                    }
                }
            }
            if model.lastVenueID != nil {
                Toggle("Tujuan terakhir untuk makan malam", isOn: $model.dinnerIsLast)
                if model.dinnerIsLast {
                    MinutePicker(title: "Makan malam paling cepat", minute: Binding(get: { model.dinnerNotBefore ?? 18 * 60 },
                                                                                    set: { model.dinnerNotBefore = $0 }), day: model.departure)
                    if model.dinnerNotBefore == nil {
                        Button("Konfirmasi mulai paling cepat pukul 18.00") { model.dinnerNotBefore = 18 * 60 }
                    }
                }
            }
            Toggle("Izinkan waktu tunggu", isOn: $model.waitConsent)
            if model.waitConsent {
                Stepper("Maksimal menunggu \(model.maxWaitMinutes) menit", value: $model.maxWaitMinutes, in: 0 ... 120, step: 15)
            }
            Toggle("Hindari hujan untuk kegiatan outdoor", isOn: $model.avoidRain)
            if model.avoidRain { Text("Batas PoC: peluang hujan maksimal 50% selama kunjungan. Paparan yang belum diketahui atau prakiraan yang kurang akan menahan tujuan.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct ChosenStopRow: View {
    let choice: StopChoice
    let venue: Venue
    let model: PocketModel
    @State private var editing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(venue.name).font(.headline)
            Toggle("Tujuan wajib", isOn: Binding(get: { choice.required || isFixed }, set: { value in
                var next = choice; next.required = value; model.update(next)
            })).disabled(isFixed)
            Stepper("Kunjungan \(choice.durationMinutes) menit", value: Binding(get: { choice.durationMinutes }, set: { value in var next = choice; next.durationMinutes = value; model.update(next) }), in: 15 ... 240, step: 15)
            Picker("Jam kunjungan", selection: Binding(get: { timingMode }, set: { mode in
                let parts = TripClock.calendar.dateComponents([.hour, .minute], from: model.departure)
                let minute = choice.timing?.minute ?? ((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
                updateTiming(mode, minute: minute)
            })) {
                ForEach(TimingMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
            }
            if let timing = choice.timing {
                MinutePicker(title: timingMode == .required ? "Mulai tepat pukul" : (timingMode == .notBefore ? "Mulai paling cepat" : "Mulai sekitar pukul"),
                             minute: Binding(get: { timing.minute }, set: { updateTiming(timingMode, minute: $0) }),
                             day: model.departure)
            }
            if let manual = choice.override, manual.day == TripClock.day(model.departure) {
                Label("Konfirmasi pribadi untuk " + manual.day, systemImage: "person.crop.circle.badge.checkmark").font(.caption).foregroundStyle(.teal)
            } else if venue.hours == nil || venue.status(.publicAccess) != .supported {
                Label("Jam atau akses belum lengkap", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button("Konfirmasi kunjungan") { editing = true }
                Spacer()
                Button("Hapus", role: .destructive) { model.remove(choice.venueID) }
            }.buttonStyle(.borderless)
        }.padding(.vertical, 5)
            .sheet(isPresented: $editing) { VisitConfirmation(choice: choice, venue: venue, model: model) }
    }

    private enum TimingMode: String, CaseIterable {
        case any = "Bebas"
        case preferred = "Diutamakan"
        case required = "Wajib"
        case notBefore = "Paling cepat"
    }

    private var timingMode: TimingMode {
        switch choice.timing {
        case .preferred: .preferred
        case .required: .required
        case .notBefore: .notBefore
        case nil: .any
        }
    }

    private var isFixed: Bool { timingMode == .required || model.lastVenueID == choice.venueID }

    private func updateTiming(_ mode: TimingMode, minute: Int) {
        var next = choice
        switch mode {
        case .any: next.timing = nil
        case .preferred: next.timing = .preferred(minute)
        case .required: next.timing = .required(minute)
        case .notBefore: next.timing = .notBefore(minute)
        }
        model.update(next)
    }
}

struct VisitConfirmation: View {
    let choice: StopChoice
    let venue: Venue
    let model: PocketModel
    @Environment(\.dismiss) private var dismiss
    @State private var opens: Int
    @State private var closes: Int
    @State private var access = false
    @State private var error: String?
    init(choice: StopChoice, venue: Venue, model: PocketModel) {
        self.choice = choice; self.venue = venue; self.model = model
        _opens = State(initialValue: choice.override?.opens ?? 9 * 60)
        _closes = State(initialValue: choice.override?.closes ?? 17 * 60)
        _access = State(initialValue: choice.override?.publicAccessConfirmed ?? false)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(venue.name).font(.headline)
                    Text("Berlaku hanya untuk " + TripClock.day(model.departure) + ", WIB. Ini keterangan Anda untuk perjalanan ini, bukan fakta terverifikasi yang dibagikan ke pengguna lain.")
                }
                Section("Interval kunjungan yang Anda ketahui") {
                    MinutePicker(title: "Mulai menerima kunjungan", minute: $opens, day: model.departure)
                    MinutePicker(title: "Kunjungan harus selesai", minute: $closes, day: model.departure)
                    Toggle("Saya memastikan boleh berkunjung pada interval tersebut", isOn: $access)
                    Text("Pastikan tiket, reservasi, hari libur, dan syarat masuk. Konfirmasi ini tidak memenuhi syarat kegiatan lain seperti membaca atau kursi roda.").font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.orange) }
                }
                Button("Simpan konfirmasi") {
                    guard access, closes > opens else { error = "Konfirmasikan akses dan pilih akhir setelah awal."; return }
                    var next = choice
                    next.override = .init(day: TripClock.day(model.departure), opens: opens, closes: closes, publicAccessConfirmed: access)
                    model.update(next); dismiss()
                }
                if choice.override != nil { Button("Hapus konfirmasi", role: .destructive) { var next = choice; next.override = nil; model.update(next); dismiss() } }
            }
            .navigationTitle("Konfirmasi kunjungan")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } } }
            .environment(\.timeZone, TripClock.calendar.timeZone)
        }
    }
}

struct MinutePicker: View {
    let title: String
    @Binding var minute: Int
    let day: Date
    var body: some View {
        DatePicker(title, selection: Binding(get: {
            TripClock.calendar.startOfDay(for: day).addingTimeInterval(Double(minute) * 60)
        }, set: { date in
            let c = TripClock.calendar.dateComponents([.hour, .minute], from: date)
            minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }), displayedComponents: .hourAndMinute)
    }
}

struct ItinerarySections: View {
    let plan: Itinerary
    let model: PocketModel
    var body: some View {
        Section("Jadwal · WIB") {
            LabeledContent("Berangkat", value: TripClock.time(plan.departure))
            ForEach(Array(plan.stops.enumerated()), id: \.element.id) { index, stop in
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(index + 1). " + stop.name).font(.headline)
                    Text(TripClock.time(stop.visitStart) + " – " + TripClock.time(stop.visitEnd)).monospacedDigit()
                    Text("Tiba \(TripClock.time(stop.arrival)) · berkendara \(Int(ceil(stop.driveSeconds / 60))) menit · menunggu \(Int(ceil(stop.visitStart.timeIntervalSince(stop.arrival) / 60))) menit").font(.caption).foregroundStyle(.secondary)
                    Text(stop.evidence).font(.caption)
                    Text(stop.weather).font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 5)
            }
            if plan.returnToOrigin { LabeledContent("Perjalanan kembali", value: "\(Int(ceil(plan.returnSeconds / 60))) menit") }
            LabeledContent(plan.returnToOrigin ? "Tiba kembali" : "Selesai", value: TripClock.time(plan.finish))
        }
        Section("Peta perjalanan") {
            ItineraryMap(plan: plan, routes: model.routes)
            Button("Muat garis rute Apple", systemImage: "map") { model.drawRoutes() }.disabled(model.isDrawing)
            if model.isDrawing { ProgressView("Memuat geometri…") }
            if !model.routeNotice.isEmpty { Text(model.routeNotice).font(.caption) }
        }
        if !plan.omitted.isEmpty { Section("Tujuan opsional yang belum terjadwal") { ForEach(plan.omitted, id: \.self) { Text($0) } } }
        Section("Catatan rencana") {
            ForEach(plan.warnings, id: \.self) { Text($0).font(.caption) }
            Text("\(plan.etaRequests) permintaan ETA · dihitung " + plan.generatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
            if let attribution = model.weatherAttribution { WeatherCredit(attribution: attribution) }
        }
    }
}

struct WeatherCredit: View {
    let attribution: WeatherAttribution
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Link(destination: attribution.legalPageURL) {
            VStack(alignment: .leading, spacing: 5) {
                AsyncImage(url: colorScheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: { Text(attribution.serviceName) }
                    .frame(width: 115, height: 24)
                Text(attribution.legalAttributionText).font(.caption2)
            }
        }
    }
}

struct ItineraryMap: View {
    let plan: Itinerary
    let routes: [MKPolyline]
    var body: some View {
        Map {
            Marker("Titik awal", systemImage: "location.fill", coordinate: .init(latitude: plan.origin.latitude, longitude: plan.origin.longitude)).tint(.blue)
            ForEach(Array(plan.stops.enumerated()), id: \.element.id) { index, stop in
                Marker("\(index + 1). " + stop.name, coordinate: .init(latitude: stop.coordinate.latitude, longitude: stop.coordinate.longitude)).tint(.teal)
            }
            ForEach(Array(routes.enumerated()), id: \.offset) { index, line in
                MapPolyline(line).stroke(index.isMultiple(of: 2) ? Color.teal : Color.indigo, lineWidth: 5)
            }
        }.frame(height: 290).clipShape(.rect(cornerRadius: 16)).mapControls { MapCompass(); MapScaleView() }
    }
}
