import SwiftUI
import TripIntegration

struct JourneyHome: View {
    @Bindable var model: JourneyModel
    @State private var showSettings = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if model.phase != .home { modeLabel }
                    if model.phase.number > 0 { stepHeader }
                    switch model.phase {
                    case .home: homeContent
                    case .setup: JourneySetup(model: model)
                    case .preferences: JourneyPreferences(model: model)
                    case .places: JourneyPlaces(model: model)
                    case .review: JourneyReview(model: model)
                    case .result:
                        if let plan = model.plan { JourneyItinerary(model: model, plan: plan) }
                    }
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red).textSelection(.enabled).accessibilityIdentifier("journey-error")
                    }
                    if let warning = model.persistenceWarning, !warning.isEmpty {
                        Text(warning).font(.footnote).foregroundStyle(.orange)
                    }
                }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }.id(model.phase.rawValue).background(JourneyTheme.canvas)
                .navigationTitle(model.phase == .home ? "C67 Journey" : model.phase.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if model.phase != .home {
                            Button(action: model.back) { Image(systemName: "chevron.left") }
                                .accessibilityLabel("Kembali").accessibilityIdentifier("journey-back")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                            .accessibilityLabel("Mode dan sumber")
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) { footer.padding(.horizontal, 20).padding(.vertical, 12).background(.bar) }
                .overlay { if model.busy { busyOverlay } }
                .disabled(model.saving || model.switching)
                .sheet(isPresented: $showSettings) { JourneySettings(model: model) }
                .tint(JourneyTheme.blue)
                .environment(\.timeZone, TripClock.calendar.timeZone)
        }
    }
    private var modeLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: model.mode == .demo ? "play.circle" : "antenna.radiowaves.left.and.right")
            Text(model.mode == .demo ? "DEMO · data sintetis" : "LIVE · provider asli")
                .accessibilityIdentifier("journey-mode")
        }.font(.caption.weight(.semibold)).foregroundStyle(model.mode == .demo ? Color.secondary : JourneyTheme.blue)
    }
    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Langkah \(model.phase.number) dari 4").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(1 ... 4, id: \.self) { step in
                    Capsule().fill(step <= model.phase.number ? JourneyTheme.blue : Color.secondary.opacity(0.18)).frame(height: 4)
                }
            }.accessibilityLabel("Langkah \(model.phase.number) dari empat")
        }
    }
    private var homeContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            modeLabel
            VStack(alignment: .leading, spacing: 10) {
                Text("Seharian di\n\(model.request.useCityCatalog == true ? "Jakarta" : "Blok M")").font(JourneyTheme.font(40, relativeTo: .largeTitle).weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text("Pilih minatmu. Susun tempat, waktu, dan perjalanan dalam satu itinerary.")
                    .font(JourneyTheme.font(19, relativeTo: .title3)).foregroundStyle(.secondary)
            }
            if model.hasDraft {
                Button(action: model.resume) {
                    Label("Lanjutkan draf", systemImage: "arrow.uturn.forward").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12).contentShape(Rectangle())
                }.accessibilityIdentifier("resume-draft")
            }
            JourneyMap(plan: nil, geometry: model.geometry, roads: model.roadRoutes).frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 24))
                .accessibilityLabel("Peta awal Jakarta")
            JourneyPanel {
                JourneyInfo(symbol: "arrow.triangle.swap", title: "Pulang-pergi", value: model.request.originQuery)
                Divider()
                JourneyInfo(symbol: "bus", title: "Pilihan perjalanan", value: "TransJakarta + jalan kaki atau mobil")
                Text(model.mode == .demo ? "Demo memakai tanggal dan provider contoh yang berlabel sintetis. Kamu tetap bisa mencoba seluruh alur." : "Lokasi dan jalan kaki memakai MapKit. Bus memakai estimasi jadwal GTFS.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let saved = model.session.accepted {
                JourneyPanel {
                    Label("Itinerary tersimpan", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.subheadline)
                    Text("\(saved.stops.count) tempat di \(saved.request.useCityCatalog == true ? "Jakarta" : "Blok M")").font(JourneyTheme.font(23, relativeTo: .title2).weight(.semibold))
                    Text(saved.request.effectiveTransport.label).foregroundStyle(.secondary)
                    Text(saved.stops.map(\.name).joined(separator: " → ")).font(.footnote)
                    Button("Buka itinerary", action: model.openSaved).accessibilityIdentifier("open-saved")
                }
            }
        }
    }
    @ViewBuilder private var footer: some View {
        switch model.phase {
        case .home:
            JourneyPrimaryButton(title: "Buat itinerary", id: "new-trip", action: model.newTrip)
        case .setup:
            JourneyPrimaryButton(title: "Lanjut pilih minat", id: "next-preferences", action: model.advanceToPreferences)
        case .preferences:
            JourneyPrimaryButton(title: "Temukan tempat", id: "find-places", action: model.recommend)
        case .places:
            JourneyPrimaryButton(title: "Tinjau \(model.selected.count) tempat", id: "review-places", disabled: model.selected.isEmpty, action: model.verify)
        case .review:
            JourneyPrimaryButton(title: "Susun itinerary", id: "generate-itinerary", symbol: "sparkles", disabled: model.prepared?.ready != true, action: model.generate)
        case .result:
            if model.session.proposal != nil {
                JourneyPrimaryButton(title: "Simpan itinerary", id: "save-itinerary", symbol: "checkmark", disabled: !model.canApply, action: model.accept)
            } else {
                JourneyPrimaryButton(title: "Kembali ke beranda", id: "back-home", action: model.back)
            }
        }
    }
    private var busyOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            JourneyPanel {
                ProgressView().frame(maxWidth: .infinity)
                Text("Menyiapkan perjalananmu").font(JourneyTheme.font(23, relativeTo: .title2).weight(.semibold))
                Text(model.progress).font(.callout).accessibilityIdentifier("journey-progress")
                Text("Kamu bisa membatalkan dan mengubah pilihan.").font(.footnote).foregroundStyle(.secondary)
                Button("Batalkan", role: .cancel, action: model.cancel).frame(minHeight: 44).accessibilityIdentifier("cancel-generation")
            }.padding(28).frame(maxWidth: 520)
        }.accessibilityAddTraits(.isModal)
    }
}
