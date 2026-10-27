import Foundation

/// Fires `onTick` just after each wall-clock minute boundary.
@MainActor
final class MinuteTicker {
    private let onTick: @MainActor () -> Void
    private var timer: Timer?

    init(onTick: @escaping @MainActor () -> Void) {
        self.onTick = onTick
        rearm()
    }

    deinit { timer?.invalidate() }

    /// Re-aims at the next boundary; call after clock or time zone changes.
    func rearm() {
        timer?.invalidate()
        let now = Date().timeIntervalSinceReferenceDate
        let next = (now / 60).rounded(.down) * 60 + 60 + 0.05
        let timer = Timer(fire: Date(timeIntervalSinceReferenceDate: next), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onTick()
                self?.rearm()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
