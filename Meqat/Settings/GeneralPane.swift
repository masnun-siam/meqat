import MeqatCore
import SwiftUI

struct GeneralPane: View {
    @Bindable var store: SettingsStore
    @State private var confirmingReset = false

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $store.settings.general.launchAtLogin)
            Picker("Calculation method", selection: $store.settings.general.method) {
                Text("Automatic (nearest authority)").tag(Int?.none)
                ForEach(CalculationMethod.all) { Text($0.name).tag(Int?.some($0.id)) }
            }
            Picker("Asr school", selection: $store.settings.general.school) {
                Text("Shafi'i").tag(School.shafii)
                Text("Hanafi").tag(School.hanafi)
            }
            Picker("Time format", selection: $store.settings.general.timeFormat) {
                Text("24-hour (15:30)").tag(TimeFormat.twentyFour)
                Text("12-hour (3:30 PM)").tag(TimeFormat.twelve)
            }
            Section("Prohibited windows") {
                DurationRow(title: "Shuruq", minutes: $store.settings.general.shuruqMinutes)
                DurationRow(title: "Istiwa", minutes: $store.settings.general.istiwaMinutes)
                DurationRow(title: "Ghurub", minutes: $store.settings.general.ghurubMinutes)
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
    @Binding var minutes: Int

    var body: some View {
        let clamped = Binding(
            get: { minutes },
            set: { minutes = Bounds.clamped($0, to: Bounds.windowMinutes) })
        LabeledContent(title) {
            HStack {
                TextField(title, value: clamped, format: .number)
                    .labelsHidden().multilineTextAlignment(.trailing).frame(width: 50)
                Stepper(title, value: clamped, in: Bounds.windowMinutes).labelsHidden()
                Text("min")
            }
        }
    }
}
