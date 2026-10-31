import AppKit
import MeqatCore
import SwiftUI

struct MenuDropdownView: View {
    let state: MenuState
    let actions: MenuActions
    let dismiss: @MainActor () -> Void

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
            if let update = state.updateRow {
                Divider()
                Button(update.title) {
                    NSWorkspace.shared.open(update.url)
                    dismiss()
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
            if let hero = state.hero {
                MenuHeroView(hero: hero)
                Divider()
            }
            VStack(spacing: 4) {
                ForEach(state.rows) { row in
                    MenuRowView(row: row)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            if let summary = state.forbiddenSummary {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "nosign").foregroundStyle(.secondary)
                    Text(summary.text).lineLimit(1)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(summary.accessibilityLabel)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(state.footerStatus).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            Button {
                actions.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh now").accessibilityLabel("Refresh now")
            .disabled(!state.refreshEnabled)
            Button {
                actions.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings").accessibilityLabel("Settings")
            Button("Quit") { actions.quit() }
        }
        .buttonStyle(.link).padding(12)
    }
}

private struct MenuHeroView: View {
    let hero: MenuHero

    private var isForbidden: Bool { hero.kind == .forbidden }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hero.title).font(.caption.weight(.semibold)).textCase(.uppercase)
                .foregroundStyle(isForbidden ? Color.red : Color.secondary)
            Text(hero.countdownText).font(.system(size: 24, weight: .semibold)).monospacedDigit()
                .foregroundStyle(isForbidden ? Color.red : Color.primary)
            if let progress = hero.progress {
                // Drawn, not ProgressView: the popover is rarely key, and AppKit then draws the bar grey without its tint.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(isForbidden ? Color.red : Color.accentColor).frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 6)
            }
            HStack {
                Text(hero.startText)
                Spacer(minLength: 8)
                if let next = hero.nextText { Text(next) }
            }
            .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
        }
        .lineLimit(1)
        .padding(12)
        .background(isForbidden ? Color.red.opacity(0.08) : Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hero.accessibilityLabel)
    }
}

private struct MenuRowView: View {
    let row: MenuRow

    private var symbol: String {
        switch row.marker {
        case .done: "✓"
        case .current: "●"
        case .next: "○"
        case .none: ""
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(symbol).frame(width: 18)
            Text(row.name)
            Spacer(minLength: 8)
            Text(row.timeText).monospacedDigit()
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}
