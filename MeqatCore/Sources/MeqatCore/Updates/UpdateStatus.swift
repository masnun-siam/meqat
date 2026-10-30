import Foundation

public enum UpdateCheckTrigger: Sendable {
    case automatic, manual
}

public enum UpdateStatus: Sendable, Equatable {
    case idle
    case checking
    case upToDate(checkedAt: Date)
    case available(version: String, releaseURL: URL)
    case failed
}
