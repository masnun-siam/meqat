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
            Section("Time") {
                Picker(selection: timeSource) {
                    Text("Calculated").tag(TimeSource.calculated)
                    Text("Static").tag(TimeSource.fixed)
                } label: {
                    Text("Source")
                    Text(sourceHelp)
                }
                .pickerStyle(.radioGroup)
                if settings.timeSource == .fixed {
                    DatePicker("Static time", selection: staticDate, displayedComponents: .hourAndMinute)
                    if isOutsideWindow(settings) {
                        Label("⚠ outside the calculated window", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            Picker(selection: event.style) {
                Text("Full-Screen Focus").tag(AlertStyle.fullScreen)
                Text("Banner").tag(AlertStyle.banner)
                Text("Disabled").tag(AlertStyle.disabled)
            } label: {
                Text("Style")
                Text(
                    "Full-Screen Focus covers the screen, Banner shows a notification, "
                        + "Disabled turns off every alert for this event.")
            }
            Section("Start alert") {
                Toggle(isOn: event.startAlert.enabled) {
                    Text("Enabled")
                    Text("Alert when the event starts.")
                }
                NumberRow(
                    title: "Offset", help: "Minutes to shift the start alert: negative is earlier, positive is later.",
                    unit: "min", value: event.startAlert.offsetMinutes,
                    range: Bounds.offsetMinutes, signed: true)
            }
            Section("End alert") {
                Toggle(isOn: event.endAlert.enabled) {
                    Text("Enabled")
                    Text("Alert before the event ends.")
                }
                NumberRow(
                    title: "Lead", help: "How many minutes before the end.", unit: "min",
                    value: event.endAlert.leadMinutes, range: Bounds.leadMinutes)
            }
            Section("Pre-warning") {
                Toggle(isOn: event.preWarning.enabled) {
                    Text("Enabled")
                    Text("A banner before the event starts, even when the style is Full-Screen Focus.")
                }
                NumberRow(
                    title: "Lead", help: "How many minutes before the start.", unit: "min",
                    value: event.preWarning.leadMinutes, range: Bounds.leadMinutes)
            }
            Section {
                Button("Reset to defaults") { store.resetEvent(eventID) }
            }
        }
        .formStyle(.grouped)
    }

    private var sourceHelp: String {
        eventID == .duha
            ? "Duha always runs from the end of the sunrise forbidden window to the start of the noon one, so a static time does not move it."
            : "Calculated follows today's prayer times. Static uses the same clock time every day."
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

private struct NumberRow: View {
    let title: String
    let help: String
    let unit: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var signed = false

    var body: some View {
        let clamped = Binding(
            get: { value },
            set: { value = Bounds.clamped($0, to: range) })
        LabeledContent {
            HStack {
                TextField(title, value: clamped, format: signed ? .number.sign(strategy: .always(includingZero: false)) : .number)
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
