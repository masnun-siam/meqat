import Foundation

/// What decides whether the running bundle can be replaced in place (FR-7 of the in-app-update PRD).
public struct InstallFacts: Sendable, Equatable {
    public var parentWritable: Bool
    public var volumeReadOnly: Bool
    public var translocated: Bool
    public var sandboxed: Bool

    public init(parentWritable: Bool, volumeReadOnly: Bool, translocated: Bool, sandboxed: Bool) {
        self.parentWritable = parentWritable
        self.volumeReadOnly = volumeReadOnly
        self.translocated = translocated
        self.sandboxed = sandboxed
    }
}

/// FR-7 of the in-app-update PRD: may Meqat install an update over itself. When not, the app keeps today's release link.
public enum InstallEligibility {
    /// Pure, no I/O: true only when every fact allows replacing the bundle.
    public static func canInstall(_ facts: InstallFacts) -> Bool {
        facts.parentWritable && !facts.volumeReadOnly && !facts.translocated && !facts.sandboxed
    }

    /// Reads the facts for `bundleURL`, failing closed when one cannot be read:
    /// - `parentWritable`: `FileManager.isWritableFile(atPath:)` on the bundle's parent folder.
    /// - `volumeReadOnly`: `URLResourceValues.volumeIsReadOnly`; unreadable counts as read-only.
    /// - `translocated`: the path contains `/AppTranslocation/` (the `SecTranslocate` API is not public).
    /// - `sandboxed`: `APP_SANDBOX_CONTAINER_ID` is set in `environment` (pass `ProcessInfo.processInfo.environment`).
    public static func probe(bundleURL: URL, environment: [String: String], fileManager: FileManager = .default) -> InstallFacts {
        let volumeReadOnly = (try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) ?? true
        return InstallFacts(
            parentWritable: fileManager.isWritableFile(atPath: bundleURL.deletingLastPathComponent().path),
            volumeReadOnly: volumeReadOnly,
            translocated: bundleURL.path.contains("/AppTranslocation/"),
            sandboxed: environment["APP_SANDBOX_CONTAINER_ID"] != nil)
    }
}
