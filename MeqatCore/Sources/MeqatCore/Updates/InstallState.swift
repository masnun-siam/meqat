/// Where a running install is. In memory only; `idle` also covers "an update is available" (the checker owns that).
public enum InstallState: Sendable, Equatable {
    case idle
    case downloading(percent: Int)
    case verifying
    case installing
    case relaunching
    case failed

    /// An install is under way: from the first download byte until the app quits to relaunch.
    public var isRunning: Bool {
        switch self {
        case .downloading, .verifying, .installing, .relaunching: return true
        case .idle, .failed: return false
        }
    }
}
