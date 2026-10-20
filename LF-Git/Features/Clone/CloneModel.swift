import Foundation
import LFKit
import Network
import os
import Observation

/// What the clone sheet asks of git; tests replace it so no process runs.
nonisolated struct CloneService: Sendable {
    var probe: @Sendable (RemoteURL, CloneCredentials?, GitCancellation) throws -> RemoteProbe
    var clone: @Sendable (CloneRequest, GitCancellation, @escaping @Sendable (CloneProgress) -> Void) throws -> URL

    static let live = CloneService(
        probe: { url, credentials, cancellation in try GitClone.probe(url, credentials: credentials, cancellation: cancellation) },
        clone: { request, cancellation, progress in try GitClone.clone(request, cancellation: cancellation, progress: progress) }
    )
}

/// The clone sheet's logic: check the address, offer the branches, ask for a login or wait for the VPN when the
/// server needs it, then clone. The view only shows `state`.
@Observable
final class CloneModel {
    enum State: Equatable {
        /// No usable address yet.
        case idle
        case probing
        /// The address is right and the branches are known.
        case ready
        case needsLogin
        /// The server cannot be reached (offline, VPN off): trying again until it can.
        case waitingForNetwork
        case cloning(CloneProgress?)
        case done(URL)
    }

    var urlText = ""
    private(set) var parent: URL?
    private(set) var folderName = ""
    var selectedBranch: String?
    var includesAllBranches = false
    var recurseSubmodules = false
    var shallow = false
    var username = ""
    var password = ""
    var remembersLogin = true

    private(set) var state = State.idle
    private(set) var found: RemoteProbe?
    /// Why the address is not usable, once the user has typed something.
    private(set) var urlProblem: String?
    /// What went wrong on the last attempt (a refused login, a failed clone).
    private(set) var message: String?
    private(set) var url: RemoteURL?

    private let service: CloneService
    private let accounts: GitAccountsModel
    private let debounce: Duration
    private let retryDelays: [Duration]
    private var generation = 0
    private var folderWasEdited = false
    /// A login typed in the sheet, kept in memory for the clone that follows.
    private var activeCredentials: CloneCredentials?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var cancellation: GitCancellation?
    @ObservationIgnored private var pathMonitor: NWPathMonitor?

    init(service: CloneService = .live, accounts: GitAccountsModel = GitAccountsModel(),
         debounce: Duration = .milliseconds(600), retryDelays: [Duration] = [.seconds(3), .seconds(5), .seconds(8), .seconds(10)]) {
        self.service = service
        self.accounts = accounts
        self.debounce = debounce
        self.retryDelays = retryDelays
    }

    // MARK: - What the sheet may do

    var host: String? { url?.host }
    var isSSH: Bool { url?.transport == .ssh }
    var isWorking: Bool {
        if case .cloning = state { return true }
        return false
    }

    var folderNameIsValid: Bool {
        let name = folderName.trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && !name.contains("/") && name != "." && name != ".." && !name.hasPrefix("-")
    }

    /// The folder the clone would create, when it is already taken.
    var destinationProblem: String? {
        guard let parent, folderNameIsValid else { return nil }
        let target = parent.appendingPathComponent(folderName.trimmingCharacters(in: .whitespaces))
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        let isEmpty = (try? FileManager.default.contentsOfDirectory(atPath: target.path))?.isEmpty == true
        return isEmpty ? nil : CloneProblem.destinationNotEmpty(target.path).errorDescription
    }

    var canClone: Bool { state == .ready && parent != nil && folderNameIsValid && destinationProblem == nil }
    var canSignIn: Bool { state == .needsLogin && !username.isEmpty && !password.isEmpty }

    func chooseParent(_ folder: URL) {
        parent = folder
    }

    // MARK: - The address

    /// Call when `urlText` changes: checks the address after a short pause, so typing does not hit the server.
    func urlChanged() {
        stopWork()
        generation += 1
        found = nil
        selectedBranch = nil
        message = nil
        activeCredentials = nil
        let text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            url = nil
            urlProblem = nil
            state = .idle
            return
        }
        do {
            let parsed = try RemoteURL.parse(text)
            url = parsed
            urlProblem = nil
            fillFolderName(parsed.repositoryName)
            // A login typed into the address is used as if it had been typed in the form.
            if let password = parsed.embeddedPassword {
                activeCredentials = CloneCredentials(username: parsed.embeddedUsername ?? "", password: password)
            }
            probe(after: debounce)
        } catch {
            url = nil
            urlProblem = error.errorDescription
            state = .idle
        }
    }

    private func fillFolderName(_ name: String) {
        guard !folderWasEdited else { return }
        folderName = name
    }

    /// The user typed a folder name: stop following the address.
    func editFolderName(_ name: String) {
        folderName = name
        folderWasEdited = true
    }

    // MARK: - Checking the server

    private func probe(after delay: Duration?, attempt: Int = 0) {
        guard let url else { return }
        let credentials = activeCredentials
        let current = generation
        state = .probing
        task = Task { [weak self] in
            if let delay { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await self?.runProbe(url, credentials, generation: current, attempt: attempt)
        }
    }

    private func runProbe(_ url: RemoteURL, _ credentials: CloneCredentials?, generation current: Int, attempt: Int) async {
        let token = GitCancellation()
        cancellation = token
        let service = service
        let outcome = await Self.probe(service, url, credentials, token)
        guard current == generation, !Task.isCancelled else { return }
        switch outcome {
        case .success(let result):
            found = result
            selectedBranch = result.defaultBranch ?? result.branches.first
            message = nil
            stopWatchingNetwork()
            state = .ready
            rememberLoginIfAsked()
        case .failure(let error):
            handle(error, url: url, credentials: credentials, attempt: attempt)
        }
    }

    private func handle(_ error: GitError, url: RemoteURL, credentials: CloneCredentials?, attempt: Int) {
        switch RemoteFailure.classify(error) {
        case .needsLogin:
            stopWatchingNetwork()
            if credentials != nil {
                message = url.transport == .ssh ? nil : "The server refused that login. Check the user name and the token or password."
                activeCredentials = nil
            }
            if username.isEmpty, let host = url.host { username = accounts.account(forHost: host)?.username ?? "" }
            state = .needsLogin
        case .unreachable:
            state = .waitingForNetwork
            watchNetwork()
            scheduleRetry(url, credentials, attempt: attempt)
        case .notFound:
            stopWatchingNetwork()
            message = "There is no repository at this address, or your account cannot see it."
            state = .idle
        case .other(let text):
            stopWatchingNetwork()
            message = text.isEmpty ? "The server did not answer as a git server." : text
            state = .idle
        }
    }

    private func scheduleRetry(_ url: RemoteURL, _ credentials: CloneCredentials?, attempt: Int) {
        let current = generation
        let delay = retryDelays[min(attempt, retryDelays.count - 1)]
        task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.runProbe(url, credentials, generation: current, attempt: attempt + 1)
        }
    }

    /// Tries now instead of waiting for the next scheduled attempt.
    func retryNow() {
        guard state == .waitingForNetwork, let url else { return }
        task?.cancel()
        cancellation?.cancel()
        let credentials = activeCredentials
        let current = generation
        task = Task { [weak self] in await self?.runProbe(url, credentials, generation: current, attempt: 0) }
    }

    func stopWaiting() {
        stopWork()
        generation += 1
        state = .idle
    }

    /// The sign-in form's button.
    func signIn() {
        guard canSignIn else { return }
        stopWork()
        generation += 1
        message = nil
        activeCredentials = CloneCredentials(username: username, password: password)
        probe(after: nil)
    }

    /// The network coming back is a better moment to try than the timer.
    private func watchNetwork() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        let isFirstReport = OSAllocatedUnfairLock(initialState: true)
        monitor.pathUpdateHandler = { [weak self] path in
            // The first report is the current state, not a change.
            if isFirstReport.withLock({ let first = $0; $0 = false; return first }) { return }
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.retryNow() }
        }
        monitor.start(queue: DispatchQueue(label: "lfgit.clone.network"))
        pathMonitor = monitor
    }

    private func stopWatchingNetwork() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    private func rememberLoginIfAsked() {
        guard remembersLogin, url?.transport == .http, let host = url?.host, let credentials = activeCredentials,
              !credentials.username.isEmpty, !credentials.password.isEmpty else { return }
        accounts.remember(host: host, username: credentials.username, password: credentials.password)
    }

    // MARK: - Cloning

    func clone() {
        guard canClone, let url, let parent else { return }
        let request = CloneRequest(
            url: url, parent: parent, folderName: folderName.trimmingCharacters(in: .whitespaces),
            branch: found?.branches.isEmpty == false ? selectedBranch : nil, singleBranch: !includesAllBranches,
            recurseSubmodules: recurseSubmodules, shallow: shallow, credentials: activeCredentials)
        let current = generation
        let token = GitCancellation()
        cancellation = token
        message = nil
        state = .cloning(nil)
        let service = service
        task = Task { [weak self] in
            let outcome = await Self.clone(service, request, token) { progress in
                Task { @MainActor in self?.updateProgress(progress, generation: current) }
            }
            self?.finishClone(outcome, generation: current)
        }
    }

    private func updateProgress(_ progress: CloneProgress, generation current: Int) {
        guard current == generation, case .cloning = state else { return }
        state = .cloning(progress)
    }

    private func finishClone(_ outcome: Result<URL, GitError>, generation current: Int) {
        guard current == generation else { return }
        switch outcome {
        case .success(let destination):
            rememberLoginIfAsked()
            state = .done(destination)
        case .failure(let error):
            if error == .cancelled {
                state = .ready
            } else if RemoteFailure.classify(error) == .needsLogin {
                message = nil
                state = .needsLogin
            } else {
                message = RemoteFailure.classify(error) == .unreachable
                    ? "The server stopped answering. If it needs a VPN, check the connection and clone again."
                    : error.description
                state = .ready
            }
        }
    }

    // MARK: - Stopping

    /// Stops whatever is running (the Cancel button during a clone).
    func cancel() {
        guard isWorking else { return }
        cancellation?.cancel()
    }

    /// The sheet is closing: nothing may keep running.
    func close() {
        generation += 1
        stopWork()
    }

    private func stopWork() {
        task?.cancel()
        task = nil
        cancellation?.cancel()
        cancellation = nil
        stopWatchingNetwork()
    }

    // MARK: - Work off the main thread

    /// Where the blocking git calls run. A dispatch queue grows its threads on demand; the cooperative pool Swift
    /// concurrency uses is only as wide as the CPU, and a few waiting git processes would starve everything else.
    nonisolated private static let blockingWork = DispatchQueue(label: "lfgit.clone.git", qos: .userInitiated, attributes: .concurrent)

    nonisolated private static func onBlockingQueue<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            blockingWork.async { continuation.resume(returning: work()) }
        }
    }

    nonisolated private static func probe(_ service: CloneService, _ url: RemoteURL, _ credentials: CloneCredentials?,
                                          _ token: GitCancellation) async -> Result<RemoteProbe, GitError> {
        await onBlockingQueue {
            do { return .success(try service.probe(url, credentials, token)) } catch let error as GitError { return .failure(error) } catch {
                return .failure(.launchFailed("\(error)"))
            }
        }
    }

    nonisolated private static func clone(_ service: CloneService, _ request: CloneRequest, _ token: GitCancellation,
                                          _ progress: @escaping @Sendable (CloneProgress) -> Void) async -> Result<URL, GitError> {
        await onBlockingQueue {
            do { return .success(try service.clone(request, token, progress)) } catch let error as GitError { return .failure(error) } catch {
                return .failure(.launchFailed(error.localizedDescription))
            }
        }
    }
}
