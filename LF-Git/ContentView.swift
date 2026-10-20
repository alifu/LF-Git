import SwiftUI

struct ContentView: View {
    let app: AppModel

    var body: some View {
        Group {
            if let repository = app.repository {
                RepositoryView(repository: repository, app: app)
            } else {
                DashboardView(app: app)
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .sheet(isPresented: Binding(get: { app.showsClone }, set: { app.showsClone = $0 })) {
            CloneSheet(app: app)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { app.errorMessage != nil },
            set: { if !$0 { app.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? "")
        }
    }
}

#Preview("Light") {
    ContentView(app: AppModel()).preferredColorScheme(.light)
}

#Preview("Dark") {
    ContentView(app: AppModel()).preferredColorScheme(.dark)
}
