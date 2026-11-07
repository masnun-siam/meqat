/// Where a running install is. In memory only; `idle` also covers "an update is available" (the checker owns that).
public enum InstallState: Sendable, Equatable {
    case idle
    case downloading(percent: Int)
    case verifying
    case installing
    case relaunching
    case failed
}
