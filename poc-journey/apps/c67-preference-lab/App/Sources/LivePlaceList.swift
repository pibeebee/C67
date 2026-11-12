import SwiftUI
import PreferenceCore

struct LivePlaceList: View {
    @Bindable var model: LabModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.placeBusy { HStack { ProgressView(); Text("Mencari tempat dan memeriksa informasi…").font(.subheadline) }.accessibilityIdentifier("places-loading") }
            if model.liveResults == nil && !model.placeBusy {
                Text("Jawab pilihan singkat atau langsung lihat tempat dengan minat yang sudah dipilih.").foregroundStyle(.secondary)
                Button("Lihat tempat sekarang") { model.discover() }.buttonStyle(.borderedProminent).accessibilityIdentifier("discover-places")
            }
            if let result = model.liveResults {
                Text("Google Maps").font(.headline).accessibilityIdentifier("google-attribution")
                Text("\(result.places.count) tempat · pilihan sebelumnya tetap tersimpan").font(.subheadline).accessibilityIdentifier("live-count")
                ForEach(result.searches) { group in
                    Text(group.label).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(result.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                if result.places.isEmpty { ContentUnavailableView("Belum ada tempat yang ditemukan", systemImage: "magnifyingglass", description: Text("Coba area lain atau cari ulang. Preferensi Anda tetap dipertahankan.")) }
                LazyVStack(spacing: 16) {
                    ForEach(result.places) { place in LivePlaceCard(place: place, saved: model.state.savedIDs.contains(place.id)) { model.keep(place.id) } }
                }
                if !result.pageTokens.isEmpty {
                    Button("Cari tempat lainnya") { model.discover(more: true) }.disabled(model.placeBusy).buttonStyle(.bordered).accessibilityIdentifier("more-live-places")
                }
                Text(result.notice).font(.caption).foregroundStyle(.secondary)
                Button("Cari ulang") { model.discover() }.disabled(model.placeBusy).accessibilityIdentifier("refresh-live-places")
            }
        }
    }
}
private struct LivePlaceCard: View {
    var place: LivePlace
    var saved: Bool
    var toggleSave: () -> Void
    private func color(_ status: String) -> Color { status == "supported" ? .green : status == "contradicted" || status == "conflict" ? .red : .orange }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(place.name).font(.headline).accessibilityIdentifier("live-place-name")
                Spacer()
                Button(action: toggleSave) { Image(systemName: saved ? "heart.fill" : "heart").padding(6) }
                    .accessibilityLabel(saved ? "Hapus pilihan tempat" : "Simpan tempat").accessibilityIdentifier("save-live-" + place.id)
            }
            Text(place.address).font(.subheadline).foregroundStyle(.secondary)
            Text(place.statusLabel).font(.caption.bold()).foregroundStyle(color(place.status)).accessibilityIdentifier("place-assessment")
            if place.requiredStatus == "unknown" { Text("Syarat wajib belum dapat dipastikan").font(.caption).foregroundStyle(.orange) }
            if place.requiredStatus == "contradicted" { Text("Ada syarat wajib yang bertentangan dengan data").font(.caption).foregroundStyle(.red) }
            DisclosureGroup("Kecocokan dengan pilihan Anda") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(place.checks) { check in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(check.label + (check.must ? " · wajib" : "")).font(.subheadline.bold())
                            Text(check.statusLabel).font(.caption.bold()).foregroundStyle(color(check.status)).accessibilityIdentifier("check-status-" + check.status)
                            Text(check.text).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("Penilaian aplikasi dari informasi yang tersedia, bukan jaminan pengalaman di lapangan.").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }.font(.subheadline).accessibilityIdentifier("place-checks-" + place.id)
            if let s = place.googleMapsURL, let url = URL(string: s), url.scheme == "https" {
                Link("Sumber di Google Maps", destination: url).font(.caption)
            }
            ForEach(Array(place.attributions.enumerated()), id: \.offset) { _, attribution in
                if let name = attribution.provider {
                    if let s = attribution.providerUri, let url = URL(string: s), url.scheme == "https" { Link(name, destination: url).font(.caption) }
                    else { Text(name).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }.padding(18).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}
