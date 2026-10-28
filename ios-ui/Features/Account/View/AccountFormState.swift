import Foundation

/// Ephemeral presentation input; passwords are never persisted by the form.
struct AccountFormState {
    var email = ""
    var password = ""
    var confirmation = ""
    var canResetPassword: Bool { password.count >= 8 && password == confirmation }
    func canSubmit(_ screen: AccountPresenter.Screen) -> Bool {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch screen {
        case .signIn: return !password.isEmpty
        case .signUp: return canResetPassword
        case .recovery: return true
        }
    }
    mutating func clearPasswords() { password = ""; confirmation = "" }
}
