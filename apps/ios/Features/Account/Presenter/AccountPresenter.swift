import Foundation
import Observation
import C67Domain

@MainActor @Observable
final class AccountPresenter {
    enum Screen: String, CaseIterable { case signIn = "Sign in", signUp = "Create account", recovery = "Forgot password" }
    private(set) var account: TravellerAccount?
    private(set) var requiresPasswordReset = false
    private(set) var pendingEmail: String?
    private(set) var pendingRecovery = false
    private(set) var isBusy = false
    private(set) var hasRestored = false
    var screen: Screen = .signIn
    var error: String?
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
            account = value.account
            requiresPasswordReset = value.requiresPasswordReset
            pendingEmail = value.pendingEmail
            pendingRecovery = value.pendingRecovery
            if value.isRestored { hasRestored = true }
            onSessionChange?(value)
        }
    }
    func restore(force: Bool = false) async {
        guard !isBusy else { return }
        isBusy = true
        defer { finishAction(); hasRestored = true }
        do {
            account = try await (force ? interactor.refresh() : interactor.restore())
            // Opening Account or returning to the foreground must not erase callback feedback.
            if force { error = nil }
        }
        catch is CancellationError { }
        catch AuthenticationError.sessionExpired { account = nil; error = AuthenticationError.sessionExpired.localizedDescription }
        catch AuthenticationError.remoteSignOutFailed { account = nil; error = AuthenticationError.remoteSignOutFailed.localizedDescription }
        catch { self.error = error.localizedDescription }
    }
    func signIn(email: String, password: String) async {
        await perform { self.account = try await self.interactor.signIn(email: email, password: password) }
    }
    func signInWithApple(_ credentials: AppleSignInCredentials) async {
        await perform { self.account = try await self.interactor.signInWithApple(credentials) }
    }
    func appleAuthorizationFailed(_ failure: AuthenticationError) {
        guard !isBusy else { return }
        error = failure.localizedDescription; notice = nil
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
    private func finishAction() {
        isBusy = false
        if let callback = queuedCallback {
            queuedCallback = nil
            Task { await self.callback(callback) }
        }
    }
    private func perform(_ action: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true; error = nil; notice = nil
        defer { finishAction() }
        do { try await action() }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}
