import Foundation

public enum Bounds {
    public static let offsetMinutes = -60...60
    public static let leadMinutes = 1...120
    public static let overlayHoldSeconds = 0...300
    public static let windowMinutes = 5...30

    public static func clamped(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

public enum AlertStyle: String, Codable, Sendable, Equatable {
    case fullScreen, banner, disabled
}

public enum TimeSource: String, Codable, Sendable, Equatable {
    case calculated
    case fixed = "static"
}

public struct StartAlert: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var offsetMinutes: Int { didSet { offsetMinutes = Bounds.clamped(offsetMinutes, to: Bounds.offsetMinutes) } }

    public init(enabled: Bool = true, offsetMinutes: Int = 0) {
        self.enabled = enabled
        self.offsetMinutes = Bounds.clamped(offsetMinutes, to: Bounds.offsetMinutes)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            offsetMinutes: try c.decodeIfPresent(Int.self, forKey: .offsetMinutes) ?? 0)
    }
}

public struct LeadAlert: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var leadMinutes: Int { didSet { leadMinutes = Bounds.clamped(leadMinutes, to: Bounds.leadMinutes) } }

    public init(enabled: Bool, leadMinutes: Int) {
        self.enabled = enabled
        self.leadMinutes = Bounds.clamped(leadMinutes, to: Bounds.leadMinutes)
    }

    public init(from decoder: Decoder, defaults: LeadAlert) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled,
            leadMinutes: try c.decodeIfPresent(Int.self, forKey: .leadMinutes) ?? defaults.leadMinutes)
    }

    // A bare `init(from:)` has no per-field default; `EventSettings` decodes through `init(from:defaults:)`.
    public init(from decoder: Decoder) throws {
        try self.init(from: decoder, defaults: LeadAlert(enabled: false, leadMinutes: 15))
    }
}

public struct EventSettings: Codable, Sendable, Equatable {
    public var style: AlertStyle
    public var timeSource: TimeSource
    /// A `.fixed` source with no time behaves as calculated.
    public var staticTime: ClockTime?
    public var startAlert: StartAlert
    public var endAlert: LeadAlert
    public var preWarning: LeadAlert
    public var overlayHoldSeconds: Int { didSet { overlayHoldSeconds = Bounds.clamped(overlayHoldSeconds, to: Bounds.overlayHoldSeconds) } }

    public init(
        style: AlertStyle, timeSource: TimeSource = .calculated, staticTime: ClockTime? = nil,
        startAlert: StartAlert = StartAlert(),
        endAlert: LeadAlert = LeadAlert(enabled: false, leadMinutes: 15),
        preWarning: LeadAlert = LeadAlert(enabled: false, leadMinutes: 20),
        overlayHoldSeconds: Int = 60
    ) {
        self.style = style
        self.timeSource = timeSource
        self.staticTime = staticTime
        self.startAlert = startAlert
        self.endAlert = endAlert
        self.preWarning = preWarning
        self.overlayHoldSeconds = Bounds.clamped(overlayHoldSeconds, to: Bounds.overlayHoldSeconds)
    }

    public static func defaults(for id: EventID) -> EventSettings {
        EventSettings(style: id == .duha || id == .tahajjud ? .disabled : .banner)
    }

    /// Decodes one event; every missing key takes the default for `id`.
    init(from decoder: Decoder, id: EventID) throws {
        let d = Self.defaults(for: id)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            style: try c.decodeIfPresent(AlertStyle.self, forKey: .style) ?? d.style,
            timeSource: try c.decodeIfPresent(TimeSource.self, forKey: .timeSource) ?? d.timeSource,
            staticTime: try c.decodeIfPresent(ClockTime.self, forKey: .staticTime) ?? d.staticTime,
            startAlert: try c.decodeIfPresent(StartAlert.self, forKey: .startAlert) ?? d.startAlert,
            endAlert: try c.decodeLead(forKey: .endAlert, default: d.endAlert),
            preWarning: try c.decodeLead(forKey: .preWarning, default: d.preWarning),
            overlayHoldSeconds: try c.decodeIfPresent(Int.self, forKey: .overlayHoldSeconds) ?? d.overlayHoldSeconds)
    }

    public init(from decoder: Decoder) throws {
        try self.init(from: decoder, id: .dhuhr)
    }
}

extension KeyedDecodingContainer {
    fileprivate func decodeLead(forKey key: Key, default d: LeadAlert) throws -> LeadAlert {
        guard contains(key) else { return d }
        return try LeadAlert(from: superDecoder(forKey: key), defaults: d)
    }
}

public enum School: Int, Codable, Sendable, Equatable {
    case shafii = 0
    case hanafi = 1
}

public enum TimeFormat: String, Codable, Sendable, Equatable {
    case twentyFour, twelve

    public var dateFormat: String { self == .twelve ? "h:mm a" : "HH:mm" }
}

public struct GeneralSettings: Codable, Sendable, Equatable {
    public var launchAtLogin: Bool
    public var method: Int?
    public var school: School
    public var timeFormat: TimeFormat
    public var shuruqMinutes: Int { didSet { shuruqMinutes = Bounds.clamped(shuruqMinutes, to: Bounds.windowMinutes) } }
    public var istiwaMinutes: Int { didSet { istiwaMinutes = Bounds.clamped(istiwaMinutes, to: Bounds.windowMinutes) } }
    public var ghurubMinutes: Int { didSet { ghurubMinutes = Bounds.clamped(ghurubMinutes, to: Bounds.windowMinutes) } }

    public init(
        launchAtLogin: Bool = true, method: Int? = nil, school: School = .shafii,
        timeFormat: TimeFormat = .twentyFour,
        shuruqMinutes: Int = 15, istiwaMinutes: Int = 10, ghurubMinutes: Int = 15
    ) {
        self.launchAtLogin = launchAtLogin
        self.method = method
        self.school = school
        self.timeFormat = timeFormat
        self.shuruqMinutes = Bounds.clamped(shuruqMinutes, to: Bounds.windowMinutes)
        self.istiwaMinutes = Bounds.clamped(istiwaMinutes, to: Bounds.windowMinutes)
        self.ghurubMinutes = Bounds.clamped(ghurubMinutes, to: Bounds.windowMinutes)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GeneralSettings()
        self.init(
            launchAtLogin: try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin,
            method: try c.decodeIfPresent(Int.self, forKey: .method),
            school: try c.decodeIfPresent(School.self, forKey: .school) ?? d.school,
            timeFormat: try c.decodeIfPresent(TimeFormat.self, forKey: .timeFormat) ?? d.timeFormat,
            shuruqMinutes: try c.decodeIfPresent(Int.self, forKey: .shuruqMinutes) ?? d.shuruqMinutes,
            istiwaMinutes: try c.decodeIfPresent(Int.self, forKey: .istiwaMinutes) ?? d.istiwaMinutes,
            ghurubMinutes: try c.decodeIfPresent(Int.self, forKey: .ghurubMinutes) ?? d.ghurubMinutes)
    }
}

public enum LocationMode: String, Codable, Sendable, Equatable {
    case automatic, manual
}

public struct LocationSettings: Codable, Sendable, Equatable {
    public var mode: LocationMode
    public var manualCity: String?
    public var manualCountry: String?
    public var manualState: String?

    public init(mode: LocationMode = .automatic, manualCity: String? = nil, manualCountry: String? = nil, manualState: String? = nil) {
        self.mode = mode
        self.manualCity = manualCity
        self.manualCountry = manualCountry
        self.manualState = manualState
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mode: try c.decodeIfPresent(LocationMode.self, forKey: .mode) ?? .automatic,
            manualCity: try c.decodeIfPresent(String.self, forKey: .manualCity),
            manualCountry: try c.decodeIfPresent(String.self, forKey: .manualCountry),
            manualState: try c.decodeIfPresent(String.self, forKey: .manualState))
    }

    public func placeName(timeZone: TimeZone) -> String? {
        switch mode {
        case .manual: manualCity
        case .automatic: timeZone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") }
        }
    }
}

public struct AppSettings: Sendable, Equatable {
    public var general: GeneralSettings
    public var location: LocationSettings
    public var events: [EventID: EventSettings]

    public static let defaultEvents = Dictionary(uniqueKeysWithValues: EventID.allCases.map { ($0, EventSettings.defaults(for: $0)) })

    public init(
        general: GeneralSettings = .init(), location: LocationSettings = .init(),
        events: [EventID: EventSettings] = AppSettings.defaultEvents
    ) {
        self.general = general
        self.location = location
        self.events = events
    }

    public subscript(event id: EventID) -> EventSettings {
        events[id] ?? .defaults(for: id)
    }
}

/// `[EventID: EventSettings]` stored as a JSON object keyed by event id; missing events take their defaults.
struct EventsGroup: Codable, Equatable {
    var events: [EventID: EventSettings]

    init(_ events: [EventID: EventSettings]) { self.events = events }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        events = [:]
        for id in EventID.allCases {
            let key = DynamicKey(id.rawValue)
            events[id] =
                c.contains(key)
                ? try EventSettings(from: c.superDecoder(forKey: key), id: id)
                : .defaults(for: id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        for (id, value) in events { try c.encode(value, forKey: DynamicKey(id.rawValue)) }
    }

    struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
