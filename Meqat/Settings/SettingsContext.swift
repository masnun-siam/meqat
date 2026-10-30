import Foundation
import MeqatCore
import Observation

enum LookupStatus {
    case idle, lookingUp, found, cityNotFound, unreachable
}

/// Runtime data the panes show that isn't a setting. #21 fills it; the defaults keep the panes usable alone.
@MainActor @Observable
final class SettingsContext {
    var calculatedWindows: [EventID: DateInterval] = [:]
    var lookupStatus: LookupStatus = .idle
    var place: String?
    var coordinatesText: String?
    var lastSyncText: String?
    var updateStatus: UpdateStatus = .idle
    var lastCheckedText: String?
    var checkNow: @MainActor () -> Void = {}
}
