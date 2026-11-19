import Foundation
import Observation
import C67Domain

@MainActor @Observable
final class AccountPresenter {
    enum Screen: String, CaseIterable { case signIn = "Sign in", signUp = "Create account", recovery = "Forgot password" }
    struct DeletionReview: Identifiable {
        let id = UUID()
        let account: TravellerAccount
        let sessionID: UUID?
        var requiresAppleVerification: Bool
        var offersManualRevocation = false
    }

    private(set) var account: TravellerAccount?
    private(set) var requiresPasswordReset = false
    private(set) var pendingEmail: String?
    private(set) var pendingRecovery = false
    private(set) var isBusy = false
    private(set) var hasRestored = false
    var screen: Screen = .signIn
    private(set) var issue: PresentationIssue?
    private(set) var deletionPending = false
    private(set) var deletingAccount = false
    private(set) var deletionMessage: String?
    private(set) var requiresManualAppleRevocation = false
    private(set) var deletionReview: DeletionReview?
    private var authorizingDeletionReviewID: UUID?
    private var sessionID: UUID?
    var isAuthorizingDeletion: Bool { authorizingDeletionReviewID != nil }
    var supportsAccountDeletion: Bool { interactor.supportsAccountDeletion }
    var error: String? { issue?.message }
    var notice: String?
    var onSessionChange: ((AuthenticationSnapshot) -> Void)?
    private var queuedCallback: URL?
    private let interactor: AccountInteractor

    init(interactor: AccountInteractor) { self.interactor = interactor }
    /// Owned by the root view's task, so observation is cancelled when that feature leaves the tree.
    func observe() async {
        let changes = await interactor.changes()
        for await value in changes {
            guard !Task.isCancelled else { return }
            sessionID = value.sessionID
            account = value.account
            requiresPasswordReset = value.requiresPasswordReset
            if let review = deletionReview, !isCurrent(review) { closeDeletionReview() }
            pendingEmail = value.pendingEmail
            pendingRecovery = value.pendingRecovery
            if value.isRestored { hasRestored = true }
            onSessionChange?(value)
        }
    }
    func restore(force: Bool = false) async {
        guard !isBusy, !isAuthorizingDeletion else { return }
        isBusy = true
        defer { finishAction(); hasRestored = true }
        do {
            account = try await (force ? interactor.refresh() : interactor.restore())
            // Opening Account or returning to the foreground must not erase callback feedback.
            deletionPending = try await interactor.hasPendingDeletion()
            if force { issue = nil }
        }
        catch is CancellationError { }
        catch AuthenticationError.sessionExpired { account = nil; issue = .init(account: AuthenticationError.sessionExpired) }
        catch AuthenticationError.remoteSignOutFailed { account = nil; issue = .init(account: AuthenticationError.remoteSignOutFailed) }
        catch { issue = .init(account: error, checkingSession: true) }
        if let review = deletionReview, !isCurrent(review) { closeDeletionReview() }
    }
    func signIn(email: String, password: String) async {
        await perform { self.account = try await self.interactor.signIn(email: email, password: password) }
    }
    func signInWithApple(_ credentials: AppleSignInCredentials) async {
        await perform { self.account = try await self.interactor.signInWithApple(credentials) }
    }
    func appleAuthorizationFailed(_ failure: AuthenticationError) {
        guard !isBusy else { return }
        issue = .init(account: failure); notice = nil
    }
    func signUp(email: String, password: String) async {
        await perform {
            try await self.interactor.signUp(email: email, password: password)
            self.notice = "If this address can be registered, a confirmation email will arrive. Open its link on this device."
        }
    }
    func resend() async {
        await perform {
            try await self.interactor.resend()
            self.notice = "Confirmation requested. Check your inbox and spam folder, and open the newest link here."
        }
    }
    func recover(email: String) async {
        await perform {
            try await self.interactor.recover(email: email)
            self.notice = "If an account exists for this address, a recovery email will arrive. Open its link on this device."
        }
    }
    func callback(_ url: URL) async {
        if isBusy { queuedCallback = url; return }
        await perform {
            try await self.interactor.callback(url)
            self.notice = nil
        }
    }
    func updatePassword(_ password: String) async {
        await perform {
            try await self.interactor.updatePassword(password)
            self.requiresPasswordReset = false
            self.notice = "Password updated. Your session is ready."
        }
    }
    func cancelEmailFlow() async {
        await perform { try await self.interactor.cancelEmailFlow(); self.notice = nil }
    }
    func signOut() async {
        await perform {
            do { try await self.interactor.signOut(); self.account = nil; self.requiresPasswordReset = false }
            catch AuthenticationError.remoteSignOutFailed {
                self.account = nil; self.requiresPasswordReset = false
                throw AuthenticationError.remoteSignOutFailed
            }
        }
    }

    func openDeletionReview(requiresAppleVerification: Bool) {
        guard supportsAccountDeletion, let account, !requiresPasswordReset,
              !isBusy, !deletionPending, deletionReview == nil else { return }
        deletionMessage = nil
        deletionReview = .init(account: account, sessionID: sessionID, requiresAppleVerification: requiresAppleVerification)
    }

    func openPocketDeletionReview(reviewEmails: Set<String>) async {
        guard let email = account?.email?.lowercased(), reviewEmails.contains(email) else {
            openDeletionReview(requiresAppleVerification: true)
            return
        }
        let originalAccount = account?.id
        let originalSession = sessionID
        let requiresAppleVerification: Bool
        do { requiresAppleVerification = try await interactor.currentAppleUserID() != nil }
        catch { requiresAppleVerification = true }
        guard originalAccount == account?.id, originalSession == sessionID else { return }
        openDeletionReview(requiresAppleVerification: requiresAppleVerification)
    }

    func closeDeletionReview() {
        deletionReview = nil
        authorizingDeletionReviewID = nil
    }

    func beginAppleDeletionAuthorization(for review: DeletionReview) {
        guard isCurrent(review), review.requiresAppleVerification, !isBusy,
              !deletionPending, !isAuthorizingDeletion else { return }
        // The native sheet can change scene phase. Keep foreground restoration from racing its result.
        authorizingDeletionReviewID = review.id
        deletionMessage = nil
        deletionReview?.offersManualRevocation = false
    }

    func cancelAppleDeletionAuthorization(for review: DeletionReview) {
        guard authorizingDeletionReviewID == review.id else { return }
        authorizingDeletionReviewID = nil
    }

    func finishAppleDeletionAuthorization(_ result: Result<AppleSignInCredentials, AuthenticationError>,
                                          for review: DeletionReview) async {
        guard authorizingDeletionReviewID == review.id else { return }
        authorizingDeletionReviewID = nil
        guard isCurrent(review), !isBusy, !deletionPending else { return }
        switch result {
        case .success(let credentials):
            guard let code = credentials.authorizationCode, !code.isEmpty else {
                offerManualRevocation(after: .invalidAppleCredential)
                return
            }
            await deleteAccount(appleAuthorizationCode: code)
        case .failure(let failure):
            offerManualRevocation(after: failure)
        }
    }

    func confirmDeletion(for review: DeletionReview, useManualAppleRevocation: Bool = false) async {
        guard isCurrent(review), !deletionPending, !isAuthorizingDeletion else { return }
        if useManualAppleRevocation {
            guard deletionReview?.offersManualRevocation == true else { return }
        } else {
            guard deletionReview?.requiresAppleVerification == false else { return }
        }
        await deleteAccount(useManualAppleRevocation: useManualAppleRevocation)
    }

    func deleteAccount(appleAuthorizationCode: String? = nil, useManualAppleRevocation: Bool = false) async {
        guard !isBusy, !isAuthorizingDeletion, let account else { return }
        let requestSessionID = sessionID
        isBusy = true; deletingAccount = true; deletionMessage = nil; issue = nil; notice = nil
        defer { deletingAccount = false; finishAction() }
        do {
            let result = try await (useManualAppleRevocation
                ? interactor.deleteAccountWithManualAppleRevocation(account.id)
                : interactor.deleteAccount(account.id, appleAuthorizationCode: appleAuthorizationCode))
            switch result {
            case .pending:
                guard self.account?.id == account.id, self.sessionID == requestSessionID else { return }
                deletionPending = true
            case .deleted(let manualRevocation):
                guard self.account == nil || (self.account?.id == account.id && self.sessionID == requestSessionID) else { return }
                closeDeletionReview()
                deletionPending = false
                self.account = nil
                requiresManualAppleRevocation = manualRevocation
                notice = "Your account has been deleted."
            }
        } catch is CancellationError { }
        catch AccountDeletionError.appleVerificationRequired {
            guard self.account?.id == account.id, self.sessionID == requestSessionID else { return }
            deletionReview?.requiresAppleVerification = true
            deletionReview?.offersManualRevocation = appleAuthorizationCode != nil
            if appleAuthorizationCode != nil {
                deletionMessage = "Apple couldn’t verify your account. Try again, or delete your Travelants account and remove Apple access yourself."
            } else if deletionReview == nil {
                deletionMessage = AccountDeletionError.appleVerificationRequired.localizedDescription
            }
        }
        catch {
            guard self.account?.id == account.id, self.sessionID == requestSessionID else { return }
            deletionMessage = error.localizedDescription
            if let failure = error as? AccountDeletionError, case .appleAccountMismatch = failure {
                deletionReview?.requiresAppleVerification = true
                deletionReview?.offersManualRevocation = false
            }
        }
        if let pending = try? await interactor.hasPendingDeletion(), self.account?.id == account.id,
           self.sessionID == requestSessionID { deletionPending = pending }
    }

    private func isCurrent(_ review: DeletionReview) -> Bool {
        deletionReview?.id == review.id && account?.id == review.account.id && sessionID == review.sessionID && !requiresPasswordReset
    }

    private func offerManualRevocation(after failure: AuthenticationError) {
        deletionMessage = failure.localizedDescription
        deletionReview?.offersManualRevocation = true
    }

    func pollPendingDeletion() async {
        while deletionPending, deletionMessage == nil {
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return }
            guard !Task.isCancelled, deletionPending, deletionMessage == nil else { return }
            await deleteAccount()
        }
    }

    private func finishAction() {
        isBusy = false
        if let callback = queuedCallback {
            queuedCallback = nil
            Task { await self.callback(callback) }
        }
    }
    private func perform(_ action: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true; issue = nil; notice = nil
        requiresManualAppleRevocation = false
        defer { finishAction() }
        do { try await action() }
        catch is CancellationError { }
        catch { issue = .init(account: error) }
    }
}
