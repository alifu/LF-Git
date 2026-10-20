import SwiftUI

/// Asked for when the server wants a login: user name, password or access token, and whether to keep it.
struct CloneCredentialForm: View {
    @Bindable var model: CloneModel

    var body: some View {
        Section {
            if model.isSSH {
                Label("This server wants an SSH key. Load yours with `ssh-add` in a terminal, then try again.", systemImage: "key")
                    .foregroundStyle(.theme(.textSubtle))
                Button("Try Again") { model.urlChanged() }
                    .accessibilityIdentifier("clone-retry")
            } else {
                Text("Sign in to \(model.host ?? "the server")")
                    .font(.headline)
                TextField("Username", text: $model.username)
                    .textContentType(.username)
                    .accessibilityIdentifier("clone-username")
                SecureField("Password or access token", text: $model.password)
                    .textContentType(.password)
                    .accessibilityIdentifier("clone-password")
                    .onSubmit { model.signIn() }
                Toggle("Remember in the keychain", isOn: $model.remembersLogin)
                    .accessibilityIdentifier("clone-remember")
                Text("GitHub, GitLab and Bitbucket want a personal access token here, not your account password.")
                    .font(.caption)
                    .foregroundStyle(.theme(.textSubtle))
                HStack {
                    Spacer()
                    Button("Sign In") { model.signIn() }
                        .disabled(!model.canSignIn)
                        .accessibilityIdentifier("clone-sign-in")
                }
            }
        } header: {
            Text("Sign in")
        }
    }
}
