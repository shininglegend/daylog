import Foundation

/// Applies block rules to an observation at capture time.
public struct RuleMatcher: Sendable {
    private let appIDs: Set<String>
    private let domains: [String]
    private let titleSubstrings: [String]
    private let regexes: [NSRegularExpression]

    public init(rules: [Rule]) {
        var appIDs = Set<String>(), domains: [String] = [], subs: [String] = [], regexes: [NSRegularExpression] = []
        for rule in rules {
            let p = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !p.isEmpty else { continue }
            switch rule.type {
            case .app: appIDs.insert(p.lowercased())
            case .domain: domains.append(Self.normalizeDomain(p))
            case .titleContains: subs.append(p)
            case .titleRegex:
                if let re = try? NSRegularExpression(pattern: p) { regexes.append(re) }
            }
        }
        self.appIDs = appIDs
        self.domains = domains
        self.titleSubstrings = subs
        self.regexes = regexes
    }

    public static func isValidRegex(_ pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }

    static func normalizeDomain(_ p: String) -> String {
        var d = p.lowercased()
        if d.hasPrefix("*.") { d.removeFirst(2) }
        if d.hasPrefix(".") { d.removeFirst() }
        if d.hasPrefix("www.") { d.removeFirst(4) }
        return d
    }

    public var isEmpty: Bool { appIDs.isEmpty && domains.isEmpty && titleSubstrings.isEmpty && regexes.isEmpty }

    public func matches(bundleID: String?, title: String?, domain: String?) -> Bool {
        if let id = bundleID?.lowercased(), appIDs.contains(id) { return true }
        if let d = domain?.lowercased() {
            for rule in domains where d == rule || d.hasSuffix("." + rule) { return true }
        }
        if let t = title, !t.isEmpty {
            for s in titleSubstrings where t.range(of: s, options: [.caseInsensitive]) != nil { return true }
            let range = NSRange(t.startIndex..., in: t)
            for re in regexes where re.firstMatch(in: t, range: range) != nil { return true }
        }
        return false
    }

    public func matches(_ segment: Segment) -> Bool {
        matches(bundleID: segment.state.bundleID, title: segment.state.title, domain: segment.state.domain)
    }

    /// The state to record for an observation: blocked activity keeps nothing identifying.
    public func apply(_ o: Capture) -> ActivityState {
        if matches(bundleID: o.bundleID, title: o.title, domain: o.domain) { return .blocked }
        return ActivityState(bundleID: o.bundleID, appName: o.appName, title: o.title, domain: o.domain)
    }
}
