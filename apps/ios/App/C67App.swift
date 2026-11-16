import SwiftUI
import C67Domain
import C67Data

@main
struct C67App: App {
    @State private var pocketRepositories = PocketRepositoryRegistry()
    var body: some Scene {
        WindowGroup {
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--completed-trip-preview") {
                    TripProgressDesignPreview(completed: true)
                } else if ProcessInfo.processInfo.arguments.contains("--add-places-preview") {
                    AddPlacesDesignPreview()
                } else if ProcessInfo.processInfo.arguments.contains("--add-places-selected-preview") {
                    AddPlacesDesignPreview(addedCount: 4)
                } else if ProcessInfo.processInfo.arguments.contains("--places-sheet-preview") {
                    AddPlacesDesignPreview(addedCount: 4, showsSheet: true)
                } else if ProcessInfo.processInfo.arguments.contains("--arrival-preview") {
                    TripProgressDesignPreview(arrived: true)
                } else if ProcessInfo.processInfo.arguments.contains("--active-trip-preview") {
                    TripProgressDesignPreview()
                } else if ProcessInfo.processInfo.arguments.contains("--home-added-preview") {
                    HomeAddedTripDesignPreview()
                } else if ProcessInfo.processInfo.arguments.contains("--saved-trip-preview") {
                    SavedTripDesignPreview()
                } else if ProcessInfo.processInfo.arguments.contains("--save-name-preview") {
                    ItinerarySaveDesignPreview()
                } else if ProcessInfo.processInfo.arguments.contains("--itinerary-preview") {
                    ItineraryDesignPreview()
                } else if ProcessInfo.processInfo.arguments.contains("--recommendations-preview") {
                    RecommendationsDesignPreview(addedCount: 0)
                } else if ProcessInfo.processInfo.arguments.contains("--recommendations-added-preview") {
                    RecommendationsDesignPreview(addedCount: 3)
                } else if ProcessInfo.processInfo.arguments.contains("--recommendations-processing-preview") {
                    RecommendationsProcessingView()
                } else {
                    StarterRootView(pocketRepositories: pocketRepositories)
                        .splashOverlay()
                }
            #else
                StarterRootView(pocketRepositories: pocketRepositories)
                    .splashOverlay()
            #endif
        }
    }
}

private struct StarterRootView: View {
    let pocketRepositories: PocketRepositoryRegistry
    @State private var result = Result { try AppDependencies.make() }
    var body: some View {
        switch result {
        case .success(let dependencies):
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--pocket-auth-settings-fixture") {
                    PlanningAssembly.make(repository: dependencies.planningRepository, mode: dependencies.mode,
                                          initialInput: dependencies.planningInitialInput, authentication: dependencies.authentication)
                } else if dependencies.mode == "Pocket • authenticated", let authentication = dependencies.authentication {
                    PocketAuthenticatedRoot(authentication: authentication, repositories: pocketRepositories)
                } else if ProcessInfo.processInfo.arguments.contains("--legacy-catalog") {
                    DiscoveryAssembly.make(repository: dependencies.repository, mode: dependencies.mode, authentication: dependencies.authentication)
                } else {
                    PlanningAssembly.make(repository: dependencies.planningRepository, mode: dependencies.mode,
                                          initialInput: dependencies.planningInitialInput, authentication: dependencies.authentication)
                }
            #else
                if dependencies.mode == "Pocket • authenticated", let authentication = dependencies.authentication {
                    PocketAuthenticatedRoot(authentication: authentication, repositories: pocketRepositories)
                } else if ProcessInfo.processInfo.arguments.contains("--legacy-catalog") {
                    DiscoveryAssembly.make(repository: dependencies.repository, mode: dependencies.mode,
                                           authentication: dependencies.authentication)
                } else {
                    PlanningAssembly.make(repository: dependencies.planningRepository, mode: dependencies.mode,
                                          initialInput: dependencies.planningInitialInput,
                                          authentication: dependencies.authentication)
                }
            #endif
        case .failure(let error):
            ContentUnavailableView("Configuration needed", systemImage: "gearshape",
                                   description: Text(error.localizedDescription))
        }
    }
}

/// Sign in once; session refresh and per-account trip storage stay on device.
private struct PocketAuthenticatedRoot: View {
    let authentication: any TravellerAuthentication
    let repositories: PocketRepositoryRegistry
    @State private var account: TravellerAccount?
    @State private var restored = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Group {
            if let account {
                PocketAuthenticatedWorkspace(authentication: authentication, accountID: account.id, repositories: repositories)
                    .id(account.id)
            } else if restored {
                VStack(spacing: 20) {
                    Text("Welcome to Travelant").font(.largeTitle.bold())
                    Text("Sign in to create and continue your trips.").foregroundStyle(.secondary)
                    AppleSignInButtonView { result in
                        switch result {
                        case .success(let credentials):
                            busy = true; error = nil
                            Task {
                                defer { busy = false }
                                do { _ = try await authentication.signInWithApple(credentials) }
                                catch { self.error = error.localizedDescription }
                            }
                        case .failure(let failure): error = failure.localizedDescription
                        }
                    }.disabled(busy)
                    if busy { ProgressView("Signing in…") }
                    if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                }.padding(24).frame(maxWidth: 480)
            } else { ProgressView("Restoring your account…") }
        }
        .task {
            let changes = await authentication.sessionChanges()
            do { _ = try await authentication.currentAccount() }
            catch { self.error = error.localizedDescription; restored = true }
            for await snapshot in changes {
                guard !Task.isCancelled else { return }
                if snapshot.isRestored {
                    let nextAccount = snapshot.requiresPasswordReset ? nil : snapshot.account
                    if let oldID = account?.id, oldID != nextAccount?.id {
                        await repositories.suspendOrdering(for: oldID)
                    }
                    account = nextAccount
                    restored = true
                }
            }
        }
    }
}

private struct PocketAuthenticatedWorkspace: View {
    let authentication: any TravellerAuthentication
    let accountID: UUID
    let repositories: PocketRepositoryRegistry
    @State private var repository: (any PlanningRepository)?
    @State private var error: String?

    var body: some View {
        Group {
            if let repository {
                PlanningAssembly.make(repository: repository, mode: "Pocket • authenticated", initialInput: nil, authentication: authentication)
            } else if let error {
                ContentUnavailableView("Trip storage unavailable", systemImage: "externaldrive.badge.exclamationmark", description: Text(error))
            } else { ProgressView("Loading your trips…") }
        }
        .task {
            do {
                let raw = Bundle.main.object(forInfoDictionaryKey: "POCKET_SERVER_URL") as? String ?? ""
                let connection = try AuthenticatedPocketConnection(serverURL: raw, authentication: authentication)
                repository = try repositories.repository(for: accountID, connection: connection)
            } catch { self.error = error.localizedDescription }
        }
    }
}

/// A single app-wide owner prevents multiple actors writing the same account file.
@MainActor
private final class PocketRepositoryRegistry {
    private var repositories: [UUID: PocketPlanningRepository] = [:]

    func repository(for accountID: UUID, connection: AuthenticatedPocketConnection) throws -> PocketPlanningRepository {
        if let existing = repositories[accountID] { return existing }
        let repository = try PocketPlanningRepository(services: .live(connection: connection), connection: connection,
                                                      storageURL: PocketPlanningRepository.storageURL(for: accountID))
        repositories[accountID] = repository
        return repository
    }

    func suspendOrdering(for accountID: UUID) async {
        await repositories[accountID]?.suspendOrdering()
    }
}
