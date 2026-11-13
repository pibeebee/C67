#if DEBUG
    import SwiftUI
    import C67Data

    struct TripCreationDesignPreview: View {
        let specificPlace: Bool
        var body: some View {
            let planning = PlanningPresenter(interactor: .init(repository: MockPlanningRepository()),
                                             initialInput: try? MockPlanningRepository.sampleInput())
            TripCreationAssembly.make(planning: planning, mode: "Mock • memory only", specificPlace: specificPlace, dismiss: {})
        }
    }
    #Preview("Connected flow · Recommendations") { TripCreationDesignPreview(specificPlace: false) }
    #Preview("Connected flow · Specific places") { TripCreationDesignPreview(specificPlace: true) }
#endif
