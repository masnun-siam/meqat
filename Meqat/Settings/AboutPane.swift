import AppKit
import MeqatCore
import SwiftUI

struct AboutPane: View {
    @Bindable var store: SettingsStore
    let context: SettingsContext

    private static let repository = URL(string: "https://github.com/masnun-siam/meqat")!
    private static let author = URL(string: "https://github.com/masnun-siam")!
    private static let coffee = URL(string: "https://buymeacoffee.com/msiamn")!

    private var versionText: String {
        let info = Bundle.main
        let short = info.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = info.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 4) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                    Text("Meqat").font(.title2.bold())
                    Text(versionText).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            Section {
                statusLines
                Button("Check now") { context.checkNow() }
                    .disabled(context.updateStatus == .checking)
                Toggle(isOn: $store.settings.general.checkForUpdates) {
                    Text("Check for updates automatically")
                    Text("Asks GitHub once a day whether a newer version exists. Sends nothing about you or this Mac.")
                }
            }
            Section {
                Link(destination: Self.repository) {
                    Label("GitHub repository", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: Self.author) {
                    Label("Made by Masnun Siam", systemImage: "person.crop.circle")
                }
                Link(destination: Self.coffee) {
                    Label("Buy me a coffee", systemImage: "cup.and.saucer")
                }
            } header: {
                Text("Project")
            } footer: {
                Text("Meqat is free and open source. Report bugs and follow releases on GitHub.")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var statusLines: some View {
        switch context.updateStatus {
        case .idle: EmptyView()
        case .checking: Text("Checking…").foregroundStyle(.secondary)
        case .upToDate:
            Text("You're up to date")
            if let text = context.lastCheckedText {
                Text("Last checked \(text)").foregroundStyle(.secondary)
            }
        case .available(let version, let url):
            Text("Version \(version) is available")
            Link("View release", destination: url)
            Text("Installed with Homebrew? Run").foregroundStyle(.secondary)
            Text("brew upgrade --cask meqat").font(.body.monospaced()).textSelection(.enabled)
        case .failed: Text("Couldn't check for updates").foregroundStyle(.secondary)
        }
    }
}
