import Foundation
import Observation
import SwiftData

@Model final class SavedRun {
    var payload: Data
    init(payload: Data) { self.payload = payload }
}

@MainActor @Observable final class SessionStore {
    private(set) var state: RunState
    private let context: ModelContext
    private var document: SavedRun
    var failNextSave = false

    static func container(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        return try ModelContainer(for: SavedRun.self, configurations: config)
    }
    init(container: ModelContainer, initial: RunState = RunState()) throws {
        context = ModelContext(container); context.autosaveEnabled = false
        let docs = try context.fetch(FetchDescriptor<SavedRun>())
        guard docs.count <= 1 else { throw POCError.message("Penyimpanan berisi lebih dari satu run; data tidak direset otomatis.") }
        if let existing = docs.first {
            document = existing
            state = try JSONDecoder().decode(RunState.self, from: existing.payload)
        } else {
            state = initial; document = SavedRun(payload: try JSONEncoder().encode(initial))
            context.insert(document); try context.save()
        }
        guard !state.sessions.isEmpty else { throw POCError.message("Run tersimpan tidak mempunyai sesi; data tidak direset otomatis.") }
    }
    // One immutable value snapshot contains both state and events. A failed save cannot expose partial counters.
    func commit(_ change: (inout RunState) throws -> Void) throws {
        var next = state
        try change(&next)
        guard !next.sessions.isEmpty else { throw POCError.message("Run harus memiliki minimal satu sesi.") }
        let encoded = try JSONEncoder().encode(next)
        do {
            document.payload = encoded
            if failNextSave { failNextSave = false; throw POCError.message("Injected save failure. Perubahan belum disimpan; coba lagi.") }
            try context.save()
            state = next
        } catch {
            context.rollback()
            throw error
        }
    }
    func apply(_ action: AttendanceAction, participantID: String? = nil, reason: String = "", arrangement: String = "", actionID: UUID = UUID()) throws {
        try commit { next in
            guard let i = next.activeIndex else { throw POCError.message("Tidak ada sesi aktif.") }
            try next.sessions[i].apply(action, participantID: participantID, reason: reason, arrangement: arrangement, actionID: actionID)
        }
    }
}
