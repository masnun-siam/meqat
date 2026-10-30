import Foundation

public enum ReleaseError: Error, Equatable {
    case http(Int)
    case bodyTooLarge
    case invalidResponse
}
