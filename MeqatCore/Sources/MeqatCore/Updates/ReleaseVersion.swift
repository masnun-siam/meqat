/// `major.minor.patch`, each part ASCII digits only; one leading lowercase `v` is ignored.
public struct ReleaseVersion: Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    /// nil for anything that is not `x.y.z`.
    public init?(_ text: String) {
        let body = text.hasPrefix("v") ? text.dropFirst() : Substring(text)
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
            parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { ("0"..."9").contains($0) } }),
            let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2])
        else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// `1.4.0`, without the `v`.
    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    /// The tag's version when it is newer than `installed`; nil when either is not `x.y.z` or it is not newer.
    public static func newer(tag: String, than installed: String) -> ReleaseVersion? {
        guard let tagVersion = ReleaseVersion(tag), let current = ReleaseVersion(installed),
            tagVersion > current
        else { return nil }
        return tagVersion
    }
}
