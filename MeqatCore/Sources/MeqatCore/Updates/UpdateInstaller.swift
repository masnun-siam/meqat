import Foundation
import Observation
import os

public enum InstallError: Error, Equatable {
    case notNewer
    case noAsset
    case relaunchFailed
}

/// Runs one install from click to relaunch: fresh release, download, verify, extract, verify, swap, relaunch.
/// Any failure deletes the work folder and leaves the installed app as it was.
@MainActor @Observable
public final class UpdateInstaller {
    public private(set) var state: InstallState = .idle

    @ObservationIgnored private let installedVersion: String
    @ObservationIgnored private let appURL: URL
    @ObservationIgnored private let client: ReleaseFetching
    @ObservationIgnored private let downloader: UpdateDownloader
    @ObservationIgnored private let extractor: DMGExtractor
    @ObservationIgnored private let replacer: BundleReplacer
    @ObservationIgnored private let runner: CommandRunning
    @ObservationIgnored private let launcher: ProcessLaunching
    @ObservationIgnored private let temporaryDirectory: URL
    @ObservationIgnored private let terminate: @MainActor () -> Void
    @ObservationIgnored private let logger = Logger(subsystem: MeqatCore.bundleIdentifier, category: "updates")

    @ObservationIgnored private var installTask: Task<Void, Never>?
    /// A cancelled run may still be unwinding when the next one starts; only the current run writes `state`.
    @ObservationIgnored private var currentRun = 0

    public init(
        installedVersion: String,
        appURL: URL,
        client: ReleaseFetching = GitHubReleaseClient(),
        downloader: UpdateDownloader = UpdateDownloader(),
        extractor: DMGExtractor = DMGExtractor(),
        replacer: BundleReplacer = BundleReplacer(),
        runner: CommandRunning = ProcessCommandRunner(),
        launcher: ProcessLaunching = ProcessLauncher(),
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        terminate: @escaping @MainActor () -> Void
    ) {
        self.installedVersion = installedVersion
        self.appURL = appURL
        self.client = client
        self.downloader = downloader
        self.extractor = extractor
        self.replacer = replacer
        self.runner = runner
        self.launcher = launcher
        self.temporaryDirectory = temporaryDirectory
        self.terminate = terminate
    }

    public var isRunning: Bool { state.isRunning }

    /// Starts an install; does nothing while one runs.
    public func install() {
        guard !isRunning else { return }
        currentRun += 1
        let run = currentRun
        state = .downloading(percent: 0)
        installTask = Task { await self.run(run) }
    }

    /// Stops a download or verification and returns to `idle`. The swap itself is never cancelled.
    public func cancel() {
        switch state {
        case .downloading, .verifying: break
        default: return
        }
        installTask?.cancel()
        installTask = nil
        currentRun += 1
        state = .idle
    }

    /// Before the app quits: cancels a download or verification, waits for a running swap to finish or roll back.
    public func prepareToQuit() async {
        switch state {
        case .downloading, .verifying:
            let task = installTask
            cancel()
            await task?.value
        case .installing:
            await installTask?.value
        case .idle, .relaunching, .failed:
            return
        }
    }

    // MARK: - Run

    private func run(_ run: Int) async {
        let work = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var relaunched = false
        do {
            try await perform(run, in: work)
            relaunched = true
        } catch {
            if error is CancellationError || Task.isCancelled {
                set(.idle, run)
            } else {
                logger.warning("update install failed: \(Self.kind(of: error), privacy: .public)")
                set(.failed, run)
            }
        }
        try? FileManager.default.removeItem(at: work)
        if run == currentRun { installTask = nil }
        if relaunched { terminate() }
    }

    private func perform(_ run: Int, in work: URL) async throws {
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        } catch {
            throw DownloadError.writeFailed
        }

        let release = try await client.fetchLatest()
        guard let version = ReleaseVersion.newer(tag: release.tag, than: installedVersion) else {
            throw InstallError.notNewer
        }
        guard let asset = release.asset else { throw InstallError.noAsset }

        let dmg = work.appendingPathComponent("Meqat.dmg")
        try await downloader.download(asset.downloadURL, to: dmg) { [weak self] percent in
            Task { @MainActor [weak self] in self?.setProgress(percent, run) }
        }
        set(.downloading(percent: 100), run)

        try Task.checkCancellation()
        set(.verifying, run)
        try await Self.offMain { try UpdateVerifier.verifyDigest(of: dmg, expected: asset.sha256) }
        let app = try await extractor.extractApp(from: dmg, into: work)
        try await UpdateVerifier.verifyApp(at: app, version: version.description, runner: runner)

        // Checked and set in one main-actor step, so a cancel can never land after the swap starts.
        try Task.checkCancellation()
        set(.installing, run)
        try await Self.offMain { [replacer, appURL] in try replacer.replace(appURL, with: app) }

        set(.relaunching, run)
        do {
            try Relauncher.relaunch(appURL, launcher: launcher)
        } catch {
            throw InstallError.relaunchFailed
        }
    }

    private func set(_ newState: InstallState, _ run: Int) {
        guard run == currentRun else { return }
        state = newState
    }

    /// Progress arrives in hops that may land late; it only ever moves forward within `downloading`.
    private func setProgress(_ percent: Int, _ run: Int) {
        guard run == currentRun, case .downloading(let shown) = state, percent > shown else { return }
        state = .downloading(percent: percent)
    }

    /// Hashing a 50 MB file and copying a bundle would otherwise block the main thread.
    private nonisolated static func offMain(_ work: () throws -> Void) async throws {
        try work()
    }

    // MARK: - Logging

    /// Error kind only, never a URL or path.
    static func kind(of error: Error) -> String {
        switch error {
        case let error as InstallError:
            switch error {
            case .notNewer: return "no newer release"
            case .noAsset: return "no asset"
            case .relaunchFailed: return "relaunch failed"
            }
        case let error as ReleaseError:
            switch error {
            case .http(let code): return "release check http \(code)"
            case .bodyTooLarge: return "release check too large"
            case .invalidResponse: return "invalid response"
            }
        case let error as DownloadError:
            switch error {
            case .insecureURL: return "download insecure"
            case .http(let code): return "download http \(code)"
            case .tooLarge: return "download too large"
            case .writeFailed: return "download write failed"
            }
        case let error as UpdateVerificationError:
            switch error {
            case .missingDigest: return "missing digest"
            case .digestMismatch: return "digest mismatch"
            case .unreadableBundle: return "unreadable bundle"
            case .wrongBundleID: return "wrong bundle id"
            case .wrongVersion: return "wrong version"
            case .badSignature: return "bad signature"
            }
        case let error as DMGError:
            switch error {
            case .attachFailed: return "dmg attach failed"
            case .appMissing: return "app missing"
            case .copyFailed: return "copy failed"
            }
        case let error as BundleReplaceError:
            switch error {
            case .stagingFailed: return "staging failed"
            case .swapFailed: return "swap failed"
            }
        case is URLError: return "connection error"
        default: return "other error"
        }
    }
}
