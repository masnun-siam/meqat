import MeqatCore
import SwiftUI

struct EventPane: View {
    let eventID: EventID
    @Bindable var store: SettingsStore
    let context: SettingsContext

    init(eventID: EventID, store: SettingsStore, context: SettingsContext) {
        self.eventID = eventID
        self.store = store
        self.context = context
    }

    private var event: Binding<EventSettings> {
        Binding(
            get: { store.settings.events[eventID, default: .defaults(for: eventID)] },
            set: { store.settings.events[eventID] = $0 })
    }

    var body: some View {
        let settings = event.wrappedValue
        Form {
            Section {
                Picker(selection: timeSource) {
                    Text("Calculated", tableName: "Settings").tag(TimeSource.calculated)
                    Text("Static", tableName: "Settings").tag(TimeSource.fixed)
                } label: {
                    Text("Source", tableName: "Settings")
                    Text(sourceHelp)
                }
                .pickerStyle(.radioGroup)
                if settings.timeSource == .fixed {
                    DatePicker(selection: staticDate, displayedComponents: .hourAndMinute) {
                        Text("Static time", tableName: "Settings")
                    }
                    if isOutsideWindow(settings) {
                        Label {
                            Text("⚠ outside the calculated window", tableName: "Settings")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Time", tableName: "Settings")
            }
            Section {
                StylePicker(
                    style: event.startAlert.style, help: String(localized: "Alert when the event starts.", table: "Settings"))
                NumberRow(
                    title: String(localized: "Offset", table: "Settings"),
                    help: String(
                        localized: "Minutes to shift the start alert: negative is earlier, positive is later.",
                        table: "Settings"),
                    unit: Self.minutesUnit, value: event.startAlert.offsetMinutes,
                    range: Bounds.offsetMinutes, signed: true)
            } header: {
                Text("Start alert", tableName: "Settings")
            }
            Section {
                StylePicker(
                    style: event.endAlert.style, help: String(localized: "Alert before the event ends.", table: "Settings"))
                NumberRow(
                    title: Self.leadTitle, help: String(localized: "How many minutes before the end.", table: "Settings"),
                    unit: Self.minutesUnit, value: event.endAlert.leadMinutes, range: Bounds.leadMinutes)
            } header: {
                Text("End alert", tableName: "Settings")
            }
            Section {
                StylePicker(
                    style: event.preWarning.style, help: String(localized: "Alert before the event starts.", table: "Settings"))
                NumberRow(
                    title: Self.leadTitle, help: String(localized: "How many minutes before the start.", table: "Settings"),
                    unit: Self.minutesUnit, value: event.preWarning.leadMinutes, range: Bounds.leadMinutes)
            } header: {
                Text("Pre-warning", tableName: "Settings")
            }
            Section {
                Button {
                    store.resetEvent(eventID)
                } label: {
                    Text("Reset to defaults", tableName: "Settings")
                }
            }
        }
        .formStyle(.grouped)
    }

    private static let minutesUnit = String(localized: "min", table: "Settings")
    private static let leadTitle = String(localized: "Lead", table: "Settings")

    private var sourceHelp: String {
        eventID == .duha
            ? String(
                localized:
                    "Duha always runs from the end of the sunrise forbidden window to the start of the noon one, so a static time does not move it.",
                table: "Settings")
            : String(
                localized: "Calculated follows today's prayer times. Static uses the same clock time every day.",
                table: "Settings")
    }

    private var timeSource: Binding<TimeSource> {
        Binding(
            get: { event.wrappedValue.timeSource },
            set: { source in
                event.wrappedValue.timeSource = source
                if source == .fixed, event.wrappedValue.staticTime == nil {
                    event.wrappedValue.staticTime = defaultStaticTime
                }
            })
    }

    /// Today's calculated start floored to the minute, else 12:00.
    private var defaultStaticTime: ClockTime {
        guard let start = context.calculatedWindows[eventID]?.start else { return ClockTime(hour: 12, minute: 0) }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: start)
        return ClockTime(hour: parts.hour ?? 12, minute: parts.minute ?? 0)
    }

    private var staticDate: Binding<Date> {
        Binding(
            get: {
                let time = event.wrappedValue.staticTime ?? defaultStaticTime
                return Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
            },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                event.wrappedValue.staticTime = ClockTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
            })
    }

    private func isOutsideWindow(_ settings: EventSettings) -> Bool {
        guard let time = settings.staticTime, let window = context.calculatedWindows[eventID] else { return false }
        return StaticTimeHint.isOutside(time, window: window, timeZone: .current)
    }
}

private struct StylePicker: View {
    @Binding var style: AlertStyle
    let help: String

    var body: some View {
        Picker(selection: $style) {
            Text("Full-Screen Focus", tableName: "Settings").tag(AlertStyle.fullScreen)
            Text("Banner", tableName: "Settings").tag(AlertStyle.banner)
            Text("Off", tableName: "Settings").tag(AlertStyle.disabled)
        } label: {
            Text("Style", tableName: "Settings")
            Text(help)
        }
    }
}

private struct NumberRow: View {
    let title: String
    let help: String
    let unit: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var signed = false
    @Environment(\.locale) private var locale

    var body: some View {
        let clamped = Binding(
            get: { value },
            set: { value = Bounds.clamped($0, to: range) })
        LabeledContent {
            HStack {
                TextField(
                    title, value: clamped,
                    format: signed
                        ? .number.sign(strategy: .always(includingZero: false)).locale(locale) : .number.locale(locale)
                )
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
