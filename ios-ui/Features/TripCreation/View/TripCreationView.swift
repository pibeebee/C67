import SwiftUI

struct TripCreationView: View {
    @State private var presenter: TripCreationPresenter
    let dismiss: () -> Void
    @State private var isRunningOperation = false
    @State private var operation: Task<Void, Never>?

    init(presenter: TripCreationPresenter, dismiss: @escaping () -> Void) {
        _presenter = State(initialValue: presenter)
        self.dismiss = dismiss
    }

    var body: some View {
        NavigationStack(path: $presenter.path) {
            screen(presenter.root)
                .navigationDestination(for: TripCreationRoute.self) { screen($0) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let error = presenter.error, !presenter.isProcessing {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.circle").font(.footnote)
                    if presenter.route == .mainSpot || presenter.route == .stay {
                        Button("Try again") { run { await presenter.plan() } }
                    }
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColor.surface)
            }
        }
        .overlay {
            if presenter.isProcessing {
                ZStack(alignment: .bottom) {
                    if presenter.isSuggesting { RecommendationsProcessingView() }
                    else {
                        TripProcessingView(advances: false, messageOverride: presenter.mode.hasPrefix("Mock")
                            ? "Building your synthetic itinerary…" : "Putting your trip together…")
                    }
                    Button { operation?.cancel(); dismiss() } label: {
                        Text("Cancel").frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .padding(20)
                }
            }
        }
        .interactiveDismissDisabled(presenter.isProcessing || presenter.planning.isBusy)
        .onChange(of: presenter.planning.sessionGeneration) { _, _ in operation?.cancel(); dismiss() }
        .onDisappear { operation?.cancel() }
        .tint(AppColor.accent)
    }

    @ViewBuilder private func screen(_ route: TripCreationRoute) -> some View {
        Group {
            switch route {
            case .question(let step):
                PreferenceQuestionView(step: step, answers: presenter.answers,
                                       update: { presenter.answers = $0 },
                                       advance: { presenter.advance(step) },
                                       skip: { presenter.advance(step, skip: true) })
            case .places:
                AddPlacesView(query: $presenter.query, results: presenter.results, selected: presenter.selected,
                              isSearching: presenter.isSearching, error: presenter.searchError,
                              synthetic: presenter.mode.hasPrefix("Mock"), search: { await presenter.search() }, toggle: presenter.toggle) {
                    if presenter.path.contains(.confirmation) { presenter.path.removeLast() }
                    else { presenter.push(.confirmation) }
                }
            case .confirmation:
                TripInputConfirmationView(presenter: presenter) { run { await presenter.confirm() } }
            case .recommendations:
                PlacesRecommendationsView(batch: presenter.batch, existing: presenter.recommendationBase.map(\.place),
                                          selected: presenter.chosenRecommendations,
                                          refresh: { await presenter.suggest() },
                                          continueWithoutSelection: { presenter.chooseRecommendations([]) },
                                          complete: presenter.chooseRecommendations)
            case .mainSpot:
                MainSpotQuestionView(places: presenter.selected, selection: presenter.mainSpot,
                                     select: { presenter.mainSpot = $0; presenter.stay = nil },
                                     next: { run { await presenter.finishMainSpot() } },
                                     skip: { presenter.mainSpot = .automatic; run { await presenter.plan() } })
            case .stay:
                StayDurationQuestionView(placeName: presenter.selected.first(where: { $0.id == presenter.mainSpot.placeID })?.place.name ?? "your main spot",
                                         selection: presenter.stay,
                                         select: { value in presenter.stay = value; run { await presenter.plan() } },
                                         skip: { presenter.stay = nil; run { await presenter.plan() } })
            case .review:
                if let proposal = presenter.reviewProposal {
                    ItineraryReviewView(presenter: presenter.planning, initialProposal: proposal)
                }
            }
        }
        .disabled(presenter.isProcessing)
        .toolbar(presenter.isProcessing ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: dismiss)
                    .disabled(presenter.isProcessing || presenter.planning.isBusy)
            }
        }
    }

    private func run(_ action: @escaping @MainActor () async -> Void) {
        guard !presenter.isProcessing, !isRunningOperation else { return }
        isRunningOperation = true
        operation = Task {
            defer { isRunningOperation = false }
            await action()
        }
    }
}
