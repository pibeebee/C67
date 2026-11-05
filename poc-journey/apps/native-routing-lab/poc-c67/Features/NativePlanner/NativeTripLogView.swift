import SwiftUI
import UniformTypeIdentifiers

struct NativeTripLogDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct NativeTripLogView: View {
    let store: NativeTripLogStore
    @State private var snapshot: NativeTripLogSnapshot?
    @State private var error: String?
    @State private var busy = false
    @State private var exporting = false
    @State private var document: NativeTripLogDocument?

    var body: some View {
        List {
            Section {
                Button("Ekspor log (.txt)") {
                    Task { await prepareExport() }
                }.disabled(busy)
                if busy { ProgressView("Membaca log…") }
                if let snapshot {
                    Text(
                        "\(snapshot.fileCount) berkas · \(ByteCountFormatter.string(fromByteCount: Int64(snapshot.data.count), countStyle: .file))"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    if snapshot.invalidLines > 0 {
                        Text(
                            "\(snapshot.invalidLines) baris tidak terbaca; isi mentah tetap disertakan dalam ekspor."
                        )
                        .font(.caption).foregroundStyle(.orange)
                    }
                }
                if let error = store.storageError ?? error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            } footer: {
                Text(
                    "Log otomatis disimpan di perangkat, termasuk nama tempat, koordinat pilihan, dan error. Maksimal 10 berkas × 2 MB; berkas tertua dirotasi."
                )
            }
            Section("Event terbaru") {
                ForEach(snapshot?.recent.reversed() ?? [].reversed()) { event in
                    NavigationLink {
                        NativeTripLogEventView(event: event)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.event).font(.subheadline.monospaced())
                            Text("\(event.at.formatted(date: .abbreviated, time: .standard)) · \(event.level)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Log").navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        .fileExporter(
            isPresented: $exporting, document: document, contentTypes: [.plainText],
            defaultFilename: "C67-PoC-logs-\(store.sessionID.prefix(8)).txt",
            onCompletion: { result in
                switch result {
                case .success:
                    store.record("log.export_completed", category: "log")
                case .failure(let failure):
                    error = failure.localizedDescription
                    store.record(
                        "log.export_failed", category: "log", level: "error",
                        fields: NativeTripLogStore.errorFields(failure))
                }
            }, onCancellation: { store.record("log.export_cancelled", category: "log") })
    }

    private func reload() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            snapshot = try await store.snapshot()
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func prepareExport() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        store.record("log.export_requested", category: "log")
        do {
            let value = try await store.snapshot()
            snapshot = value
            document = NativeTripLogDocument(data: value.data)
            error = nil
            exporting = true
        } catch { self.error = error.localizedDescription }
    }
}

private struct NativeTripLogEventView: View {
    let event: NativeTripLogEvent
    var body: some View {
        List {
            Section {
                LabeledContent("Event", value: event.event)
                LabeledContent("Waktu", value: event.at.ISO8601Format())
                LabeledContent("Level", value: event.level)
                LabeledContent("Kategori", value: event.category)
                LabeledContent("Sesi", value: event.sessionID)
                LabeledContent("Urutan", value: String(event.sequence))
                if let operationID = event.operationID { LabeledContent("Operasi", value: operationID) }
            }
            ForEach(event.fields.keys.sorted(), id: \.self) { key in
                Section(key) { Text(event.fields[key] ?? "").font(.caption.monospaced()) }
            }
        }
        .textSelection(.enabled)
        .navigationTitle("Detail log").navigationBarTitleDisplayMode(.inline)
    }
}
