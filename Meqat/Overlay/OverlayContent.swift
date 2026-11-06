import Foundation
import MeqatCore

struct OverlayContent: Equatable {
    let eventName: String
    let start: Date
    let end: Date
    let timeoutSeconds: Int
    let timeFormat: TimeFormat
    /// The alert's title for End and Pre-warning alerts; `nil` keeps the plain layout.
    let kindLine: String?
}
