import MeqatCore
import SwiftUI

struct LocationPane: View {
    @Bindable var store: SettingsStore
    let context: SettingsContext
    @State private var manualSelected: Bool
    @State private var city: String
    @State private var country: String
    @State private var state: String

    init(store: SettingsStore, context: SettingsContext) {
        self.store = store
        self.context = context
        let location = store.settings.location
        _manualSelected = State(initialValue: location.mode == .manual)
        _city = State(initialValue: location.manualCity ?? "")
        _country = State(initialValue: location.manualCountry ?? "")
        _state = State(initialValue: location.manualState ?? "")
    }

    private var normalized: (city: String, country: String, state: String?)? {
        ManualCityInput.normalized(city: city, country: country, state: state)
    }

    private var canCommit: Bool { normalized != nil && context.lookupStatus != .lookingUp }

    var body: some View {
        Form {
            Picker(selection: modeBinding) {
                Text("Automatic (uses this Mac's location)", tableName: "Location").tag(false)
                Text("Manual city", tableName: "Location").tag(true)
            } label: {
                Text("Location", tableName: "Location")
                Text("Automatic uses this Mac's location. Manual uses the city you enter.", tableName: "Location")
            }
            .pickerStyle(.radioGroup)
            if manualSelected { manualSection } else { automaticSection }
            lastSyncLine.foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var modeBinding: Binding<Bool> {
        Binding(
            get: { manualSelected },
            set: { manual in
                manualSelected = manual
                if !manual {
                    store.setLocationMode(.automatic)
                    city = ""
                    country = ""
                    state = ""
                } else if store.settings.location.manualCity != nil {
                    store.settings.location.mode = .manual
                }
            })
    }

    private var lastSyncLine: Text {
        guard let text = context.lastSyncText else { return Text("Last sync: never", tableName: "Location") }
        return Text("Last sync: \(text)", tableName: "Location")
    }

    private var automaticSection: some View {
        Section {
            Text("Current place: \(context.place ?? "—")", tableName: "Location")
            if let coordinates = context.coordinatesText { Text(coordinates).foregroundStyle(.secondary) }
        }
    }

    private var manualSection: some View {
        Section {
            TextField(String(localized: "City", table: "Location"), text: $city).onSubmit(commit)
            TextField(String(localized: "Country", table: "Location"), text: $country).onSubmit(commit)
            TextField(String(localized: "State or region (optional)", table: "Location"), text: $state).onSubmit(commit)
            Button(action: commit) { Text("Look up", tableName: "Location") }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCommit)
            if let text = statusText { Text(text).foregroundStyle(.secondary) }
        } footer: {
            Text("Look up finds the city and fetches its prayer times.", tableName: "Location")
        }
    }

    private var statusText: String? {
        switch context.lookupStatus {
        case .idle: return nil
        case .lookingUp: return String(localized: "Looking up…", table: "Location")
        case .found:
            // Shows the committed place, not unsaved edits in the fields.
            let l = store.settings.location
            return [l.manualCity, l.manualState, l.manualCountry].compactMap { $0 }.joined(separator: ", ")
        case .cityNotFound: return String(localized: "City not found", table: "Location")
        case .unreachable: return String(localized: "Couldn't reach the server — try again", table: "Location")
        }
    }

    private func commit() {
        guard canCommit, let input = normalized else { return }
        store.setManualLocation(city: input.city, country: input.country, state: input.state)
    }
}
