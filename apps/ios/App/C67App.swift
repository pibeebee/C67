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
                } else if ProcessInfo.processInfo.arguments.contains("--home-draft-ready-preview") {
                    HomeAddedTripDesignPreview(draftStatus: .succeeded)
                } else if ProcessInfo.processInfo.arguments.contains("--home-draft-running-preview") {
                    HomeAddedTripDesignPreview(draftStatus: .running)
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
    @State private var result: Result<AppDependencies, Error>

    init(pocketRepositories: PocketRepositoryRegistry) {
        self.pocketRepositories = pocketRepositories
        _result = State(initialValue: Self.makeDependencies(pocketRepositories))
    }

    private static func makeDependencies(_ repositories: PocketRepositoryRegistry) -> Result<AppDependencies, Error> {
        Result { try AppDependencies.make(removeAccountData: { try await repositories.erase(for: $0) }) }
    }
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
            let needsConfiguration = (error as? RepositoryError) == .invalidConfiguration
            ContentUnavailableView {
                Label("Travelant couldn’t start", systemImage: "gearshape")
            } description: {
                if needsConfiguration {
                    Text("This build couldn’t start. Check for a Travelant update or contact support.")
                } else {
                    Text("Try opening Travelant again. Your trips haven’t been removed.")
                }
            } actions: {
                if needsConfiguration {
                    ShareLink(item: "Travelant could not start because this build needs configuration.") {
                        Label("Share startup details", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button("Try again") { result = Self.makeDependencies(pocketRepositories) }
                }
            }
        }
    }
}

/// Sign in once; session refresh and per-account trip storage stay on device.
private struct PocketAuthenticatedRoot: View {
    let authentication: any TravellerAuthentication
    let repositories: PocketRepositoryRegistry
    @State private var account: TravellerAccount?
    @State private var restored = false
    @State private var accountDeleted = false
    @State private var busy = false
    @State private var issue: PresentationIssue?

    var body: some View {
        Group {
            if let account {
                PocketAuthenticatedWorkspace(authentication: authentication, accountID: account.id, repositories: repositories)
                    .id(account.id)
            } else if restored {
                VStack(spacing: 20) {
                    Text("Welcome to Travelant").font(.largeTitle.bold())
                    Text(accountDeleted ? "Your account has been deleted." : "Sign in to create and continue your trips.")
                        .foregroundStyle(.secondary)
                    AppleSignInButtonView { result in
                        switch result {
                        case .success(let credentials):
                            busy = true; issue = nil
                            Task {
                                defer { busy = false }
                                do { _ = try await authentication.signInWithApple(credentials) }
                                catch is CancellationError { }
                                catch { issue = .init(account: error) }
                            }
                        case .failure(let failure): issue = .init(account: failure)
                        }
                    }.disabled(busy)
                    if busy { ProgressView("Signing in…") }
                    if let issue {
                        RecoveryNotice(title: "Sign-in needs attention", message: issue.message,
                                       primary: issue.recovery == .checkSession
                                           ? .init(title: "Check session again") { Task { await checkSession() } }
                                           : nil)
                    }
                }.padding(24).frame(maxWidth: 480)
            } else { ProgressView("Restoring your account…") }
        }
        .task {
            let changes = await authentication.sessionChanges()
            await checkSession()
            for await snapshot in changes {
                guard !Task.isCancelled else { return }
                if snapshot.isRestored {
                    let nextAccount = snapshot.requiresPasswordReset ? nil : snapshot.account
                    if let oldID = account?.id, oldID != nextAccount?.id {
                        await repositories.suspendOrdering(for: oldID)
                    }
                    account = nextAccount
                    accountDeleted = snapshot.accountDeleted
                    restored = true
                }
            }
        }
    }

    private func checkSession() async {
        guard !busy else { return }
        busy = true; issue = nil
        defer { busy = false; restored = true }
        do { _ = try await authentication.currentAccount() }
        catch is CancellationError { }
        catch { issue = .init(account: error, checkingSession: true) }
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
            } else if error != nil {
                ContentUnavailableView {
                    Label("Trip storage unavailable", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Your trips could not be opened. Try again; your saved data has not been removed.")
                } actions: {
                    Button("Try again") { openRepository() }
                }
            } else { ProgressView("Loading your trips…") }
        }
        .task { openRepository() }
    }

    private func openRepository() {
        error = nil
        do {
            let raw = Bundle.main.object(forInfoDictionaryKey: "POCKET_SERVER_URL") as? String ?? ""
            let connection = try AuthenticatedPocketConnection(serverURL: raw, authentication: authentication)
            repository = try repositories.repository(for: accountID, connection: connection)
        } catch { self.error = error.localizedDescription }
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

    func erase(for accountID: UUID) async throws {
        await HTTPPlanningRepository.eraseAccountData(for: accountID)
        if let repository = repositories[accountID] {
            try await repository.eraseAccountData()
            repositories[accountID] = nil
        }
        let folder = try PocketPlanningRepository.storageURL(for: accountID).deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    func suspendOrdering(for accountID: UUID) async {
        await repositories[accountID]?.suspendOrdering()
    }
}
