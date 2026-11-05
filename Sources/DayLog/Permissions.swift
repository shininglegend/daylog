import AppKit
import ApplicationServices

enum Permissions {
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system "allow Accessibility" prompt if not yet trusted.
    static func promptAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    enum AutomationStatus {
        case granted, denied, notDetermined, chromeNotRunning, unknown
    }

    /// Checks Chrome Automation consent without prompting.
    static func chromeAutomationStatus() -> AutomationStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: ChromeProbe.bundleID)
        guard let desc = target.aeDesc else { return .unknown }
        switch AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, false) {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
        case OSStatus(procNotFound): return .chromeNotRunning
        default: return .unknown
        }
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openAutomationSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    private static func open(_ s: String) {
        if let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }
}
