import Foundation

/// A fake clock: `sleep` suspends until `advance(by:)` moves time past its deadline.
actor ManualSleeper {
    private var elapsed: Duration = .zero
    private var sleepers: [(deadline: Duration, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var requestedDurations: [Duration] = []

    func sleep(_ duration: Duration) async {
        requestedDurations.append(duration)
        let deadline = elapsed + duration
        await withCheckedContinuation { sleepers.append((deadline, $0)) }
    }

    func advance(by duration: Duration) {
        elapsed += duration
        let due = sleepers.filter { $0.deadline <= elapsed }
        sleepers.removeAll { $0.deadline <= elapsed }
        due.forEach { $0.continuation.resume() }
    }
}
