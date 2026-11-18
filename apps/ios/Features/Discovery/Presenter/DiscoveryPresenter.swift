import Foundation
import Observation
import C67Domain

@MainActor @Observable
final class DiscoveryPresenter {
    var rundowns: [Rundown] = []
    var isLoading = false
    var isSaving = false
    private(set) var loadError: String?
    private(set) var saveError: String?
    private(set) var failedRundownID: UUID?
    var error: String? { saveError ?? loadError }
    var savedTrip: Trip?
    private var sessionID: UUID?
    private var saveTask: Task<Trip, Error>?
    private let interactor: DiscoveryInteractor
    private var pending: (versionID: UUID, startsAt: Date, requestID: UUID)?

    init(interactor: DiscoveryInteractor) { self.interactor = interactor }
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do { rundowns = try await interactor.load() }
        catch is CancellationError { }
        catch { if !Task.isCancelled { loadError = "Check your connection and try loading rundowns again." } }
    }
    func save(_ rundown: Rundown, at start: Date) async {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil; failedRundownID = nil
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
        catch {
            guard operation == sessionID, !Task.isCancelled else { return }
            failedRundownID = rundown.id
            saveError = "The trip couldn’t be saved. Try again."
        }
    }
    func sessionDidChange(_ snapshot: AuthenticationSnapshot) {
        guard sessionID != snapshot.sessionID else { return }
        sessionID = snapshot.sessionID
        saveTask?.cancel(); saveTask = nil
        isSaving = false; savedTrip = nil; pending = nil; saveError = nil; failedRundownID = nil
    }
    func dismissResult() { savedTrip = nil; pending = nil }
}
