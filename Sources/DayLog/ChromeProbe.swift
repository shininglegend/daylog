import Foundation
import DayLogCore
import os

/// Asks Google Chrome for the front window's mode and active tab URL via Apple Events.
/// The URL is reduced to a hostname immediately and never stored or logged.
final class ChromeProbe {
    static let bundleID = "com.google.Chrome"
    private static let log = Logger(subsystem: "local.daylog", category: "chrome")

    enum Result: Equatable {
        case domain(String?)
        case incognito
        /// The user denied Automation for Chrome (error -1743).
        case denied
        case unavailable
    }

    private lazy var script: NSAppleScript? = {
        let source = """
        tell application id "\(Self.bundleID)"
            if (count of windows) is 0 then return ""
            with timeout of 2 seconds
                set w to front window
                return (mode of w as text) & linefeed & (URL of active tab of w)
            end timeout
        end tell
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
        guard let text = output.stringValue, !text.isEmpty else { return .domain(nil) }
        let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.first == "incognito" { return .incognito }
        return .domain(parts.count > 1 ? DomainExtractor.domain(fromURL: String(parts[1])) : nil)
    }

    private static func code(_ err: NSDictionary?) -> Int {
        (err?[NSAppleScript.errorNumber] as? Int) ?? 0
    }
}
