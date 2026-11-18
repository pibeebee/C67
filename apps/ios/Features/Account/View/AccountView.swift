import SwiftUI

struct AccountView: View {
    @Bindable var presenter: AccountPresenter
    var appleOnly = false
    @Environment(\.dismiss) private var dismiss
    private enum Field: Hashable { case email, password, newPassword }
    @FocusState private var focusedField: Field?
    @State private var form = AccountFormState()
    @State private var confirmsDeletion = false

    var body: some View {
        NavigationStack {
            Form {
                if presenter.isBusy {
                    ProgressView(presenter.deletingAccount ? "Checking account deletion…" : "Updating account…")
                }
                if appleOnly && !presenter.requiresPasswordReset { ItineraryMethodSection() }
                if presenter.requiresPasswordReset {
                    passwordReset
                } else if let account = presenter.account {
                    Section("Traveller account") {
                        Text(account.email ?? "Signed in")
                        Button("Sign out", role: .destructive) { Task { await presenter.signOut() } }
                            .disabled(presenter.deletionPending)
                    }
                    if !appleOnly {
                        Section("Security") {
                            Text("Sign out and use Forgot password to request a recovery link when you need to reset your password.")
                        }
                    }
                } else if presenter.hasRestored {
                    credentials
                    if let pending = presenter.pendingEmail {
                        Section(presenter.pendingRecovery ? "Recovery requested" : "Confirmation requested") {
                            Text("Check the email sent to \(pending). Open the newest link on this device.")
                            if !presenter.pendingRecovery {
                                Button("Resend confirmation") { Task { await presenter.resend() } }
                            }
                            Button("Cancel email request") { Task { await presenter.cancelEmailFlow() } }
                        }
                    }
                }
                if presenter.account != nil, presenter.supportsAccountDeletion, !presenter.requiresPasswordReset {
                    Section {
                        if presenter.deletionPending || presenter.deletionMessage != nil {
                            RecoveryNotice(title: presenter.deletionPending ? "Account deletion" : "Couldn’t delete account",
                                           message: presenter.deletionMessage ?? "Your deletion request is being processed.",
                                           primary: presenter.deletionPending
                                               ? .init(title: "Check status") { Task { await presenter.deleteAccount() } }
                                               : nil)
                        }
                        if !presenter.deletionPending {
                            Button("Delete account", role: .destructive) { confirmsDeletion = true }
                                .accessibilityIdentifier("deleteAccount")
                        }
                    }
                }
                if let notice = presenter.notice { Section("Account status") { Text(notice) } }
                if let issue = presenter.issue {
                    Section {
                        RecoveryNotice(title: "Account needs attention", message: issue.message,
                                       primary: recovery(for: issue))
                    }
                }
            }
            .disabled(presenter.isBusy)
            .navigationTitle("Account")
            .confirmationDialog("Delete your account?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
                Button("Delete account permanently", role: .destructive) { Task { await presenter.deleteAccount() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your Travelant account and associated data, including trips saved on this device, will be permanently deleted.")
            }
            .sheet(isPresented: $presenter.verifiesAppleForDeletion) {
                verifyAppleForDeletion
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { form.clearPasswords(); dismiss() } } }
            .task { await presenter.restore() }
            .task(id: presenter.deletionPending) {
                while presenter.deletionPending, presenter.deletionMessage == nil {
                    do { try await Task.sleep(for: .seconds(5)) }
                    catch { return }
                    guard !Task.isCancelled, presenter.deletionPending, presenter.deletionMessage == nil else { return }
                    await presenter.deleteAccount()
                }
            }
            .onChange(of: presenter.screen) { _, _ in form.clearPasswords() }
            .onChange(of: presenter.requiresPasswordReset) { _, _ in form.clearPasswords() }
            .onChange(of: presenter.account?.id) { _, _ in form.clearPasswords() }
        }
        .onDisappear { form.clearPasswords() }
    }
    private var verifyAppleForDeletion: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Use the Apple Account you signed in with to confirm deletion.")
                    .foregroundStyle(.secondary)
                AppleSignInButtonView(verifyingDeletion: true) { result in
                    switch result {
                    case .success(let credentials):
                        guard let code = credentials.authorizationCode else {
                            presenter.appleDeletionAuthorizationFailed(.invalidAppleCredential)
                            return
                        }
                        Task { await presenter.deleteAccount(appleAuthorizationCode: code) }
                    case .failure(let error):
                        presenter.appleDeletionAuthorizationFailed(error)
                    }
                }
                .disabled(presenter.isBusy)
                if presenter.isBusy { ProgressView("Confirming with Apple…") }
                if let message = presenter.deletionMessage {
                    RecoveryNotice(title: "Account deletion needs attention", message: message)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Confirm with Apple")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presenter.verifiesAppleForDeletion = false }.disabled(presenter.isBusy)
                }
            }
            .interactiveDismissDisabled(presenter.isBusy)
        }
    }

    private func recovery(for issue: PresentationIssue) -> RecoveryNotice.Action? {
        switch issue.recovery {
        case .checkSession: .init(title: "Check session again") { Task { await presenter.restore(force: true) } }
        case .editCredentials:
            .init(title: "Edit details") {
                switch issue.cause {
                case .authentication(.invalidEmail): focusedField = .email
                default: focusedField = presenter.requiresPasswordReset ? .newPassword : .password
                }
            }
        case .requestLink where !appleOnly:
            .init(title: "Request a new link") {
                if let email = presenter.pendingEmail, presenter.pendingRecovery {
                    Task { await presenter.recover(email: email) }
                } else if presenter.pendingEmail != nil, issue.cause == .authentication(.emailNotConfirmed) {
                    Task { await presenter.resend() }
                } else {
                    presenter.screen = presenter.pendingRecovery || presenter.requiresPasswordReset ||
                        issue.cause == .authentication(.reauthenticationRequired) ? .recovery : .signUp
                    if let email = presenter.pendingEmail { form.email = email }
                    focusedField = .email
                }
            }
        case .signIn where !appleOnly: .init(title: "Sign in") { presenter.screen = .signIn; focusedField = .email }
        default: nil
        }
    }

    private var credentials: some View {
        Group {
            Section {
                AppleSignInButtonView { result in
                    form.clearPasswords()
                    switch result {
                    case .success(let credentials): Task { await presenter.signInWithApple(credentials) }
                    case .failure(let error): presenter.appleAuthorizationFailed(error)
                    }
                }
            } footer: { Text("Use your Apple Account or sign in with email below. Hide My Email is supported.") }
            Section {
                Picker("Account action", selection: $presenter.screen) {
                    ForEach(AccountPresenter.Screen.allCases, id: \.self) { screen in Text(screen.rawValue).tag(screen) }
                }.pickerStyle(.menu).accessibilityIdentifier("authAction")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email").font(.subheadline)
                    TextField("Email address", text: $form.email)
                        .focused($focusedField, equals: .email)
                        .textContentType(.username).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Email address").accessibilityIdentifier("authEmail")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                if presenter.screen != .recovery {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password").font(.subheadline)
                        SecureField("Password", text: $form.password)
                            .focused($focusedField, equals: .password)
                            .textContentType(presenter.screen == .signUp ? .newPassword : .password)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityLabel("Password").accessibilityIdentifier("authPassword")
                            .frame(minHeight: 44)
                    }
                }
                if presenter.screen == .signUp {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm password").font(.subheadline)
                        SecureField("Confirm password", text: $form.confirmation).textContentType(.newPassword)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityLabel("Confirm password").accessibilityIdentifier("authConfirmation")
                            .frame(minHeight: 44)
                    }
                    Text("Use at least 8 characters.").font(.footnote)
                    if !form.confirmation.isEmpty && form.password != form.confirmation {
                        Text("Passwords do not match.").font(.footnote)
                    }
                }
                Button(actionTitle) { submit() }
                    .accessibilityIdentifier("authSubmit")
                    .disabled(!form.canSubmit(presenter.screen))
            } header: { Text(presenter.screen.rawValue) }
                footer: { Text("Traveller accounts are separate from Supabase Studio. Confirmation and recovery links must be opened on the device that requested them.") }
        }
    }
    private var passwordReset: some View {
        Section {
            SecureField("New password", text: $form.password).textContentType(.newPassword).focused($focusedField, equals: .newPassword)
            SecureField("Confirm new password", text: $form.confirmation).textContentType(.newPassword)
            Text("Use at least 8 characters.").font(.footnote)
            Button("Set new password") {
                let submitted = form.password
                form.clearPasswords()
                Task { await presenter.updatePassword(submitted) }
            }.disabled(!form.canResetPassword)
            Button("Cancel recovery", role: .cancel) { Task { await presenter.signOut() } }
        } header: { Text("Set a new password") }
            footer: { Text("Finish resetting your password before accessing your trips.") }
    }
    private var actionTitle: String {
        presenter.screen == .recovery ? "Send recovery email" : presenter.screen.rawValue
    }
    private func submit() {
        let submittedPassword = form.password
        let submittedEmail = form.email
        let action = presenter.screen
        form.clearPasswords()
        Task {
            switch action {
            case .signIn: await presenter.signIn(email: submittedEmail, password: submittedPassword)
            case .signUp: await presenter.signUp(email: submittedEmail, password: submittedPassword)
            case .recovery: await presenter.recover(email: submittedEmail)
            }
        }
    }
}
