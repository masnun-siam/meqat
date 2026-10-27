import AppKit
import MeqatCore
import SwiftUI

struct MenuDropdownView: View {
    let state: MenuState
    let actions: MenuActions

    private static let notificationsPane = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header = state.header {
                Text(header).font(.headline).lineLimit(1).padding(12)
                Divider()
            }
            content
            if state.showsNotificationsOffRow {
                Divider()
                Button("Notifications are off — Open System Settings") {
                    NSWorkspace.shared.open(Self.notificationsPane)
                }
                .buttonStyle(.link).padding(12)
            }
            Divider()
            footer
        }
        .frame(width: 280)
    }

    @ViewBuilder private var content: some View {
        if let empty = state.emptyState {
            VStack(spacing: 8) {
                Text(empty.message).multilineTextAlignment(.center)
                switch empty.action {
                case .openLocationPane: Button("Open Location settings") { actions.openLocationPane() }
                case .tryAgain: Button("Try again") { actions.tryAgain() }
                case nil: EmptyView()
                }
            }
            .frame(maxWidth: .infinity).padding(16)
        } else {
            VStack(spacing: 4) {
                ForEach(state.rows) { row in
                    MenuRowView(row: row)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            HStack {
                Text(state.footerStatus).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Refresh now") { actions.refreshNow() }.disabled(!state.refreshEnabled)
            }
            HStack {
                Button("Settings…") { actions.openSettings() }
                Spacer()
                Button("Quit") { actions.quit() }
            }
        }
        .buttonStyle(.link).padding(12)
    }
}

private struct MenuRowView: View {
    let row: MenuRow

    private var symbol: String {
        switch row.marker {
        case .done: "✓"
        case .current: "●"
        case .next: "▶"
        case .prohibited: "⛔"
        case .none: ""
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(symbol).frame(width: 18)
            Text(row.name)
            Spacer(minLength: 8)
            Text(row.timeText).monospacedDigit()
            if let detail = row.detailText { Text(detail).foregroundStyle(.secondary) }
        }
        .font(.system(size: 12))
        .opacity(row.isDimmed ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}
