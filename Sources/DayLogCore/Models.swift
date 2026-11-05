import Foundation

/// Raw facts from one poll, before block rules are applied.
public struct Capture: Equatable, Sendable {
    public var bundleID: String?
    public var appName: String?
    public var title: String?
    public var domain: String?

    public init(bundleID: String?, appName: String?, title: String?, domain: String?) {
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.domain = domain
    }
}

/// What a segment records. A new segment starts whenever this changes.
public struct ActivityState: Equatable, Sendable {
    public var bundleID: String?
    public var appName: String?
    public var title: String?
    public var domain: String?
    public var idle: Bool
    public var blocked: Bool

    public init(bundleID: String?, appName: String?, title: String?, domain: String?, idle: Bool = false, blocked: Bool = false) {
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.domain = domain
        self.idle = idle
        self.blocked = blocked
    }

    public static let idle = ActivityState(bundleID: nil, appName: nil, title: nil, domain: nil, idle: true)
    public static let blocked = ActivityState(bundleID: nil, appName: BlockedLabel.name, title: nil, domain: nil, blocked: true)
}

public enum BlockedLabel {
    public static let name = "Blocked"
}

/// A stored segment with title and domain decrypted in memory.
public struct Segment: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var start: Date
    public var end: Date
    public var state: ActivityState
    /// The hour key is gone, so title/domain could not be decrypted.
    public var expired: Bool

    public init(id: Int64, start: Date, end: Date, state: ActivityState, expired: Bool = false) {
        self.id = id
        self.start = start
        self.end = end
        self.state = state
        self.expired = expired
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

public enum RuleType: String, CaseIterable, Sendable, Identifiable {
    case app
    case domain
    case titleContains = "title_contains"
    case titleRegex = "title_regex"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .app: "App (bundle ID)"
        case .domain: "Domain (and subdomains)"
        case .titleContains: "Title contains"
        case .titleRegex: "Title regex"
        }
    }
}

public struct Rule: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var type: RuleType
    public var pattern: String
    public var createdAt: Date

    public init(id: Int64 = 0, type: RuleType, pattern: String, createdAt: Date) {
        self.id = id
        self.type = type
        self.pattern = pattern
        self.createdAt = createdAt
    }
}
