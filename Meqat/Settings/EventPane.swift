import MeqatCore
import MeqatCore
import SwiftUI

/// Placeholder; #18 fills it in.
struct EventPane: View {
    let eventID: EventID
    let store: SettingsStore
    let context: SettingsContext

    var body: some View { Text(eventID.displayName) }
}
