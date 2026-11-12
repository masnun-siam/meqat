import MeqatCore
import Observation
import SwiftUI

@MainActor @Observable
final class SettingsNavigation {
    var selection: SettingsPane = .general
}

struct SettingsView: View {
    @Bindable var navigation: SettingsNavigation
    let store: SettingsStore
    let context: SettingsContext

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.selection) {
                Section {
                    Text("General", tableName: "Settings").tag(SettingsPane.general)
                    Text("Location", tableName: "Settings").tag(SettingsPane.location)
                    Text("About", tableName: "Settings").tag(SettingsPane.about)
                }
                Section {
                    ForEach(EventID.allCases, id: \.self) { id in
                        Text(id.displayName(in: context.language) + (id.kind == .prohibited ? " ⛔" : "")).tag(SettingsPane.event(id))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
        } detail: {
            switch navigation.selection {
            case .general: GeneralPane(store: store, context: context)
            case .location: LocationPane(store: store, context: context)
            case .about: AboutPane(store: store, context: context)
            case .event(let id): EventPane(eventID: id, store: store, context: context)
            }
        }
        .frame(minWidth: 680, minHeight: 480)
    }
}
