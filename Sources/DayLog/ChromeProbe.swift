import Foundation
import DayLogCore
import os

/// Asks Google Chrome for the front window's mode, active tab URL, and tab title via Apple Events.
/// The URL is reduced to a hostname immediately and never stored or logged.
final class ChromeProbe {
    static let bundleID = "com.google.Chrome"
    private static let log = Logger(subsystem: "local.daylog", category: "chrome")

    enum Result: Equatable {
        /// A normal (non-incognito) window. Domain and title come from the same window in
        /// one script run, so the title can't belong to a different window than the mode check.
        case window(domain: String?, title: String?)
        case noWindow
        case incognito
        /// The user denied Automation for Chrome (error -1743).
        case denied
        case unavailable
    }

    /// The whole script runs inside the timeout so a hung Chrome can't block the
    /// main thread for the default two-minute Apple Event timeout.
    private lazy var script: NSAppleScript? = {
        let source = """
        with timeout of 2 seconds
            tell application id "\(Self.bundleID)"
                if (count of windows) is 0 then return ""
                set w to front window
                set t to active tab of w
                return (mode of w as text) & linefeed & (URL of t) & linefeed & (title of t)
            end tell
        end timeout
        """
        let s = NSAppleScript(source: source)
        var err: NSDictionary?
        if s?.compileAndReturnError(&err) != true {
            Self.log.error("Chrome script failed to compile: \(Self.code(err))")
            return nil
        }
        return s
    }()

    func probe() -> Result {
        guard let script else { return .unavailable }
        var err: NSDictionary?
        let output = script.executeAndReturnError(&err)
        if let err {
            let code = Self.code(err)
            if code == -1743 { return .denied }
            Self.log.debug("Chrome query failed: \(code)")
            return .unavailable
        }
        guard let text = output.stringValue, !text.isEmpty else { return .noWindow }
        let parts = text.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false)
        // Anything other than an explicit "normal" (including a malformed reply) is treated as private.
        guard parts.count == 3, parts[0] == "normal" else { return .incognito }
        let title = String(parts[2])
        return .window(domain: DomainExtractor.domain(fromURL: String(parts[1])), title: title.isEmpty ? nil : title)
    }

    private static func code(_ err: NSDictionary?) -> Int {
        (err?[NSAppleScript.errorNumber] as? Int) ?? 0
    }
}
