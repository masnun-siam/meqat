import Foundation
import Observation
import os

@MainActor @Observable
public final class UpdateChecker {
    public private(set) var status: UpdateStatus = .idle

    @ObservationIgnored private let installedVersion: String
    @ObservationIgnored private let client: ReleaseFetching
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let canInstall: Bool
    @ObservationIgnored private let isInstalling: @MainActor () -> Bool
    @ObservationIgnored private let logger = Logger(subsystem: MeqatCore.bundleIdentifier, category: "updates")

    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var manualPending = false
    @ObservationIgnored private var statusBeforeCheck: UpdateStatus = .idle

    public init(
        installedVersion: String,
        client: ReleaseFetching = GitHubReleaseClient(),
        now: @escaping @Sendable () -> Date = { Date() },
        canInstall: Bool = false,
        isInstalling: @escaping @MainActor () -> Bool = { false }
    ) {
        self.installedVersion = installedVersion
        self.client = client
        self.now = now
        self.canInstall = canInstall
        self.isInstalling = isInstalling
    }

    /// Starts a check; one started while another runs joins it. Skipped while an install runs.
    public func check(_ trigger: UpdateCheckTrigger) {
        guard !isInstalling() else { return }
        if trigger == .manual { manualPending = true }
        guard checkTask == nil else { return }
        statusBeforeCheck = status
        status = .checking
        checkTask = Task { await run() }
    }

    private func run() async {
        do {
            let release = try await client.fetchLatest()
            if let version = ReleaseVersion.newer(tag: release.tag, than: installedVersion) {
                status = .available(version: version.description, releaseURL: release.pageURL, canInstall: canInstall)
            } else {
                status = .upToDate(checkedAt: now())
            }
        } catch {
            logger.warning("update check failed: \(Self.kind(of: error), privacy: .public)")
            status = manualPending ? .failed : statusBeforeCheck
        }
        checkTask = nil
        manualPending = false
    }

    /// Error kind only, never a URL.
    private static func kind(of error: Error) -> String {
        switch error as? ReleaseError {
        case .http(let code)?: return "http \(code)"
        case .bodyTooLarge?: return "body too large"
        case .invalidResponse?: return "invalid response"
        case nil: return error is URLError ? "connection error" : "other error"
        }
    }
}
