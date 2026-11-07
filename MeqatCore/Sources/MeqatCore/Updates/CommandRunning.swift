import Foundation

public protocol CommandRunning: Sendable {
    /// Runs `executable` with `arguments`, waits for it to exit and returns its exit status.
    func run(_ executable: URL, _ arguments: [String]) async throws -> Int32
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ executable: URL, _ arguments: [String]) async throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
