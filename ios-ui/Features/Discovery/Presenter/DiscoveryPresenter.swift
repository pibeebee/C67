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
        defer { isSaving = false }
        // Keep the command identity after a failed/uncertain request; replace it for new input.
        if pending?.versionID != rundown.id || pending?.startsAt != start {
            pending = (rundown.id, start, UUID())
        }
        guard let command = pending else { return }
        do {
            savedTrip = try await interactor.save(rundown, at: start, requestID: command.requestID)
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    func dismissResult() { savedTrip = nil; pending = nil }
}
