import SwiftUI

/// State shared by every screen's panel.
final class OverlayModel: ObservableObject {
    @Published var content: OverlayContent
    @Published var remaining: Int

    init(content: OverlayContent) {
        self.content = content
        remaining = content.holdSeconds
    }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // White text contrast on each stop: 18.7:1, 15.8:1, 11.7:1 (see PR).
    private static let gradient = LinearGradient(
        colors: [
            Color(red: 0x0B / 255, green: 0x10 / 255, blue: 0x2A / 255),
            Color(red: 0x2A / 255, green: 0x14 / 255, blue: 0x55 / 255),
            Color(red: 0x0F / 255, green: 0x3D / 255, blue: 0x4D / 255),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var canDismiss: Bool { model.remaining <= 0 }

    private var timeRange: String {
        let f = Self.timeFormat
        return "\(f.string(from: model.content.start))–\(f.string(from: model.content.end))"
    }

    private var buttonTitle: String {
        canDismiss ? "Dismiss" : String(format: "Dismiss (%d:%02d)", model.remaining / 60, model.remaining % 60)
    }

    var body: some View {
        ZStack {
            Self.gradient.ignoresSafeArea()
            VStack(spacing: 24) {
                Text(model.content.eventName)
                    .font(.system(size: 96, weight: .bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(timeRange)
                    .font(.system(size: 40, weight: .medium))
                Button(action: dismiss) {
                    Text(buttonTitle)
                        .font(.system(size: 22, weight: .semibold))
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canDismiss)
                .controlSize(.large)
            }
            .foregroundStyle(.white)
            .padding(48)
        }
        .animation(nil, value: model.remaining)
    }
}
