import LFKit
import SwiftUI

/// The controls of the Git server accounts card (token, password or LDAP logins). The card supplies the title.
struct GitAccountsSection: View {
    @State private var model = GitAccountsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("account-host")
            TextField("Username", text: $model.username, prompt: Text("Username (for a token: your user name or any name)"))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("account-username")
            SecureField("Password or access token", text: $model.password)
                .textFieldStyle(.roundedBorder)
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
        }
    }
}

#Preview("Git server accounts") {
    SettingsPage { GitAccountsSection() }
        .frame(width: 580, height: 420)
}
