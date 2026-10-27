public struct ClockTime: Codable, Sendable, Equatable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard text.count == 5, parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute),
              parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) })
        else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected HH:mm, got \(text)"))
        }
        self.init(hour: hour, minute: minute)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(format: "%02d:%02d", hour, minute))
    }
}
