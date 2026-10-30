public enum EventKind: Sendable, Equatable {
    case voluntary, obligatory, prohibited
}

public enum EventID: String, CaseIterable, Codable, Sendable, Equatable {
    case tahajjud, fajr, shuruq, duha, istiwa, dhuhr, jumah, asr, ghurub, maghrib, isha

    public var kind: EventKind {
        switch self {
        case .tahajjud, .duha: .voluntary
        case .shuruq, .istiwa, .ghurub: .prohibited
        default: .obligatory
        }
    }

    public var displayName: String {
        switch self {
        case .shuruq: "Forbidden (sunrise)"
        case .istiwa: "Forbidden (noon)"
        case .ghurub: "Forbidden (sunset)"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}
