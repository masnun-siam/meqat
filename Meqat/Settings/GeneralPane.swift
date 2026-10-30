import MeqatCore
import SwiftUI

struct GeneralPane: View {
    @Bindable var store: SettingsStore
    @State private var confirmingReset = false

    var body: some View {
        Form {
            Toggle(isOn: $store.settings.general.launchAtLogin) {
                Text("Launch at login")
                Text("Opens Meqat automatically when you log in to this Mac.")
            }
            Picker(selection: $store.settings.general.method) {
                Text("Automatic (nearest authority)").tag(Int?.none)
                ForEach(CalculationMethod.all) { Text($0.name).tag(Int?.some($0.id)) }
            } label: {
                Text("Calculation method")
                Text("The authority whose rules set the prayer times. Automatic picks the one nearest your location.")
            }
            Picker(selection: $store.settings.general.school) {
                Text("Shafi'i").tag(School.shafii)
                Text("Hanafi").tag(School.hanafi)
            } label: {
                Text("Asr school")
                Text("Changes when Asr begins: Hanafi starts it later than Shafi'i.")
            }
            Picker("Time format", selection: $store.settings.general.timeFormat) {
                Text("24-hour (15:30)").tag(TimeFormat.twentyFour)
                Text("12-hour (3:30 PM)").tag(TimeFormat.twelve)
            }
            Section {
                DurationRow(
                    title: "Shuruq", help: "Starts at sunrise and lasts this long.",
                    minutes: $store.settings.general.shuruqMinutes)
                DurationRow(
                    title: "Istiwa", help: "Ends at Dhuhr and starts this long before it.",
                    minutes: $store.settings.general.istiwaMinutes)
                DurationRow(
                    title: "Ghurub", help: "Ends at sunset and starts this long before it.",
                    minutes: $store.settings.general.ghurubMinutes)
            } header: {
                Text("Prohibited windows")
            } footer: {
                Text("Times when voluntary prayer should be avoided. Set how long each one lasts.")
            }
            Section("Full-Screen overlay") {
                DurationRow(
                    title: "Auto-dismiss after", help: "Closes the full-screen alert on its own after this long.",
                    minutes: $store.settings.general.overlayTimeoutSeconds,
                    range: Bounds.overlayTimeoutSeconds, unit: "s")
            }
            Section {
                Button("Reset all settings…") { confirmingReset = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all settings?", isPresented: $confirmingReset) {
            Button("Reset all settings", role: .destructive) { store.resetAll() }
        } message: {
            Text("Restores every default. Your location is kept.")
        }
    }
}

private struct DurationRow: View {
    let title: String
    let help: String
    @Binding var minutes: Int
    var range = Bounds.windowMinutes
    var unit = "min"

    var body: some View {
        let clamped = Binding(
            get: { minutes },
            set: { minutes = Bounds.clamped($0, to: range) })
        LabeledContent {
            HStack {
                TextField(title, value: clamped, format: .number)
                    .labelsHidden().multilineTextAlignment(.trailing).frame(width: 50)
                Stepper(title, value: clamped, in: range).labelsHidden()
                Text(unit)
            }
        } label: {
            Text(title)
            Text(help)
        }
    }
}
