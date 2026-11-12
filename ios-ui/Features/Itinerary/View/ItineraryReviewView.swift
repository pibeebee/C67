import SwiftUI
import C67Domain

struct ItineraryReviewView: View {
    let presenter: PlanningPresenter
    let initialProposal: PlanProposal
    @State private var showsSaveName = false
    @State private var saveName = ""
    @State private var editRoute: ItineraryEditRoute?

    private var proposal: PlanProposal { presenter.job?.result?.proposal ?? initialProposal }
    private var retryAction: (() -> Void)? {
        if presenter.needsFreshProposal || presenter.job?.result?.proposal == nil { return { regenerate() } }
        if presenter.error != nil { return { Task { await presenter.apply() } } }
        return nil
    }

    var body: some View {
        ItineraryListView(proposal: proposal, isSaving: presenter.isBusy, error: presenter.error,
                          canSave: !presenter.needsFreshProposal && presenter.job?.result?.proposal != nil && presenter.draftInput == proposal.input,
                          retry: retryAction,
                          edit: edit, save: { saveName = proposal.input.title; showsSaveName = true })
            .modifier(ItinerarySaveNameDialog(isPresented: $showsSaveName, name: $saveName, originalName: proposal.input.title, save: save))
            .safeAreaInset(edge: .top, spacing: 0) {
                if proposal.input.title != initialProposal.input.title {
                    Text("Updated itinerary. Review it before saving.")
                        .font(.footnote).padding().frame(maxWidth: .infinity).background(AppColor.surface)
                }
            }
            .disabled(presenter.isBusy)
            .overlay {
                if presenter.isBusy {
                    ProgressView(presenter.progress ?? String(localized: "Working on your itinerary…"))
                        .padding(20)
                        .background(.regularMaterial, in: .rect(cornerRadius: 16))
                }
            }
            .sheet(item: $editRoute) { route in
                switch route {
                case .visit(let place):
                    ItineraryVisitEditor(place: place, zone: proposal.input.timeZone,
                                         startsAt: proposal.input.startsAt, update: update)
                case .addPlace:
                    PlanningSearchSheet(near: presenter.origin, title: "Add a place", select: add)
                }
            }
    }

    private func edit(_ id: UUID?) {
        if let id, let place = presenter.places.first(where: { $0.id == id }) {
            editRoute = .visit(place)
        } else if id == nil {
            editRoute = .addPlace
        }
    }

    private func update(_ place: PlanningPlace) {
        guard let index = presenter.places.firstIndex(where: { $0.id == place.id }), !presenter.isBusy else { return }
        presenter.places[index] = place
        regenerate()
    }

    private func add(_ place: PlanningPlace) {
        guard presenter.places.count < 6, !presenter.isBusy else { return }
        presenter.places.append(place)
        regenerate()
    }

    private func regenerate() {
        presenter.draftChanged()
        Task { await presenter.request() }
    }

    private func save() {
        Task { await presenter.saveReviewedProposal(named: saveName) }
    }
}
