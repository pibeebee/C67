import SwiftUI

struct AccountView: View {
    @Bindable var presenter: AccountPresenter
    @Environment(\.dismiss) private var dismiss
    @State private var form = AccountFormState()

    var body: some View {
        NavigationStack {
            Form {
                if presenter.isBusy { ProgressView("Updating account…") }
                if presenter.requiresPasswordReset {
                    passwordReset
                } else if let account = presenter.account {
                    Section("Traveller account") {
                        Text(account.email ?? "Signed in")
                        Button("Sign out", role: .destructive) { Task { await presenter.signOut() } }
                    }
                    Section("Security") {
                        Text("Sign out and use Forgot password to request a recovery link when you need to reset your password.")
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
                if let notice = presenter.notice { Section("Account status") { Text(notice) } }
                if let error = presenter.error {
                    Section("Account status") {
                        Text(error)
                        Button("Check session again") { Task { await presenter.restore(force: true) } }
                    }
                }
            }
            .disabled(presenter.isBusy)
            .navigationTitle("Account")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { form.clearPasswords(); dismiss() } } }
            .task { await presenter.restore() }
            .onChange(of: presenter.screen) { _, _ in form.clearPasswords() }
            .onChange(of: presenter.requiresPasswordReset) { _, _ in form.clearPasswords() }
            .onChange(of: presenter.account?.id) { _, _ in form.clearPasswords() }
        }
        .onDisappear { form.clearPasswords() }
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
                        .textContentType(.username).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Email address").accessibilityIdentifier("authEmail")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                if presenter.screen != .recovery {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password").font(.subheadline)
                        SecureField("Password", text: $form.password)
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
            SecureField("New password", text: $form.password).textContentType(.newPassword)
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
