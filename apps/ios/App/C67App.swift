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
                } else if ProcessInfo.processInfo.arguments.contains("--trip-processing-preview") {
                    TripProcessingActivityPreview()
                } else {
                    StarterRootView(pocketRepositories: pocketRepositories)
                }
            #else
                StarterRootView(pocketRepositories: pocketRepositories)
            #endif
        }
    }
}

private struct StarterRootView: View {
    let pocketRepositories: PocketRepositoryRegistry
    private enum Workspace {
        case authenticated(any TravellerAuthentication)
        #if DEBUG
            case development(AppDependencies)
        #endif
    }

    @State private var result: Result<Workspace, Error>

    init(pocketRepositories: PocketRepositoryRegistry) {
        self.pocketRepositories = pocketRepositories
        _result = State(initialValue: Self.makeDependencies(pocketRepositories))
    }

    private static func makeDependencies(_ repositories: PocketRepositoryRegistry) -> Result<Workspace, Error> {
        Result {
            let erase: @Sendable (UUID) async throws -> Void = { try await repositories.erase(for: $0) }
            #if DEBUG
                let mode = Bundle.main.object(forInfoDictionaryKey: "C67_DATA_MODE") as? String
                if mode != "pocket-auth" || ProcessInfo.processInfo.arguments.contains("--pocket-auth-fixture") {
                    return .development(try AppDependencies.make(removeAccountData: erase))
                }
            #endif
            return .authenticated(try AppDependencies.makeAuthenticated(removeAccountData: erase))
        }
    }

    var body: some View {
        switch result {
        case .success(.authenticated(let authentication)):
            PocketAuthenticatedRoot(authentication: authentication, repositories: pocketRepositories)
        #if DEBUG
            case .success(.development(let dependencies)):
                if dependencies.mode == AppDependencies.authenticatedMode,
                   let authentication = dependencies.authentication,
                   !ProcessInfo.processInfo.arguments.contains("--pocket-auth-settings-fixture") {
                    PocketAuthenticatedRoot(authentication: authentication, repositories: pocketRepositories)
                } else if ProcessInfo.processInfo.arguments.contains("--legacy-catalog") {
                    DiscoveryAssembly.make(repository: dependencies.repository, mode: dependencies.mode, authentication: dependencies.authentication)
                } else {
                    PlanningAssembly.make(repository: dependencies.planningRepository, mode: dependencies.mode,
                                          initialInput: dependencies.planningInitialInput, authentication: dependencies.authentication)
                }
        #endif
        case .failure(let error):
            let needsConfiguration = (error as? RepositoryError) == .invalidConfiguration
            ContentUnavailableView {
                Label("Travelants couldn’t start", systemImage: "gearshape")
            } description: {
                if needsConfiguration {
                    Text("This build couldn’t start. Check for a Travelants update or contact support.")
                } else {
                    Text("Try opening Travelants again. Your trips haven’t been removed.")
                }
            } actions: {
                if needsConfiguration {
                    ShareLink(item: "Travelants could not start because this build needs configuration.") {
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
    @State private var requiresManualAppleRevocation = false
    @State private var busy = false
    @State private var issue: PresentationIssue?
    @State private var showsReviewSignIn = false
    private let reviewEmails = AppDependencies.reviewEmails

    var body: some View {
        Group {
            if let account {
                PocketAuthenticatedWorkspace(authentication: authentication, accountID: account.id, repositories: repositories)
                    .id(account.id)
            } else if restored {
                ScrollView {
                    VStack(spacing: 20) {
                        Image("TravelantsMark")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 144)
                            .accessibilityHidden(true)
                        Text("Welcome to Travelants")
                            .font(AppFont.largeTitleBold)
                            .accessibilityAddTraits(.isHeader)
                        Text(accountDeleted ? "Your account has been deleted." : "Plan a trip and pick up where you left off.")
                            .font(AppFont.body)
                            .foregroundStyle(.secondary)
                        if requiresManualAppleRevocation {
                            Link("How to remove Apple access", destination: AccountView.appleRevocationHelp)
                        }
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
                        if !reviewEmails.isEmpty {
                            Button("App Review Sign-In") { showsReviewSignIn = true }
                                .accessibilityIdentifier("appReviewSignIn")
                                .disabled(busy)
                        }
                        if let policy = TravelantsPrivacy.policyURL { Link("Privacy Policy", destination: policy) }
                        if busy { ProgressView("Signing in…") }
                        if let issue {
                            RecoveryNotice(title: "Sign-in needs attention", message: issue.message,
                                           primary: issue.recovery == .checkSession
                                               ? .init(title: "Check session again") { Task { await checkSession() } }
                                               : nil)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32)
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.center, for: .alignment)
            } else { ProgressView("Restoring your account…") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { if account == nil { AppColor.canvas.ignoresSafeArea() } }
        .tint(AppColor.accent)
        .sheet(isPresented: $showsReviewSignIn) {
            AppReviewSignInView(presenter: AccountAssembly.makePresenter(authentication: authentication))
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
                    // Recent places are shown only to the account that chose them.
                    PlanningRecentPlaces.owner = nextAccount?.id
                    if snapshot.accountDeleted { PlanningRecentPlaces.clear() }
                    account = nextAccount
                    accountDeleted = snapshot.accountDeleted
                    requiresManualAppleRevocation = snapshot.requiresManualAppleRevocation
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

private struct AppReviewSignInView: View {
    @Environment(\.dismiss) private var dismiss
    @State var presenter: AccountPresenter
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email address", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("appReviewEmail")
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .accessibilityIdentifier("appReviewPassword")
                    Button("Sign in", action: signIn)
                        .accessibilityIdentifier("appReviewSubmit")
                        .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                } footer: {
                    Text("Use the demo credentials provided in App Store Connect.")
                }
                if presenter.isBusy { ProgressView("Signing in…") }
                if let issue = presenter.issue {
                    RecoveryNotice(title: "Sign-in needs attention", message: issue.message)
                }
            }
            .disabled(presenter.isBusy)
            .navigationTitle("App Review Sign-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(presenter.isBusy)
                }
            }
        }
        .interactiveDismissDisabled(presenter.isBusy)
        .onDisappear { password = "" }
    }

    private func signIn() {
        let submittedEmail = email
        let submittedPassword = password
        password = ""
        Task {
            await presenter.signIn(email: submittedEmail, password: submittedPassword)
            if presenter.account != nil { dismiss() }
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
            } else if error != nil {
                ContentUnavailableView {
                    Label("Trip storage unavailable", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(error ?? "Trip storage is unavailable.")
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
        } catch {
            self.error = (error as? PlanningError) == .failed("TRIP_STORAGE_CORRUPT") ?
                "The saved trip file needs recovery. The original file is preserved." :
                "Your trips could not be opened. Try again when your device storage is available."
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
                                                      storageURL: PocketPlanningRepository.storageURL(for: accountID),
                                                      requiresExternalAIConsent: true,
                                                      externalAIDisclosure: TravelantsPrivacy.disclosure)
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

enum TravelantsPrivacy {
    #if DEBUG
        private static var isFixture: Bool {
            ProcessInfo.processInfo.arguments.contains("--pocket-privacy-fixture")
        }
    #endif

    static var policyURL: URL? {
        #if DEBUG
            if isFixture { return URL(string: "https://fixture.invalid/privacy") }
        #endif
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "TRAVELANTS_PRIVACY_POLICY_URL") as? String,
              let url = URL(string: raw), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    static var aiRecipient: String? {
        #if DEBUG
            if isFixture { return "Synthetic test provider" }
        #endif
        return setting("TRAVELANTS_AI_RECIPIENT")
    }

    static var disclosure: String? {
        guard let policyURL, let aiRecipient, let version = setting("TRAVELANTS_AI_DISCLOSURE_VERSION") else { return nil }
        return "\(version)|\(aiRecipient)|\(policyURL.absoluteString)"
    }

    private static func setting(_ key: String) -> String? {
        guard let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }
}
