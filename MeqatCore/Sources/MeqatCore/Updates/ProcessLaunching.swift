import Foundation

public protocol ProcessLaunching: Sendable {
    /// Starts `executable` and returns without waiting for it.
    func launch(_ executable: URL, _ arguments: [String]) throws
}

public struct ProcessLauncher: ProcessLaunching {
    public init() {}

    public func launch(_ executable: URL, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        try process.run()
    }
}
