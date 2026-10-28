import Foundation
import MeqatCore

struct OverlayContent: Equatable {
    let eventName: String
    let start: Date
    let end: Date
    let holdSeconds: Int
    let timeFormat: TimeFormat
}
