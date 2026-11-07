import CryptoKit
import Foundation

public enum UpdateVerificationError: Error, Equatable {
    case missingDigest
    case digestMismatch
    case unreadableBundle
    case wrongBundleID
    case wrongVersion
    case badSignature
}

/// The checks a downloaded update must pass before it replaces the installed app (FR-3).
public enum UpdateVerifier {
    /// Throws unless the file's SHA-256 equals `expected` (hex, any case). A missing digest fails.
    public static func verifyDigest(of dmg: URL, expected: String?) throws {
        guard let expected else { throw UpdateVerificationError.missingDigest }
        // ponytail: reads the whole file; the download is capped at 50 MB (#144).
        let data = try Data(contentsOf: dmg)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected.lowercased() else { throw UpdateVerificationError.digestMismatch }
    }

    /// Throws unless the app's bundle id and version match and `codesign --verify --deep --strict` passes.
    public static func verifyApp(at app: URL, version: String, runner: CommandRunning) async throws {
        // Not `Bundle(url:)`: it caches Info.plist per path.
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw UpdateVerificationError.unreadableBundle }
        guard plist["CFBundleIdentifier"] as? String == MeqatCore.bundleIdentifier else {
            throw UpdateVerificationError.wrongBundleID
        }
        guard plist["CFBundleShortVersionString"] as? String == version else {
            throw UpdateVerificationError.wrongVersion
        }
        let status = try await runner.run(
            URL(fileURLWithPath: "/usr/bin/codesign"), ["--verify", "--deep", "--strict", app.path])
        guard status == 0 else { throw UpdateVerificationError.badSignature }
    }
}
