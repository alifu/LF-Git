import LFKit
import SwiftUI

/// Settings section for company (LDAP) logins to git servers.
struct GitAccountsSection: View {
    @State private var model = GitAccountsModel()

    var body: some View {
        Section {
            ForEach(model.accounts) { account in
                HStack {
                    Image(systemName: "person.badge.key")
                    Text(account.id)
                    Spacer()
                    Button("Remove", role: .destructive) { model.remove(account) }
                        .accessibilityIdentifier("account-remove-\(account.id)")
                }
            }
            TextField("Server", text: $model.host, prompt: Text("gitlab.company.com"))
                .accessibilityIdentifier("account-host")
            TextField("Username", text: $model.username, prompt: Text("Username (for a token: your user name or any name)"))
                .accessibilityIdentifier("account-username")
            SecureField("Password or access token", text: $model.password)
                .accessibilityIdentifier("account-password")
            HStack {
                if let message = model.message {
                    Text(message).foregroundStyle(model.isError ? .red : .secondary)
                }
                Spacer()
                Button("Add Account") { model.add() }
                    .disabled(!model.canAdd)
                    .accessibilityIdentifier("account-add")
            }
        } header: {
            Text("Git server accounts (token, password or LDAP)")
        } footer: {
            Text("For a server that signs in with a personal access token (GitHub, GitLab, Bitbucket) or your company (LDAP) account. Enter the token as the password. It is kept by git's credential helper (the macOS keychain), never by this app, so fetch, pull and push work without a prompt. A login you already made in the terminal works without adding it here.")
        }
    }
}

#Preview("Git server accounts") {
    Form { GitAccountsSection() }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
}
