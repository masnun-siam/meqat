import Foundation
import os

public enum BundleReplaceError: Error, Equatable {
    case stagingFailed
    case swapFailed
}

/// Swaps a verified app into the installed app's path, putting the original back on any failure.
public struct BundleReplacer {
    private let files: FileMoving
    private let logger = Logger(subsystem: MeqatCore.bundleIdentifier, category: "updates")

    public init(files: FileMoving = FileManager.default) {
        self.files = files
    }

    public func replace(_ installed: URL, with newApp: URL) throws {
        // On the installed app's volume, so the moves below are renames.
        let staging: URL
        do {
            staging = try files.url(
                for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: installed, create: true)
        } catch {
            logger.warning("bundle replace failed: staging folder")
            throw BundleReplaceError.stagingFailed
        }
        let stagedNew = staging.appendingPathComponent("Meqat.app")
        let stagedOld = staging.appendingPathComponent("Meqat-old.app")

        do {
            try files.copyItem(at: newApp, to: stagedNew)
        } catch {
            fail("copy", staging: staging)
            throw BundleReplaceError.stagingFailed
        }

        do {
            try files.moveItem(at: installed, to: stagedOld)
        } catch {
            fail("move old aside", staging: staging)
            throw BundleReplaceError.swapFailed
        }

        do {
            try files.moveItem(at: stagedNew, to: installed)
        } catch {
            do {
                try files.moveItem(at: stagedOld, to: installed)
                fail("move new in", staging: staging)
            } catch {
                // ponytail: staging is kept here, it holds the only copy of the original.
                logger.error("rollback failed")
            }
            throw BundleReplaceError.swapFailed
        }

        do {
            try files.removeItem(at: staging)
        } catch {
            logger.warning("bundle replace cleanup failed")
        }
    }

    /// Logs the failed step (never a path) and removes the staging folder.
    private func fail(_ step: StaticString, staging: URL) {
        logger.warning("bundle replace failed: \(String(describing: step), privacy: .public)")
        do {
            try files.removeItem(at: staging)
        } catch {
            logger.warning("bundle replace cleanup failed")
        }
    }
}
