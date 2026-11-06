import Foundation

public enum Bounds {
    public static let offsetMinutes = -60...60
    public static let leadMinutes = 1...120
    public static let overlayTimeoutSeconds = 10...600
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

/// Keys shared by `StartAlert` and `LeadAlert`. `enabled` is written for builds before per-alert styles and read only to carry their settings over.
enum AlertCodingKeys: String, CodingKey {
    case style, enabled, offsetMinutes, leadMinutes
}

public struct StartAlert: Codable, Sendable, Equatable {
    public var style: AlertStyle
    public var offsetMinutes: Int { didSet { offsetMinutes = Bounds.clamped(offsetMinutes, to: Bounds.offsetMinutes) } }
    public var enabled: Bool { style != .disabled }

    public init(style: AlertStyle = .banner, offsetMinutes: Int = 0) {
        self.style = style
        self.offsetMinutes = Bounds.clamped(offsetMinutes, to: Bounds.offsetMinutes)
    }

    /// `legacy` is the style this alert had in builds before per-alert styles when its `enabled` was on (default on).
    init(from decoder: Decoder, defaults d: StartAlert, legacy: AlertStyle) throws {
        let c = try decoder.container(keyedBy: AlertCodingKeys.self)
        self.init(
            style: try c.decodeAlertStyle(default: d.style, legacy: legacy, legacyEnabled: true),
            offsetMinutes: try c.decodeIfPresent(Int.self, forKey: .offsetMinutes) ?? d.offsetMinutes)
    }

    public init(from decoder: Decoder) throws {
        try self.init(from: decoder, defaults: StartAlert(), legacy: .banner)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AlertCodingKeys.self)
        try c.encode(style, forKey: .style)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(offsetMinutes, forKey: .offsetMinutes)
    }
}

public struct LeadAlert: Codable, Sendable, Equatable {
    public var style: AlertStyle
    public var leadMinutes: Int { didSet { leadMinutes = Bounds.clamped(leadMinutes, to: Bounds.leadMinutes) } }
    public var enabled: Bool { style != .disabled }

    public init(style: AlertStyle, leadMinutes: Int) {
        self.style = style
        self.leadMinutes = Bounds.clamped(leadMinutes, to: Bounds.leadMinutes)
    }

    /// `legacy` is the style this alert had in builds before per-alert styles when its `enabled` was on (default off).
    init(from decoder: Decoder, defaults d: LeadAlert, legacy: AlertStyle) throws {
        let c = try decoder.container(keyedBy: AlertCodingKeys.self)
        self.init(
            style: try c.decodeAlertStyle(default: d.style, legacy: legacy, legacyEnabled: false),
            leadMinutes: try c.decodeIfPresent(Int.self, forKey: .leadMinutes) ?? d.leadMinutes)
    }

    // A bare `init(from:)` has no per-field default; `EventSettings` decodes through `init(from:defaults:legacy:)`.
    public init(from decoder: Decoder) throws {
        try self.init(from: decoder, defaults: LeadAlert(style: .disabled, leadMinutes: 15), legacy: .banner)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AlertCodingKeys.self)
        try c.encode(style, forKey: .style)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(leadMinutes, forKey: .leadMinutes)
    }
}

extension KeyedDecodingContainer where K == AlertCodingKeys {
    /// The saved `style` (an unknown value takes `d`); without one, `legacy` when the saved `enabled` (else `legacyEnabled`) is on, else Off.
    fileprivate func decodeAlertStyle(default d: AlertStyle, legacy: AlertStyle, legacyEnabled: Bool) throws -> AlertStyle {
        guard contains(.style) else {
            return try (decodeIfPresent(Bool.self, forKey: .enabled) ?? legacyEnabled) ? legacy : .disabled
        }
        return try decodeIfPresent(String.self, forKey: .style).flatMap(AlertStyle.init(rawValue:)) ?? d
    }
}

public struct EventSettings: Codable, Sendable, Equatable {
    public var timeSource: TimeSource
    /// A `.fixed` source with no time behaves as calculated.
    public var staticTime: ClockTime?
    public var startAlert: StartAlert
    public var endAlert: LeadAlert
    public var preWarning: LeadAlert

    /// The first alert style that is not Off (start, end, pre-warning), else `.disabled`. Written for builds before per-alert styles.
    public var style: AlertStyle {
        [startAlert.style, endAlert.style, preWarning.style].first { $0 != .disabled } ?? .disabled
    }

    public init(
        timeSource: TimeSource = .calculated, staticTime: ClockTime? = nil,
        startAlert: StartAlert = StartAlert(),
        endAlert: LeadAlert = LeadAlert(style: .disabled, leadMinutes: 15),
        preWarning: LeadAlert = LeadAlert(style: .disabled, leadMinutes: 20)
    ) {
        self.timeSource = timeSource
        self.staticTime = staticTime
        self.startAlert = startAlert
        self.endAlert = endAlert
        self.preWarning = preWarning
    }

    public static func defaults(for id: EventID) -> EventSettings {
        EventSettings(startAlert: StartAlert(style: id == .duha || id == .tahajjud ? .disabled : .banner))
    }

    enum CodingKeys: String, CodingKey {
        case style, timeSource, staticTime, startAlert, endAlert, preWarning
    }

    /// Decodes one event; every missing key takes the default for `id`. Alerts without a `style` of their own
    /// carry over the event-level `style` and `enabled` flags saved by builds before per-alert styles.
    init(from decoder: Decoder, id: EventID) throws {
        let d = Self.defaults(for: id)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try c.decodeIfPresent(String.self, forKey: .style).flatMap(AlertStyle.init(rawValue:)) ?? d.style
        let legacyPre: AlertStyle = legacy == .disabled ? .disabled : .banner
        self.init(
            timeSource: try c.decodeIfPresent(TimeSource.self, forKey: .timeSource) ?? d.timeSource,
            staticTime: try c.decodeIfPresent(ClockTime.self, forKey: .staticTime) ?? d.staticTime,
            startAlert: c.contains(.startAlert)
                ? try StartAlert(from: c.superDecoder(forKey: .startAlert), defaults: d.startAlert, legacy: legacy)
                : StartAlert(style: legacy, offsetMinutes: d.startAlert.offsetMinutes),
            endAlert: try c.decodeLead(forKey: .endAlert, default: d.endAlert, legacy: legacy),
            preWarning: try c.decodeLead(forKey: .preWarning, default: d.preWarning, legacy: legacyPre))
    }

    public init(from decoder: Decoder) throws {
        try self.init(from: decoder, id: .dhuhr)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(style, forKey: .style)
        try c.encode(timeSource, forKey: .timeSource)
        try c.encodeIfPresent(staticTime, forKey: .staticTime)
        try c.encode(startAlert, forKey: .startAlert)
        try c.encode(endAlert, forKey: .endAlert)
        try c.encode(preWarning, forKey: .preWarning)
    }
}

extension KeyedDecodingContainer {
    /// A missing lead alert was off in builds before per-alert styles, which is also its default (Off).
    fileprivate func decodeLead(forKey key: Key, default d: LeadAlert, legacy: AlertStyle) throws -> LeadAlert {
        guard contains(key) else { return d }
        return try LeadAlert(from: superDecoder(forKey: key), defaults: d, legacy: legacy)
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
    public var checkForUpdates: Bool
    public var shuruqMinutes: Int { didSet { shuruqMinutes = Bounds.clamped(shuruqMinutes, to: Bounds.windowMinutes) } }
    public var istiwaMinutes: Int { didSet { istiwaMinutes = Bounds.clamped(istiwaMinutes, to: Bounds.windowMinutes) } }
    public var ghurubMinutes: Int { didSet { ghurubMinutes = Bounds.clamped(ghurubMinutes, to: Bounds.windowMinutes) } }
    public var overlayTimeoutSeconds: Int {
        didSet { overlayTimeoutSeconds = Bounds.clamped(overlayTimeoutSeconds, to: Bounds.overlayTimeoutSeconds) }
    }

    public init(
        launchAtLogin: Bool = true, method: Int? = nil, school: School = .shafii,
        timeFormat: TimeFormat = .twentyFour,
        shuruqMinutes: Int = 15, istiwaMinutes: Int = 10, ghurubMinutes: Int = 15,
        overlayTimeoutSeconds: Int = 60, checkForUpdates: Bool = true
    ) {
        self.launchAtLogin = launchAtLogin
        self.method = method
        self.school = school
        self.timeFormat = timeFormat
        self.checkForUpdates = checkForUpdates
        self.shuruqMinutes = Bounds.clamped(shuruqMinutes, to: Bounds.windowMinutes)
        self.istiwaMinutes = Bounds.clamped(istiwaMinutes, to: Bounds.windowMinutes)
        self.ghurubMinutes = Bounds.clamped(ghurubMinutes, to: Bounds.windowMinutes)
        self.overlayTimeoutSeconds = Bounds.clamped(overlayTimeoutSeconds, to: Bounds.overlayTimeoutSeconds)
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
            ghurubMinutes: try c.decodeIfPresent(Int.self, forKey: .ghurubMinutes) ?? d.ghurubMinutes,
            overlayTimeoutSeconds: try c.decodeIfPresent(Int.self, forKey: .overlayTimeoutSeconds) ?? d.overlayTimeoutSeconds,
            checkForUpdates: try c.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? d.checkForUpdates)
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
