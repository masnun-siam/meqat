import AppKit
import MeqatCore
import SwiftUI

struct AboutPane: View {
    @Bindable var store: SettingsStore
    let context: SettingsContext

    private static let repository = URL(string: "https://github.com/masnun-siam/meqat")!
    private static let author = URL(string: "https://github.com/masnun-siam")!
    private static let coffee = URL(string: "https://buymeacoffee.com/msiamn")!

    // Strings, not numbers, so the version keeps Latin digits in Bangla (PRD FR-6).
    private var versionText: Text {
        let info = Bundle.main
        let short = info.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = info.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return Text("Version \(short) (\(build))", tableName: "About")
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 4) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                    Text(verbatim: "Meqat").font(.title2.bold())
                    versionText.foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            Section {
                statusLines
                Button {
                    context.checkNow()
                } label: {
                    Text("Check now", tableName: "About")
                }
                .disabled(context.updateStatus == .checking || context.installState.isRunning)
                Toggle(isOn: $store.settings.general.checkForUpdates) {
                    Text("Check for updates automatically", tableName: "About")
                    Text("Asks GitHub once a day whether a newer version exists. Sends nothing about you or this Mac.", tableName: "About")
                }
            }
            Section {
                Link(destination: Self.repository) {
                    link("GitHub repository", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: Self.author) {
                    link("Made by Masnun Siam", systemImage: "person.crop.circle")
                }
                Link(destination: Self.coffee) {
                    link("Buy me a coffee", systemImage: "cup.and.saucer")
                }
            } header: {
                Text("Project", tableName: "About")
            } footer: {
                Text("Meqat is free and open source. Report bugs and follow releases on GitHub.", tableName: "About")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var statusLines: some View {
        switch context.updateStatus {
        case .idle: EmptyView()
        case .checking: Text("Checking…", tableName: "About").foregroundStyle(.secondary)
        case .upToDate:
            Text("You're up to date", tableName: "About")
            if let text = context.lastCheckedText {
                Text("Last checked \(text)", tableName: "About").foregroundStyle(.secondary)
            }
        case .available(let version, let url, let canInstall):
            if canInstall {
                installLines(version: version, url: url)
            } else {
                availableLines(version: version, url: url)
            }
        case .failed: Text("Couldn't check for updates", tableName: "About").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func availableLines(version: String, url: URL, showsInstall: Bool = false) -> some View {
        Text("Version \(version) is available", tableName: "About")
        if showsInstall { installButton }
        viewRelease(url)
        Text("Installed with Homebrew? Run", tableName: "About").foregroundStyle(.secondary)
        Text(verbatim: "brew upgrade --cask meqat").font(.body.monospaced()).textSelection(.enabled)
    }

    @ViewBuilder private func installLines(version: String, url: URL) -> some View {
        switch context.installState {
        case .idle: availableLines(version: version, url: url, showsInstall: true)
        case .downloading(let percent):
            Text("Downloading… \(percent)%", tableName: "About")
            Button {
                context.cancelInstall()
            } label: {
                Text("Cancel", tableName: "About")
            }
        case .verifying, .installing, .relaunching: Text("Installing…", tableName: "About")
        case .failed:
            Text("Update failed", tableName: "About")
            installButton
            viewRelease(url)
        }
    }

    private var installButton: some View {
        Button {
            context.install()
        } label: {
            Text("Download and install", tableName: "About")
        }
    }

    private func viewRelease(_ url: URL) -> some View {
        Link(destination: url) { Text("View release", tableName: "About") }
    }

    private func link(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(title, tableName: "About")
        } icon: {
            Image(systemName: systemImage)
        }
    }
}
