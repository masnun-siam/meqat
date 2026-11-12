import AppKit
import MeqatCore
import SwiftUI

struct GeneralPane: View {
    @Bindable var store: SettingsStore
    let context: SettingsContext
    @State private var confirmingReset = false
    @State private var languageChoice = LanguageChoice(override: Self.storedOverride)
    @State private var askingRelaunch = false

    var body: some View {
        Form {
            Picker(selection: languageSelection) {
                Text("System", tableName: "Language").tag(LanguageChoice.system)
                Text(verbatim: "English").tag(LanguageChoice.english)
                Text(verbatim: "বাংলা").tag(LanguageChoice.bangla)
            } label: {
                Text("Language", tableName: "Language")
                Text("Meqat relaunches to switch language.", tableName: "Language")
            }
            Toggle(isOn: $store.settings.general.launchAtLogin) {
                Text("Launch at login", tableName: "Settings")
                Text("Opens Meqat automatically when you log in to this Mac.", tableName: "Settings")
            }
            Picker(selection: $store.settings.general.method) {
                Text("Automatic (nearest authority)", tableName: "Settings").tag(Int?.none)
                ForEach(CalculationMethod.all) { Text($0.name).tag(Int?.some($0.id)) }
            } label: {
                Text("Calculation method", tableName: "Settings")
                Text(
                    "The authority whose rules set the prayer times. Automatic picks the one nearest your location.",
                    tableName: "Settings")
            }
            Picker(selection: $store.settings.general.school) {
                Text("Shafi'i", tableName: "Settings").tag(School.shafii)
                Text("Hanafi", tableName: "Settings").tag(School.hanafi)
            } label: {
                Text("Asr school", tableName: "Settings")
                Text("Changes when Asr begins: Hanafi starts it later than Shafi'i.", tableName: "Settings")
            }
            Picker(selection: $store.settings.general.timeFormat) {
                Text("24-hour (15:30)", tableName: "Settings").tag(TimeFormat.twentyFour)
                Text("12-hour (3:30 PM)", tableName: "Settings").tag(TimeFormat.twelve)
            } label: {
                Text("Time format", tableName: "Settings")
            }
            Section {
                DurationRow(
                    title: EventID.shuruq.displayName(in: context.language),
                    help: String(localized: "Starts at sunrise and lasts this long.", table: "Settings"),
                    minutes: $store.settings.general.shuruqMinutes)
                DurationRow(
                    title: EventID.istiwa.displayName(in: context.language),
                    help: String(localized: "Ends at Dhuhr and starts this long before it.", table: "Settings"),
                    minutes: $store.settings.general.istiwaMinutes)
                DurationRow(
                    title: EventID.ghurub.displayName(in: context.language),
                    help: String(localized: "Ends at sunset and starts this long before it.", table: "Settings"),
                    minutes: $store.settings.general.ghurubMinutes)
            } header: {
                Text("Forbidden windows", tableName: "Settings")
            } footer: {
                Text("Times when voluntary prayer should be avoided. Set how long each one lasts.", tableName: "Settings")
            }
            Section {
                DurationRow(
                    title: String(localized: "Auto-dismiss after", table: "Settings"),
                    help: String(localized: "Closes the full-screen alert on its own after this long.", table: "Settings"),
                    minutes: $store.settings.general.overlayTimeoutSeconds,
                    range: Bounds.overlayTimeoutSeconds, unit: String(localized: "s", table: "Settings"))
            } header: {
                Text("Full-Screen overlay", tableName: "Settings")
            }
            Section {
                Button {
                    context.testOverlay()
                } label: {
                    Text("Show test overlay", tableName: "Settings")
                }
                Button {
                    context.testBanner()
                } label: {
                    Text("Send test banner", tableName: "Settings")
                }
            } header: {
                Text("Test alerts", tableName: "Settings")
            } footer: {
                if !context.notificationsAuthorized {
                    Text(
                        "Notifications are off for Meqat. Turn them on in System Settings › Notifications.",
                        tableName: "Settings")
                }
            }
            Section {
                Button {
                    confirmingReset = true
                } label: {
                    Text("Reset all settings…", tableName: "Settings")
                }
            } header: {
                Text("Reset", tableName: "Settings")
            }
        }
        .formStyle(.grouped)
        .onAppear { context.refreshAuthorization() }
        .confirmationDialog(Text("Reset all settings?", tableName: "Settings"), isPresented: $confirmingReset) {
            Button(role: .destructive) {
                store.resetAll()
            } label: {
                Text("Reset all settings", tableName: "Settings")
            }
        } message: {
            Text("Restores every default. Your location is kept.", tableName: "Settings")
        }
        .alert(Text("Relaunch Meqat to change the language?", tableName: "Language"), isPresented: $askingRelaunch) {
            Button {
                Self.relaunch()
            } label: {
                Text("Relaunch Now", tableName: "Language")
            }
            Button(role: .cancel) {
            } label: {
                Text("Later", tableName: "Language")
            }
        } message: {
            Text("Until then, Meqat stays in its current language.", tableName: "Language")
        }
    }

    /// Stores the choice as Meqat's own `AppleLanguages` override at once, and asks to relaunch
    /// only when it changes the language in effect (Bangla PRD FR-1, FR-2).
    private var languageSelection: Binding<LanguageChoice> {
        Binding(
            get: { languageChoice },
            set: { choice in
                languageChoice = choice
                if let override = choice.override {
                    UserDefaults.standard.set(override, forKey: Self.appleLanguagesKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: Self.appleLanguagesKey)
                }
                askingRelaunch = Language.resolve(override: choice.override, preferred: Self.macPreferred) != context.language
            })
    }

    private static let appleLanguagesKey = "AppleLanguages"

    /// Meqat's own override only; `stringArray(forKey:)` would fall through to the Mac's list and hide System.
    private static var storedOverride: [String]? {
        UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[appleLanguagesKey] as? [String]
    }

    /// The Mac's preferred languages, ignoring Meqat's override.
    private static var macPreferred: [String] {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[appleLanguagesKey] as? [String] ?? []
    }

    /// Opens a new instance, then quits this one; if the launch fails Meqat keeps running.
    private static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}

private struct DurationRow: View {
    let title: String
    let help: String
    @Binding var minutes: Int
    var range = Bounds.windowMinutes
    var unit = String(localized: "min", table: "Settings")
    @Environment(\.locale) private var locale

    var body: some View {
        let clamped = Binding(
            get: { minutes },
            set: { minutes = Bounds.clamped($0, to: range) })
        LabeledContent {
            HStack {
                TextField(title, value: clamped, format: .number.locale(locale))
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
