import AppKit
import ApplicationServices
import DayLogCore
import os

/// Polls the frontmost app on the main run loop and feeds a `SegmentTracker`.
/// Stops (closes the open segment) while paused, locked, asleep, or switched out.
final class Recorder: NSObject {
    private static let log = Logger(subsystem: "local.daylog", category: "recorder")

    private let store: DayLogStore
    private let tracker: SegmentTracker
    private let chrome = ChromeProbe()
    private var timer: Timer?
    private var purgeTimer: Timer?

    var settings: Preferences {
        didSet {
            if settings.pollInterval != oldValue.pollInterval { schedule() }
            updateGap()
        }
    }
    var matcher = RuleMatcher(rules: [])

    private(set) var screenLocked = false
    private(set) var asleep = false
    private(set) var sessionInactive = false
    /// `.distantFuture` means paused until resumed.
    private(set) var pausedUntil: Date?

    /// Called after each poll so the UI can refresh state.
    var onTick: ((Recorder) -> Void)?
    /// Chrome Automation was denied (-1743); domains are recorded as nil until it's allowed.
    private(set) var chromeDenied = false
    private(set) var accessibilityGranted = Permissions.accessibilityGranted

    init(store: DayLogStore, settings: Preferences) {
        self.store = store
        self.settings = settings
        self.tracker = SegmentTracker(sink: store, clock: store.clock)
        super.init()
        updateGap()
    }

    var isPaused: Bool {
        guard let until = pausedUntil else { return false }
        return until > store.clock.now
    }

    func pause(until: Date) {
        pausedUntil = until
        tick()
    }

    func resume() {
        pausedUntil = nil
        tick()
    }

    var isRecording: Bool { !isPaused && !screenLocked && !asleep && !sessionInactive }

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        ws.addObserver(self, selector: #selector(sessionBecameActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        let dn = DistributedNotificationCenter.default()
        dn.addObserver(self, selector: #selector(screenDidLock), name: .init("com.apple.screenIsLocked"), object: nil)
        dn.addObserver(self, selector: #selector(screenDidUnlock), name: .init("com.apple.screenIsUnlocked"), object: nil)

        purge()
        schedule()
        let hourly = Timer(timeInterval: 3600, target: self, selector: #selector(purgeTimerFired), userInfo: nil, repeats: true)
        RunLoop.main.add(hourly, forMode: .common)
        purgeTimer = hourly
        tick()
    }

    /// Closes the open segment and removes all timers and observers.
    func shutdown() {
        timer?.invalidate()
        purgeTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        closeOpenSegment()
    }

    private func schedule() {
        timer?.invalidate()
        let t = Timer(timeInterval: settings.pollInterval, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        t.tolerance = settings.pollInterval * 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func updateGap() {
        tracker.maxGap = max(30, settings.pollInterval * 3)
    }

    @objc private func timerFired() { tick() }
    @objc private func purgeTimerFired() { purge() }

    func purge() {
        do {
            try store.purge(retentionDays: settings.totalsRetentionDays)
        } catch {
            Self.log.error("purge failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// One poll.
    func tick() {
        accessibilityGranted = Permissions.accessibilityGranted
        defer { onTick?(self) }
        if pausedUntil != nil, !isPaused { pausedUntil = nil }
        guard isRecording else {
            closeOpenSegment()
            return
        }
        do {
            let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            if idleSeconds >= settings.idleThreshold {
                try tracker.observe(.idle, since: store.clock.now.addingTimeInterval(-idleSeconds))
            } else {
                try tracker.observe(matcher.apply(observe()))
            }
        } catch {
            Self.log.error("capture write failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func observe() -> Capture {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return Capture(bundleID: nil, appName: nil, title: nil, domain: nil)
        }
        var title = accessibilityGranted ? Self.focusedWindowTitle(pid: app.processIdentifier) : nil
        var domain: String?
        if app.bundleIdentifier == ChromeProbe.bundleID {
            switch chrome.probe() {
            case .domain(let d): domain = d; chromeDenied = false
            case .incognito: domain = nil; title = nil; chromeDenied = false
            case .denied: chromeDenied = true
            case .unavailable: break
            }
        }
        return Capture(bundleID: app.bundleIdentifier, appName: app.localizedName, title: title, domain: domain)
    }

    private static func focusedWindowTitle(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.5)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success,
              let s = title as? String, !s.isEmpty
        else { return nil }
        return s
    }

    private func closeOpenSegment() {
        do { try tracker.stop() } catch {
            Self.log.error("closing segment failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The open segment was deleted from the UI; start a fresh one on the next poll.
    func segmentsDeleted(ids: Set<Int64>) {
        if let open = tracker.open, ids.contains(open.id) { tracker.discardOpen() }
    }

    /// Rules changed: restart the segment so the new rules apply from now on.
    func rulesChanged(_ rules: [Rule]) {
        matcher = RuleMatcher(rules: rules)
        closeOpenSegment()
        tick()
    }

    // MARK: System state

    @objc private func willSleep() { asleep = true; tick() }
    @objc private func didWake() { asleep = false; purge(); tick() }
    @objc private func sessionResigned() { sessionInactive = true; tick() }
    @objc private func sessionBecameActive() { sessionInactive = false; tick() }
    @objc private func screenDidLock() { screenLocked = true; tick() }
    @objc private func screenDidUnlock() { screenLocked = false; tick() }
}
