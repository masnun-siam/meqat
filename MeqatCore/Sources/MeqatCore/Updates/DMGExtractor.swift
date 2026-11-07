import Foundation
import os

public enum DMGError: Error, Equatable {
    case attachFailed
    case appMissing
    case copyFailed
}

/// Copies `Meqat.app` out of a downloaded DMG, always detaching the DMG once it is attached (FR-3, FR-4).
public struct DMGExtractor: Sendable {
    private let runner: CommandRunning
    private let logger = Logger(subsystem: MeqatCore.bundleIdentifier, category: "updates")
    private static let hdiutil = URL(fileURLWithPath: "/usr/bin/hdiutil")
    private static let ditto = URL(fileURLWithPath: "/usr/bin/ditto")

    public init(runner: CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    /// Returns `directory/Meqat.app`, copied without the quarantine attribute.
    public func extractApp(from dmg: URL, into directory: URL) async throws -> URL {
        // A fixed mount point means no plist output to parse.
        let mount = directory.appendingPathComponent("mnt-\(UUID().uuidString)")
        let attach = try? await runner.run(
            Self.hdiutil,
            ["attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount.path, dmg.path])
        guard attach == 0 else {
            logger.warning("dmg attach failed: status \(attach ?? -1, privacy: .public)")
            throw DMGError.attachFailed
        }

        let app = directory.appendingPathComponent("Meqat.app")
        do {
            try await copyApp(from: mount, to: app)
        } catch {
            await detach(mount)
            throw error
        }
        await detach(mount)
        return app
    }

    private func copyApp(from mount: URL, to app: URL) async throws {
        let source = mount.appendingPathComponent("Meqat.app")
        guard FileManager.default.fileExists(atPath: source.path) else {
            logger.warning("dmg has no Meqat.app at its root")
            throw DMGError.appMissing
        }
        let status = try? await runner.run(Self.ditto, ["--noqtn", source.path, app.path])
        guard status == 0 else {
            logger.warning("dmg copy failed: status \(status ?? -1, privacy: .public)")
            throw DMGError.copyFailed
        }
        guard Self.removeQuarantine(under: app) else {
            logger.warning("dmg copy failed: quarantine not removed")
            throw DMGError.copyFailed
        }
    }

    /// Strips `com.apple.quarantine` from the bundle and everything in it, so the new app launches without
    /// the unidentified-developer block. `ditto --noqtn` alone still copies the attribute (seen on macOS 27).
    /// Returns false if any file kept it.
    private static func removeQuarantine(under app: URL) -> Bool {
        let inside = FileManager.default.enumerator(atPath: app.path)?.compactMap { $0 as? String } ?? []
        let paths = [app.path] + inside.map { app.appendingPathComponent($0).path }
        return paths.allSatisfy { removexattr($0, "com.apple.quarantine", XATTR_NOFOLLOW) == 0 || errno == ENOATTR }
    }

    /// A failed detach is logged and does not change the result.
    private func detach(_ mount: URL) async {
        let status = try? await runner.run(Self.hdiutil, ["detach", mount.path, "-force"])
        if status != 0 {
            logger.warning("dmg detach failed: status \(status ?? -1, privacy: .public)")
        }
    }
}
