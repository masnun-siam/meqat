import Foundation

public enum SyncFailure: Equatable, Sendable {
    case cityNotFound
    case network
}

public struct SyncStatus: Equatable, Sendable {
    public var isFetching = false
    public var isWaitingToRetry = false
    public var lastSuccess: Date?
    public var offlineSince: Date?
    public var lastFailure: SyncFailure?

    public init() {}
}
