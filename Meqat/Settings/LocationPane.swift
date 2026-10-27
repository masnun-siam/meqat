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
            Picker("Location", selection: modeBinding) {
                Text("Automatic (uses this Mac's location)").tag(false)
                Text("Manual city").tag(true)
            }
            .pickerStyle(.radioGroup)
            if manualSelected { manualSection } else { automaticSection }
            Text("Last sync: \(context.lastSyncText ?? "never")").foregroundStyle(.secondary)
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
                    city = ""; country = ""; state = ""
                } else if store.settings.location.manualCity != nil {
                    store.settings.location.mode = .manual
                }
            })
    }

    private var automaticSection: some View {
        Section {
            Text("Current place: \(context.place ?? "—")")
            if let coordinates = context.coordinatesText { Text(coordinates).foregroundStyle(.secondary) }
        }
    }

    private var manualSection: some View {
        Section {
            TextField("City", text: $city).onSubmit(commit)
            TextField("Country", text: $country).onSubmit(commit)
            TextField("State or region (optional)", text: $state).onSubmit(commit)
            Button("Look up", action: commit)
                .keyboardShortcut(.defaultAction)
                .disabled(!canCommit)
            if let text = statusText { Text(text).foregroundStyle(.secondary) }
        }
    }

    private var statusText: String? {
        switch context.lookupStatus {
        case .idle: nil
        case .lookingUp: "Looking up…"
        case .found: [city, state, country].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: ", ")
        case .cityNotFound: "City not found"
        case .unreachable: "Couldn't reach the server — try again"
        }
    }

    private func commit() {
        guard canCommit, let input = normalized else { return }
        store.setManualLocation(city: input.city, country: input.country, state: input.state)
    }
}
