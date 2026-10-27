import Foundation

public enum AladhanError: Error, Equatable {
    case cityNotFound
    case http(Int)
    case apiCode(Int)
    case bodyTooLarge
    case invalidResponse(String)
    case noLocation
}
