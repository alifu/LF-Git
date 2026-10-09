/// Runs git commands that change the repository one at a time.
///
/// Two `git add`/`git apply`/`git commit` at once collide on git's index lock ("index.lock exists").
/// Everything that writes goes through here; reads (status, log, diff) run freely.
actor GitWriteQueue {
    func run<T: Sendable>(_ work: @Sendable () throws -> T) throws -> T {
        try work()
    }
}
