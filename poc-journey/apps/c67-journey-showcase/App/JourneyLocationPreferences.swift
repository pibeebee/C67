import SwiftUI
import TripIntegration

struct JourneyOriginPicker: View {
    @Bindable var model: JourneyModel
    @FocusState private var editingOrigin: Bool
    var body: some View {
        JourneyPanel {
            Text("Mulai & kembali ke mana?").font(.headline)
            HStack {
                TextField("Nama tempat atau alamat di Jakarta", text: Binding(get: { model.request.originQuery }, set: model.setOriginQuery))
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("origin-query")
                    .focused($editingOrigin).submitLabel(.search)
                    .onSubmit { editingOrigin = false; model.searchOrigin() }
                if !model.request.originQuery.isEmpty {
                    Button { model.setOriginQuery(""); editingOrigin = true } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                        .accessibilityLabel("Hapus pencarian titik awal").accessibilityIdentifier("clear-origin")
                }
            }
            Button("Cari titik awal", systemImage: "magnifyingglass") { editingOrigin = false; model.searchOrigin() }
                .frame(minHeight: 44).disabled(model.originSearching).accessibilityIdentifier("search-origin")
            if model.originSearching { ProgressView("Mencari lokasi…") }
            if let pin = model.request.originPin {
                Label(pin.name, systemImage: "checkmark.circle.fill").accessibilityIdentifier("chosen-origin")
                Text(pin.address).font(.footnote).foregroundStyle(.secondary)
            }
            if let message = model.originSearchMessage { Text(message).font(.footnote).foregroundStyle(.secondary) }
            ForEach(model.originResults) { pin in
                Button { model.chooseOrigin(pin) } label: {
                    VStack(alignment: .leading) { Text(pin.name); Text(pin.address).font(.caption).foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.accessibilityIdentifier("origin-result-" + pin.id)
            }
            if model.mode == .demo {
                Text("Titik contoh Demo · koordinat sintetis. Gunakan Live untuk mencari tempat atau alamat lain.").font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(BlokMReplay.origins) { pin in
                            Button(pin.name) { model.chooseOrigin(pin) }
                                .buttonStyle(.bordered).accessibilityIdentifier("demo-origin-" + pin.name)
                        }
                    }
                }
            } else {
                Text("Pilih hasil MapKit untuk mengunci koordinat titik awal. Cakupan POC: Jakarta.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct JourneyDestinationPreferences: View {
    @Bindable var model: JourneyModel
    @State private var spotQuery = ""
    private var spots: [String] {
        model.catalog.quality.candidates.filter {
            model.request.includesArea(candidateID: $0.id) && (spotQuery.isEmpty ||
                ($0.name + " " + $0.address + " " + $0.scope).localizedCaseInsensitiveContains(spotQuery))
        }.map(\.id)
    }
    var body: some View {
        JourneyPanel {
            areaPicker
            Divider()
            requiredSpots
            spotSearch
        }
    }
    private var areaPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Area yang ingin dijelajahi").font(.headline)
            Text("Tanpa pilihan berarti semua area dalam katalog. Spot di luar area tidak akan diusulkan.").font(.footnote).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))]) {
                ForEach(model.availableAreas) { area in
                    JourneyAreaChoice(area: area, chosen: model.request.targetAreas?.contains(area) == true) {
                        model.toggleArea(area)
                    }
                }
            }
            if !(model.request.targetAreas ?? []).isEmpty {
                Button("Semua area") { model.edit { $0.targetAreas = nil } }.accessibilityIdentifier("all-areas")
            }
        }
    }
    private var requiredSpots: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ada spot yang wajib didatangi?").font(.headline)
            Text("Pilih hingga enam spot dari katalog bersumber. Syarat minat, jam layanan, dan rute tetap diperiksa; spot wajib tidak diganti diam-diam.").font(.footnote).foregroundStyle(.secondary)
            ForEach(model.request.requiredCandidateIDs, id: \.self) { id in
                Button { model.toggleDesiredSpot(id) } label: {
                    Label(model.catalog.candidate(id)?.name ?? id, systemImage: "pin.slash")
                }.accessibilityLabel("Lepas spot wajib " + (model.catalog.candidate(id)?.name ?? id))
            }
        }
    }
    private var spotSearch: some View {
        DisclosureGroup("Cari & pilih spot dalam katalog") {
            TextField("Nama spot atau alamat", text: $spotQuery).textFieldStyle(.roundedBorder).accessibilityIdentifier("spot-query")
            if spots.isEmpty { Text("Belum ada spot bersumber untuk pencarian ini. Coba area atau nama lain.").font(.footnote) }
            ForEach(spots, id: \.self) { id in
                spotChoice(id)
            }
        }
    }
    @ViewBuilder private func spotChoice(_ id: String) -> some View {
        if let candidate = model.catalog.candidate(id) {
            JourneySpotChoice(id: id, name: candidate.name, scope: candidate.scope,
                              required: model.request.requiredCandidateIDs.contains(id)) {
                model.toggleDesiredSpot(id)
            }
        }
    }
}

private struct JourneyAreaChoice: View {
    let area: TripArea
    let chosen: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(area.label, systemImage: chosen ? "checkmark.circle.fill" : "circle")
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }.accessibilityIdentifier("area-" + area.rawValue)
            .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

private struct JourneySpotChoice: View {
    let id: String
    let name: String
    let scope: String
    let required: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading) {
                    Text(name)
                    Text(scope).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: required ? "pin.fill" : "plus.circle")
            }.frame(minHeight: 44)
        }.accessibilityIdentifier("desired-spot-" + id)
    }
}
