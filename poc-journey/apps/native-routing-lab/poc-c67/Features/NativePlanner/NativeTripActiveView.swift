import SwiftUI

struct NativeTripActiveView: View {
    @State private var controller: NativeTripActiveController
    @State private var confirmsStart = false
    @State private var confirmsAnchor = false
    @State private var confirmsExtend = false
    @State private var confirmsFinish = false
    @State private var skipID: String?
    @State private var editingDeadline = false
    @State private var editingLeave = false
    @State private var dateInput = Date()
    @Environment(\.scenePhase) private var scenePhase
    let onClose: () -> Void

    init(controller: NativeTripActiveController, onClose: @escaping () -> Void) {
        _controller = State(initialValue: controller)
        self.onClose = onClose
    }

    var body: some View {
        List {
            if let original = controller.original {
                if let active = controller.active {
                    statusSection(active, original: original)
                    if active.isActive {
                        controlsSection(active, original: original)
                        proposalSection(active, original: original)
                    }
                    visitsSection(active, original: original)
                    if !active.warnings(original: original).isEmpty {
                        Section("Catatan fakta aktual") {
                            ForEach(active.warnings(original: original), id: \.self) { Text($0).font(.footnote) }
                        }
                    }
                } else {
                    Section("Mulai dari itinerary pilihan") {
                        Text(original.draft.stops.map(\.point.title).joined(separator: " → "))
                        Text(original.draft.deadlineSummary).font(.footnote)
                        if original.simulationKind == "active" {
                            Text("SIMULASI LOKAL · jam, lokasi dan ETA sintetis. Tidak memanggil provider.").font(
                                .footnote)
                        } else {
                            Text(
                                "Waktu mulai aktual dicatat saat Anda menekan Mulai. Pilih satu moda jalan kaki atau taksi untuk PoC aktif."
                            ).font(.footnote)
                        }
                        rowButton("Mulai trip") { confirmsStart = true }
                    }
                }
            }
            if controller.isBusy {
                Section {
                    ProgressView(controller.phase)
                    rowButton("Batalkan perhitungan") { controller.cancel() }
                }
            } else if !controller.phase.isEmpty {
                Section { Text(controller.phase).font(.footnote) }
            }
            if let error = controller.error {
                Section("Periksa tindakan") {
                    Text(error).foregroundStyle(.red)
                    if controller.canRetry { rowButton("Coba simpan tindakan lagi") { controller.retry() } }
                }
            }
            if let notice = controller.notice { Section { Text(notice).font(.footnote) } }
            Section {
                DisclosureGroup("Diagnostik lokal") {
                    rowButton("Gagalkan satu simpan berikutnya") { controller.failNextSave() }
                    Text(
                        "Kunjungan dicatat manual; tidak membuktikan kehadiran GPS. Di tengah perjalanan, pilih perhitungan hanya jika masih berada di lokasi yang dikonfirmasi."
                    ).font(.footnote)
                }
            }
        }
        .navigationTitle("Trip aktif")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ShareLink(item: controller.textReport) {
                Label("Bagikan ringkasan", systemImage: "square.and.arrow.up")
            }
        }
        .confirmationDialog(
            "Mulai trip dari rencana tersimpan?", isPresented: $confirmsStart, titleVisibility: .visible
        ) {
            Button("Mulai dan simpan waktu aktual") { controller.start() }
        }
        .confirmationDialog(
            "Hitung dari \(controller.anchorTitle)? Konfirmasi Anda masih di lokasi ini. Perhitungan dari tengah perjalanan belum didukung.",
            isPresented: $confirmsAnchor, titleVisibility: .visible
        ) {
            Button("Saya di lokasi ini · hitung ulang") {
                controller.requestReplan(anchorConfirmed: true)
            }
        }
        .confirmationDialog(extendSummary, isPresented: $confirmsExtend, titleVisibility: .visible) {
            Button("Simpan tambahan 30 menit") { controller.perform(.extend(30)) }
        }
        .confirmationDialog(
            "Lewati tujuan ini? Tujuan akan dicatat sebagai dilewati, bukan selesai dikunjungi.",
            isPresented: Binding(get: { skipID != nil }, set: { if !$0 { skipID = nil } }),
            titleVisibility: .visible
        ) {
            if let skipID {
                Button("Lewati tujuan", role: .destructive) {
                    controller.perform(.skip(skipID))
                    self.skipID = nil
                }
            }
        }
        .confirmationDialog(
            "Konfirmasi sudah tiba di titik akhir? Ini laporan manual Anda dan akan menyelesaikan trip.",
            isPresented: $confirmsFinish, titleVisibility: .visible
        ) {
            Button("Sudah tiba · selesaikan trip") { controller.perform(.finish) }
        }
        .sheet(isPresented: $editingDeadline) {
            dateSheet(title: "Batas tiba di titik akhir") {
                controller.perform(.deadline(dateInput))
                editingDeadline = false
            }
        }
        .sheet(isPresented: $editingLeave) {
            dateSheet(title: "Waktu keluar dari tempat ini") {
                controller.perform(.setLeave(dateInput))
                editingLeave = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { controller.cancel(reason: "background") }
        }
        .onDisappear {
            controller.cancel(reason: "leave_screen")
            onClose()
        }
    }

    private var extendSummary: String {
        guard let original = controller.original, let leave = controller.active?.current?.plannedLeaveAt
        else { return "Tambah 30 menit?" }
        return
            "Waktu keluar baru: \(original.draft.clock(max(controller.now, leave).addingTimeInterval(1800))). Perubahan disimpan sebelum hitung ulang."
    }

    @ViewBuilder private func statusSection(
        _ active: NativeTripActiveTrip, original: NativeTripReport
    ) -> some View {
        Section(active.isActive ? "Perjalanan berlangsung" : "Perjalanan selesai") {
            if active.simulationNow != nil {
                Text("SIMULASI LOKAL · tanpa provider live").font(.headline)
            }
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text("Sekarang: \(original.draft.clock(controller.now))")
            }
            Text("Batas tiba: \(original.draft.clock(active.finishBy))")
            if active.isActive {
                Text(
                    active.needsReplan
                        ? "Perubahan tersimpan · sisa rencana perlu dihitung ulang"
                        : "Usulan terakhir sudah diterapkan"
                ).font(.footnote)
            } else {
                Text("Perjalanan selesai berdasarkan konfirmasi Anda. Riwayat aktual tersimpan.").font(
                    .footnote)
            }
            if let finish = active.acceptedRemaining?.fastest?.finish {
                Text("Estimasi selesai pada rencana terakhir: \(original.draft.clock(finish))").font(
                    .footnote)
            }
            if let finish = active.finishedAt { Text("Tiba aktual: \(original.draft.clock(finish))") }
            if active.simulationNow != nil, active.isActive {
                HStack {
                    rowButton("Waktu +10 menit") { controller.perform(.advanceSimulation(10)) }
                    rowButton("Waktu +30 menit") { controller.perform(.advanceSimulation(30)) }
                }.buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder private func controlsSection(
        _ active: NativeTripActiveTrip, original: NativeTripReport
    ) -> some View {
        Section("Tindakan perjalanan") {
            if let current = active.current {
                let name =
                    original.draft.stops.first { $0.id == current.stopID }?.point.title ?? current.stopID
                Text("Sekarang di: \(name)").font(.headline)
                if current.status == .arrived {
                    rowButton("Mulai kunjungan") { controller.perform(.beginVisit(current.stopID)) }
                    Text("Jika tempat belum buka, tunggu lalu catat mulai saat benar-benar mengunjunginya.")
                        .font(.footnote)
                } else {
                    if let leave = current.plannedLeaveAt {
                        Text("Rencana keluar: \(original.draft.clock(leave))")
                    }
                    rowButton("Tambah 30 menit di sini") { confirmsExtend = true }
                    rowButton("Atur waktu keluar") {
                        dateInput = max(controller.now, current.plannedLeaveAt ?? controller.now)
                        editingLeave = true
                    }
                    rowButton("Selesai kunjungan dan berangkat") {
                        controller.perform(.depart(current.stopID))
                    }
                }
            } else if let nextID = active.pendingIDs.first {
                let title = original.draft.stops.first { $0.id == nextID }?.point.title ?? nextID
                Text("Tujuan berikutnya: \(title)")
                rowButton("Saya sudah tiba di tujuan berikutnya") { controller.perform(.arrive(nextID)) }
            } else {
                rowButton("Konfirmasi tiba di titik akhir") { confirmsFinish = true }
            }
            rowButton("Ubah batas tiba") {
                dateInput = active.finishBy
                editingDeadline = true
            }
            rowButton("Hitung ulang sisa trip") { confirmsAnchor = true }
        }
    }

    @ViewBuilder private func proposalSection(
        _ active: NativeTripActiveTrip, original: NativeTripReport
    ) -> some View {
        if let proposal = active.proposal {
            Section("Tinjau perubahan") {
                Text(
                    "Rencana awal selesai: \(original.fastest?.finish.map(original.draft.clock) ?? "belum diketahui")"
                )
                Text(
                    "Urutan sekarang, waktu diperbarui: \(proposal.baseline?.finish.map(original.draft.clock) ?? "belum lengkap")"
                )
                Text(
                    "Usulan selesai: \(proposal.report.fastest?.finish.map(original.draft.clock) ?? "belum lengkap")"
                ).font(.headline)
                if let candidate = proposal.report.fastest {
                    let names = candidate.order.map { id in
                        original.draft.stops.first { $0.id == id }?.point.title ?? id
                    }
                    Text(names.isEmpty ? "Langsung ke titik akhir" : names.joined(separator: " → "))
                    Text(
                        "Perjalanan \(candidate.travelMinutes, specifier: "%.1f") menit · menunggu \(candidate.waitingMinutes, specifier: "%.1f") menit · singgah sisa \(candidate.dwellMinutes) menit"
                    ).font(.footnote)
                    if let remaining = proposal.totalRemainingMinutes {
                        Text("Total sisa dari waktu perhitungan: \(remaining, specifier: "%.1f") menit").font(
                            .footnote)
                    }
                    if let baseline = proposal.baseline, baseline.feasible, candidate.feasible {
                        Text(
                            "Perubahan terhadap urutan yang sama-sama dihitung ulang: \(candidate.elapsedMinutes - baseline.elapsedMinutes, specifier: "%.1f") menit"
                        ).font(.footnote)
                    }
                    ForEach(candidate.conflicts, id: \.self) { Text($0).foregroundStyle(.red) }
                    ForEach(Array(Set(candidate.uncertainties)).sorted(), id: \.self) {
                        Text($0).font(.footnote)
                    }
                }
                if proposal.report.fastest == nil {
                    ForEach(Array(Set(proposal.report.candidates.flatMap(\.conflicts))).sorted(), id: \.self)
                        {
                            Text($0).foregroundStyle(.red)
                        }
                }
                ForEach(proposal.projection.currentConflicts, id: \.self) { Text($0).foregroundStyle(.red) }
                if !proposal.canApply {
                    Text(
                        "Usulan belum dapat diterapkan. Anda dapat mengubah waktu keluar, batas tiba, atau melewati tujuan sebelum menghitung ulang."
                    ).font(.footnote)
                } else if !controller.canApply {
                    Text(
                        "Usulan sudah kedaluwarsa atau berasal dari sesi sebelumnya. Hitung ulang sebelum menerapkan."
                    ).font(.footnote)
                }
                rowButton("Terapkan perubahan") { controller.perform(.apply(proposal.id)) }.disabled(
                    !controller.canApply || controller.isBusy)
                rowButton("Abaikan usulan") { controller.perform(.reject(proposal.id)) }
            }
        }
    }

    @ViewBuilder private func visitsSection(
        _ active: NativeTripActiveTrip, original: NativeTripReport
    ) -> some View {
        Section("Kunjungan dan fakta aktual") {
            ForEach(active.visits, id: \.stopID) { visit in
                VStack(alignment: .leading, spacing: 5) {
                    Text(original.draft.stops.first { $0.id == visit.stopID }?.point.title ?? visit.stopID)
                        .font(.headline)
                    Text(visit.status.title)
                    if let at = visit.arrivedAt {
                        Text("Tiba aktual: \(original.draft.clock(at))").font(.caption)
                    }
                    if let at = visit.startedAt {
                        Text("Mulai aktual: \(original.draft.clock(at))").font(.caption)
                    }
                    if let at = visit.departedAt {
                        Text("Selesai aktual: \(original.draft.clock(at))").font(.caption)
                    }
                    if visit.status == .pending, active.isActive {
                        rowButton("Lewati \(visit.stopID)") { skipID = visit.stopID }
                    }
                }
            }
        }
    }

    private func rowButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
    }

    private func dateSheet(title: String, save: @escaping () -> Void) -> some View {
        NavigationStack {
            Form {
                DatePicker(title, selection: $dateInput).environment(
                    \.timeZone, controller.original?.draft.timeZone ?? .current)
                rowButton("Simpan perubahan", action: save)
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Batal") {
                    editingDeadline = false
                    editingLeave = false
                }
            }
        }
    }
}
