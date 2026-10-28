import Foundation
import MeqatCore

struct OverlayContent: Equatable {
    let eventName: String
    let start: Date
    let end: Date
    let timeoutSeconds: Int
    let timeFormat: TimeFormat
}
