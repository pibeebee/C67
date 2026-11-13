import SwiftUI

struct NativeTripOpeningSection: View {
    @Binding var opening: NativeTripOpening?
    let departure: Date
    let timeZone: TimeZone

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        return value
    }
    private var tripDate: String { NativeTripOpening.dateKey(departure, timeZone: timeZone) }

    private func setBound(_ minutes: Int?, opens: Bool) {
        var value = opening ?? .init()
        if opens { value.opensMinute = minutes } else { value.closesMinute = minutes }
        value.serviceDate = tripDate
        value.timeZoneID = timeZone.identifier
        opening = value.opensMinute == nil && value.closesMinute == nil ? nil : value
    }

    private func known(_ opens: Bool) -> Binding<Bool> {
        Binding(
            get: { opens ? opening?.opensMinute != nil : opening?.closesMinute != nil },
            set: { enabled in
                // These are editable form values, used only after the user enables the bound.
                let initial = opens ? min(600, (opening?.closesMinute ?? 1440) - 1)
                    : min(1440, (opening?.opensMinute ?? 600) + 60)
                setBound(enabled ? initial : nil, opens: opens)
            })
    }

    private func clock(_ opens: Bool) -> Binding<Date> {
        Binding(
            get: {
                let minutes = (opens ? opening?.opensMinute : opening?.closesMinute) ?? 600
                return calendar.startOfDay(for: departure).addingTimeInterval(Double(minutes) * 60)
            },
            set: { value in
                let parts = calendar.dateComponents([.hour, .minute], from: value)
                setBound((parts.hour ?? 0) * 60 + (parts.minute ?? 0), opens: opens)
            })
    }

    private var midnightClosing: Binding<Bool> {
        Binding(
            get: { opening?.closesMinute == 1440 },
            set: { setBound($0 ? 1440 : 23 * 60, opens: false) })
    }
    private var sourceNote: Binding<String> {
        Binding(
            get: { opening?.sourceNote ?? "" },
            set: { opening?.sourceNote = $0.isEmpty ? nil : $0 })
    }

    var body: some View {
        Section {
            Text("Tanggal trip: \(tripDate) · \(timeZone.identifier)")
                .font(.footnote).foregroundStyle(.secondary)
            Toggle("Jam buka diketahui", isOn: known(true))
            if opening?.opensMinute != nil {
                DatePicker("Buka", selection: clock(true), displayedComponents: .hourAndMinute)
            }
            Toggle("Jam tutup diketahui", isOn: known(false))
            if opening?.closesMinute != nil {
                Toggle("Tutup pukul 24.00", isOn: midnightClosing)
                if opening?.closesMinute != 1440 {
                    DatePicker("Tutup", selection: clock(false), displayedComponents: .hourAndMinute)
                }
            }
            if let opening {
                Text(opening.summary).font(.footnote)
                TextField("Catatan sumber (opsional)", text: sourceNote)
                    .textInputAutocapitalization(.sentences)
                if !opening.matchesTrip(departure, timeZone: timeZone) || opening.serviceDate == nil
                    || opening.timeZoneID == nil
                {
                    Text(
                        "Data tersimpan untuk \(opening.serviceDate ?? "tanggal belum dicatat") · \(opening.timeZoneID ?? "zona belum dicatat"). Periksa kesesuaiannya dengan tanggal trip."
                    )
                    .font(.footnote).foregroundStyle(.orange)
                    Button("Konfirmasi jam untuk tanggal trip ini") {
                        self.opening?.serviceDate = tripDate
                        self.opening?.timeZoneID = timeZone.identifier
                    }
                }
                if let issue = opening.issue(for: departure, timeZone: timeZone) {
                    Text(issue).font(.footnote).foregroundStyle(.red)
                }
            } else {
                Text("Belum diisi. Ketersediaan tempat saat tiba belum dapat dipastikan.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Jam operasional")
        } footer: {
            Text(
                "Isi manual sesuai tanggal trip. Boleh hanya jam buka atau jam tutup; batas yang belum diketahui tetap ditandai. Satu rentang dalam satu hari; periksa hari libur dan batas masuk secara terpisah."
            )
        }
        .environment(\.timeZone, timeZone)
    }
}

struct NativeTripListInputSheet: View {
    let remaining: Int
    let onAdd: (String) throws -> Void
    @State private var text = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var names: [String] { NativeTripListInput.names(from: text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text).frame(minHeight: 180)
                        .accessibilityLabel("Daftar tempat, satu tempat per baris")
                    Text(
                        "Satu tempat per baris. Nomor seperti 1. atau tanda bullet boleh disertakan. Nama, alamat dan tanda koma tetap dipertahankan."
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("Tulis atau tempel daftar Anda")
                }
                Section("Pratinjau · \(names.count) tempat") {
                    ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                        Text("\(index + 1). \(name)")
                    }
                    if names.count > remaining {
                        Text("Tersisa \(remaining) tempat. Kurangi daftar sebelum menambahkannya.")
                            .foregroundStyle(.red)
                    }
                    Text(
                        "Daftar ditambahkan ke tujuan yang sudah ada, maksimal 20. Nama yang berulang tetap menjadi kunjungan terpisah. Tanggal, jam dan titik awal/akhir diatur di form utama."
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Daftar tempat")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tambahkan") {
                        do {
                            try onAdd(text)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(names.isEmpty || names.count > remaining)
                }
            }
        }
    }
}

struct NativeTripTimeZonePicker: View {
    @Binding var selection: String
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    private static let identifiers = TimeZone.knownTimeZoneIdentifiers.sorted()
    private var identifiers: [String] {
        let all = Array(Set(Self.identifiers + [selection])).sorted()
        return query.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            Section {
                Text(
                    "Pilih zona waktu lokasi trip. Saat zona diganti, tanggal dan jam yang Anda isi dipertahankan sebagai waktu setempat."
                )
                .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(identifiers, id: \.self) { identifier in
                Button {
                    selection = identifier
                    dismiss()
                } label: {
                    HStack {
                        Text(identifier)
                        Spacer()
                        if identifier == selection { Image(systemName: "checkmark") }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Kota atau zona, misalnya Jakarta")
        .navigationTitle("Zona waktu trip")
        .navigationBarTitleDisplayMode(.inline)
    }
}
