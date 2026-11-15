import SwiftUI
import PreferenceCore

struct CatalogPlaceList: View {
    @Bindable var model: LabModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.placeBusy {
                HStack { ProgressView(); Text("Mencocokkan kegiatan dengan informasi tempat…").font(.subheadline) }
            }
            if model.catalogResults == nil && !model.placeBusy {
                Button("Lihat tempat sekarang") { model.discover() }.buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("discover-catalog")
            }
            if let result = model.catalogResults {
                Text(result.scope).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("catalog-scope")
                Text("\(result.places.count) pilihan dari \(result.totalPlaces) tempat").font(.subheadline)
                    .accessibilityIdentifier("catalog-count")
                ForEach(result.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                if result.excludedCount > 0 {
                    Text("\(result.excludedCount) tempat disisihkan karena bertentangan dengan syarat wajib.").font(.caption)
                }
                if result.places.isEmpty {
                    ContentUnavailableView("Belum ada tempat yang sesuai", systemImage: "books.vertical",
                                           description: Text("Tinjau pilihan atau gunakan pencarian Google untuk menjelajah di luar katalog."))
                }
                LazyVStack(spacing: 16) {
                    ForEach(result.places) { place in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                Text(place.name).font(.headline).accessibilityIdentifier("catalog-place-name")
                                Spacer()
                                Button { model.keep(place.id) } label: {
                                    Image(systemName: model.state.savedIDs.contains(place.id) ? "heart.fill" : "heart").padding(6)
                                }.accessibilityLabel("Simpan atau hapus pilihan tempat").accessibilityIdentifier("save-catalog-" + place.id)
                            }
                            Text(place.categoryLabel).font(.caption.bold())
                            Text(place.address).font(.subheadline).foregroundStyle(.secondary)
                            Text(place.statusLabel).font(.caption).foregroundStyle(place.status == "supported" ? .green : .orange)
                                .accessibilityIdentifier("catalog-status-" + place.status)
                            DisclosureGroup("Kegiatan dan bukti") {
                                VStack(alignment: .leading, spacing: 14) {
                                    ForEach(place.checks) { check in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(check.label + (check.must ? " · wajib" : "")).font(.subheadline.bold())
                                            Text(check.status == "supported" ? "Didukung bukti" : check.status == "contradicted" ? "Bertentangan" : "Belum diketahui")
                                                .font(.caption.bold()).foregroundStyle(check.status == "supported" ? .green : .orange)
                                                .accessibilityIdentifier("catalog-check-" + check.id + "-" + check.status)
                                            Text(check.explanation).font(.caption).foregroundStyle(.secondary)
                                            ForEach(check.evidence, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    if let hours = place.regularHours {
                                        Text("Jam rutin dari sumber · " + hours).font(.caption)
                                        Text("Jam rutin belum memastikan pengecualian tanggal kunjungan.").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text("Sumber diperiksa " + place.checkedDateLabel).font(.caption).foregroundStyle(.secondary)
                                    if let url = URL(string: place.sourceURL), url.scheme == "https" {
                                        Link("Lihat sumber tempat", destination: url).font(.caption)
                                    }
                                }.padding(.top, 8)
                            }.font(.subheadline).accessibilityIdentifier("catalog-evidence-" + place.id)
                        }.padding(18).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    }
                }
                Text(result.notice).font(.caption).foregroundStyle(.secondary)
                Link("© OpenStreetMap contributors · ODbL 1.0", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                    .font(.caption).accessibilityIdentifier("osm-attribution")
                Button("Cocokkan ulang") { model.discover() }.disabled(model.placeBusy)
                    .accessibilityIdentifier("refresh-catalog")
            }
        }
    }
}
