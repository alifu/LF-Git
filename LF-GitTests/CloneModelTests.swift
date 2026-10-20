import Foundation
import LFKit
import Testing
@testable import LF_Git

/// A scripted server: each probe takes the next prepared answer (the last one repeats).
private final class FakeServer: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [Result<RemoteProbe, GitError>]
    private(set) var probedCredentials: [CloneCredentials?] = []
    private(set) var probedURLs: [String] = []
    private(set) var requests: [CloneRequest] = []
    var cloneResult: Result<URL, GitError> = .success(URL(fileURLWithPath: "/tmp/cloned"))
    var cloneWaitsForCancel = false

    init(_ answers: [Result<RemoteProbe, GitError>]) { self.answers = answers }

    func service() -> CloneService {
        CloneService(
            probe: { url, credentials, _ in
                try self.lock.withLock {
                    self.probedURLs.append(url.text)
                    self.probedCredentials.append(credentials)
                    let answer = self.answers.count > 1 ? self.answers.removeFirst() : self.answers[0]
                    return try answer.get()
                }
            },
            clone: { request, cancellation, progress in
                self.lock.withLock { self.requests.append(request) }
                progress(CloneProgress(phase: "Receiving objects", percent: 50))
                while self.cloneWaitsForCancel, !cancellation.isCancelled { Thread.sleep(forTimeInterval: 0.01) }
                if cancellation.isCancelled { throw GitError.cancelled }
                return try self.cloneResult.get()
            })
    }
}

private let reachable = Result<RemoteProbe, GitError>.success(RemoteProbe(branches: ["main", "dev"], defaultBranch: "main"))
private let offline = Result<RemoteProbe, GitError>.failure(
    .failed(arguments: ["ls-remote"], status: 128, stderr: "fatal: unable to access 'https://h/': Could not resolve host: h"))
private let loginNeeded = Result<RemoteProbe, GitError>.failure(
    .failed(arguments: ["ls-remote"], status: 128, stderr: "fatal: could not read Username for 'https://h': terminal prompts disabled"))

@MainActor
@Suite("Clone sheet logic")
struct CloneModelTests {
    private func makeModel(_ server: FakeServer) -> CloneModel {
        let defaults = UserDefaults(suiteName: "lfgit-clone-\(UUID().uuidString)")!
        return CloneModel(service: server.service(), accounts: GitAccountsModel(defaults: defaults),
                          debounce: .milliseconds(10), retryDelays: [.milliseconds(20)])
    }

    /// Waits by counting turns, not by the clock: other suites can hold the main actor for seconds, and a clock
    /// deadline would pass while the model had no chance to run.
    private func wait(_ model: CloneModel, for expected: CloneModel.State, turns: Int = 3_000) async -> Bool {
        for _ in 0..<turns {
            if model.state == expected { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return model.state == expected
    }

    private func wait(turns: Int = 3_000, until condition: () -> Bool) async -> Bool {
        for _ in 0..<turns {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test("a valid address leads to the branches with the default one chosen and the folder named")
    func ready() async {
        let model = makeModel(FakeServer([reachable]))

        model.urlText = "https://example.com/team/app.git"
        model.urlChanged()

        #expect(await wait(model, for: .ready))
        #expect(model.found?.branches == ["main", "dev"])
        #expect(model.selectedBranch == "main")
        #expect(model.folderName == "app")
    }

    @Test("an address git cannot use is explained and never probed")
    func invalidAddress() async {
        let server = FakeServer([reachable])
        let model = makeModel(server)

        model.urlText = "-oProxyCommand=evil"
        model.urlChanged()
        try? await Task.sleep(for: .milliseconds(80))

        #expect(model.state == .idle)
        #expect(model.urlProblem != nil)
        #expect(server.probedURLs.isEmpty)
    }

    @Test("an answer for an address that was replaced is dropped")
    func staleAnswer() async {
        let server = FakeServer([reachable])
        let model = makeModel(server)
        model.urlText = "https://example.com/first.git"
        model.urlChanged()

        model.urlText = "https://example.com/second.git"
        model.urlChanged()

        #expect(await wait(model, for: .ready))
        #expect(model.folderName == "second")
        #expect(!server.probedURLs.contains("https://example.com/first.git"))
    }

    @Test("an unreachable server is retried until it answers")
    func waitsForTheVPN() async {
        let server = FakeServer([offline, offline, reachable])
        let model = makeModel(server)

        model.urlText = "https://vpn.example.com/team/app.git"
        model.urlChanged()

        #expect(await wait(model, for: .waitingForNetwork))
        #expect(await wait(model, for: .ready))
        #expect(server.probedURLs.count == 3)
    }

    @Test("stopping the wait ends the retries")
    func stopWaiting() async {
        let server = FakeServer([offline])
        let model = makeModel(server)
        model.urlText = "https://vpn.example.com/team/app.git"
        model.urlChanged()
        #expect(await wait(model, for: .waitingForNetwork))

        model.stopWaiting()
        let probes = server.probedURLs.count
        try? await Task.sleep(for: .milliseconds(150))

        #expect(model.state == .idle)
        #expect(server.probedURLs.count == probes)
    }

    @Test("a server that wants a login gets the sign-in form, and the typed login is used")
    func signIn() async {
        let server = FakeServer([loginNeeded, reachable])
        let model = makeModel(server)
        model.urlText = "https://git.example.com/team/app.git"
        model.urlChanged()
        #expect(await wait(model, for: .needsLogin))
        #expect(!model.canSignIn)

        model.username = "me"
        model.password = "token"
        model.remembersLogin = false
        model.signIn()

        #expect(await wait(model, for: .ready))
        #expect(server.probedCredentials.last == CloneCredentials(username: "me", password: "token"))
    }

    @Test("a refused login returns to the form with a message")
    func wrongPassword() async {
        let model = makeModel(FakeServer([loginNeeded]))
        model.urlText = "https://git.example.com/team/app.git"
        model.urlChanged()
        #expect(await wait(model, for: .needsLogin))
        model.username = "me"
        model.password = "wrong"

        model.signIn()

        #expect(await wait { model.message?.contains("refused") == true })
        #expect(model.state == .needsLogin)
    }

    @Test("a login typed into the address is used without showing the form")
    func loginInAddress() async {
        let server = FakeServer([reachable])
        let model = makeModel(server)

        model.urlText = "https://me:token@git.example.com/team/app.git"
        model.urlChanged()

        #expect(await wait(model, for: .ready))
        #expect(server.probedURLs == ["https://git.example.com/team/app.git"])
        #expect(server.probedCredentials.first == CloneCredentials(username: "me", password: "token"))
    }

    @Test("cloning needs a folder, then runs with the chosen branch")
    func clones() async {
        let server = FakeServer([reachable])
        let model = makeModel(server)
        model.urlText = "https://example.com/team/app.git"
        model.urlChanged()
        #expect(await wait(model, for: .ready))
        #expect(!model.canClone)

        model.chooseParent(URL(fileURLWithPath: "/tmp/lfgit-clone-parent-that-does-not-exist"))
        model.selectedBranch = "dev"
        model.clone()

        #expect(await wait(model, for: .done(URL(fileURLWithPath: "/tmp/cloned"))))
        #expect(server.requests.first?.branch == "dev")
        #expect(server.requests.first?.folderName == "app")
    }

    @Test("stopping a clone goes back to the form")
    func cancelClone() async {
        let server = FakeServer([reachable])
        server.cloneWaitsForCancel = true
        let model = makeModel(server)
        model.urlText = "https://example.com/team/app.git"
        model.urlChanged()
        #expect(await wait(model, for: .ready))
        model.chooseParent(URL(fileURLWithPath: "/tmp/lfgit-clone-parent-that-does-not-exist"))
        model.clone()
        #expect(await wait(model, for: .cloning(CloneProgress(phase: "Receiving objects", percent: 50))))

        model.cancel()

        #expect(await wait(model, for: .ready))
        #expect(model.message == nil)
    }

    @Test("a failed clone says why and keeps the form")
    func cloneFails() async {
        let server = FakeServer([reachable])
        server.cloneResult = .failure(.failed(arguments: ["clone"], status: 128, stderr: "fatal: disk full"))
        let model = makeModel(server)
        model.urlText = "https://example.com/team/app.git"
        model.urlChanged()
        #expect(await wait(model, for: .ready))
        model.chooseParent(URL(fileURLWithPath: "/tmp/lfgit-clone-parent-that-does-not-exist"))

        model.clone()

        #expect(await wait { model.message?.contains("disk full") == true })
        #expect(model.state == .ready)
    }

    @Test("an empty repository clones without a branch")
    func emptyRepository() async {
        let server = FakeServer([.success(RemoteProbe(branches: [], defaultBranch: nil))])
        let model = makeModel(server)
        model.urlText = "https://example.com/team/empty.git"
        model.urlChanged()
        #expect(await wait(model, for: .ready))
        model.chooseParent(URL(fileURLWithPath: "/tmp/lfgit-clone-parent-that-does-not-exist"))

        model.clone()

        #expect(await wait(model, for: .done(URL(fileURLWithPath: "/tmp/cloned"))))
        #expect(server.requests.first?.branch == nil)
    }
}
