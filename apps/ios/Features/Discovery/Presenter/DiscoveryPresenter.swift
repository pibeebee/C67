import Foundation
import Observation
import C67Domain

@MainActor @Observable
final class DiscoveryPresenter {
    var rundowns: [Rundown] = []
    var isLoading = false
    var isSaving = false
    var error: String?
    var savedTrip: Trip?
    private var sessionID: UUID?
    private var saveTask: Task<Trip, Error>?
    private let interactor: DiscoveryInteractor
    private var pending: (versionID: UUID, startsAt: Date, requestID: UUID)?

    init(interactor: DiscoveryInteractor) { self.interactor = interactor }
    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do { rundowns = try await interactor.load() }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    func save(_ rundown: Rundown, at start: Date) async {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        let operation = sessionID
        defer { if operation == sessionID { isSaving = false; saveTask = nil } }
        if pending?.versionID != rundown.id || pending?.startsAt != start {
            pending = (rundown.id, start, UUID())
        }
        guard let command = pending else { return }
        let interactor = interactor
        let task = Task { try await interactor.save(rundown, at: start, requestID: command.requestID) }
        saveTask = task
        do {
            let value = try await task.value
            guard operation == sessionID, !Task.isCancelled else { return }
            savedTrip = value
        } catch is CancellationError { }
        catch { if operation == sessionID { self.error = error.localizedDescription } }
    }
    func sessionDidChange(_ snapshot: AuthenticationSnapshot) {
        guard sessionID != snapshot.sessionID else { return }
        sessionID = snapshot.sessionID
        saveTask?.cancel(); saveTask = nil
        isSaving = false; savedTrip = nil; pending = nil; error = nil
    }
    func dismissResult() { savedTrip = nil; pending = nil }
}
