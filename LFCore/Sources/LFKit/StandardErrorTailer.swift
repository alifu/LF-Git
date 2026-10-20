import Foundation

/// Hands out what a running command writes to its error file, a few times a second.
final class StandardErrorTailer: @unchecked Sendable {
    private static let interval: DispatchTimeInterval = .milliseconds(150)
    private let queue = DispatchQueue(label: "lfgit.stderr-tailer")
    private let timer: DispatchSourceTimer
    private let reader: FileHandle?
    private let deliver: @Sendable (String) -> Void

    init(file: URL, deliver: @escaping @Sendable (String) -> Void) {
        self.deliver = deliver
        reader = try? FileHandle(forReadingFrom: file)
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.interval, repeating: Self.interval)
        timer.setEventHandler { [weak self] in self?.drain() }
        timer.resume()
    }

    /// Stops the timer and delivers whatever is left.
    func finish() {
        timer.cancel()
        queue.sync { drain() }
        try? reader?.close()
    }

    private func drain() {
        guard let data = try? reader?.readToEnd(), !data.isEmpty else { return }
        deliver(String(decoding: data, as: UTF8.self))
    }
}
