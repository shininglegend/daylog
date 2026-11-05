import AppKit
import DayLogCore
import LocalAuthentication
import Observation
import ServiceManagement
import os

/// App-wide state shared by the menu bar popover and the main window.
@Observable
final class AppModel {
    enum Status {
        case recording, paused, suspended, permissionMissing

        var symbol: String {
            switch self {
            case .recording: "record.circle"
            case .paused: "pause.circle"
            case .suspended: "moon.circle"
            case .permissionMissing: "exclamationmark.triangle"
            }
        }

        var description: String {
            switch self {
            case .recording: "Recording"
            case .paused: "Paused"
            case .suspended: "Not recording (locked or asleep)"
            case .permissionMissing: "Accessibility permission needed"
            }
        }
    }

    private static let log = Logger(subsystem: "local.daylog", category: "app")

    private let keys: KeyStore
    private let clock: Clock
    private(set) var store: DayLogStore
    @ObservationIgnored private var recorder: Recorder

    private(set) var settings: Preferences
    private(set) var rules: [Rule] = []
    private(set) var status: Status = .recording
    private(set) var pausedUntil: Date?
    private(set) var chromeDenied = false
    private(set) var accessibilityGranted = false
    /// Bumped on every poll and data change; views reload with `.task(id: revision)`.
    private(set) var revision = 0
    var errorMessage: String?
    /// Touch ID gate for the main window (UI-only, not cryptographic).
    var mainWindowUnlocked = false

    init(keys: KeyStore = KeychainKeyStore(), clock: Clock = SystemClock()) throws {
        self.keys = keys
        self.clock = clock
        let store = try DayLogStore(keys: keys, clock: clock)
        self.store = store
        let settings = (try? store.loadPreferences()) ?? Preferences()
        self.settings = settings
        self.recorder = Recorder(store: store, settings: settings)
        self.rules = (try? store.rules()) ?? []
        // Nothing is recorded until the user has seen the onboarding explanation.
        if !settings.onboarded { recorder.pause(until: .distantFuture) }
        startRecorder()
    }

    private func startRecorder() {
        recorder.matcher = RuleMatcher(rules: rules)
        recorder.onTick = { [weak self] r in self?.recorderTicked(r) }
        recorder.start()
    }

    private func recorderTicked(_ r: Recorder) {
        accessibilityGranted = r.accessibilityGranted
        chromeDenied = r.chromeDenied
        pausedUntil = r.pausedUntil
        status = if r.isPaused { .paused }
            else if !r.accessibilityGranted { .permissionMissing }
            else if !r.isRecording { .suspended }
            else { .recording }
        revision &+= 1
    }

    func shutdown() { recorder.shutdown() }

    private func perform(_ what: String, _ body: () throws -> Void) {
        do {
            try body()
            revision &+= 1
        } catch {
            Self.log.error("\(what, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            errorMessage = "\(what) failed: \(error)"
        }
    }

    // MARK: Pause

    func pause(minutes: Int?) {
        recorder.pause(until: minutes.map { clock.now.addingTimeInterval(TimeInterval($0) * 60) } ?? .distantFuture)
    }

    func resume() { recorder.resume() }

    // MARK: Queries (decrypted in memory only)

    func liveSegments() -> [Segment] {
        (try? store.liveSegments()) ?? []
    }

    func breakdown(_ kind: BreakdownKind, firstDay: Date, lastDay: Date) -> [BreakdownRow] {
        (try? store.breakdown(kind, firstDay: firstDay, lastDay: lastDay)) ?? []
    }

    var now: Date { clock.now }

    // MARK: Edits

    func deleteSegments(ids: [Int64]) {
        perform("Delete") {
            recorder.segmentsDeleted(ids: Set(ids))
            try store.deleteSegments(ids: ids)
        }
    }

    /// Adds a rule and returns the live segments it matches, for the retroactive-cleanup prompt.
    @discardableResult
    func addRule(type: RuleType, pattern: String) -> [Segment] {
        var matches: [Segment] = []
        perform("Add rule") {
            let rule = try store.addRule(type: type, pattern: pattern)
            rules = try store.rules()
            recorder.rulesChanged(rules)
            matches = try store.segmentsMatching(rule)
        }
        return matches
    }

    func updateRule(_ rule: Rule) -> [Segment] {
        var matches: [Segment] = []
        perform("Update rule") {
            try store.updateRule(rule)
            rules = try store.rules()
            recorder.rulesChanged(rules)
            matches = try store.segmentsMatching(rule)
        }
        return matches
    }

    func deleteRule(_ rule: Rule) {
        perform("Delete rule") {
            try store.deleteRule(id: rule.id)
            rules = try store.rules()
            recorder.rulesChanged(rules)
        }
    }

    func updateSettings(_ change: (inout Preferences) -> Void) {
        var s = settings
        change(&s)
        guard s != settings else { return }
        perform("Save settings") {
            try store.savePreferences(s)
            settings = s
            recorder.settings = s
        }
    }

    // MARK: Launch at login

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) {
        perform("Launch at login") {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        }
    }

    // MARK: Delete all data

    /// Removes the database and every `local.daylog.*` keychain item, then starts fresh.
    func deleteAllData() {
        perform("Delete all data") {
            let wasPaused = recorder.pausedUntil
            recorder.shutdown()
            store.db.close()
            try DayLogStore.deleteAllData(directory: store.directory, keys: keys)
            store = try DayLogStore(keys: keys, clock: clock)
            var fresh = Preferences()
            fresh.onboarded = true
            try store.savePreferences(fresh)
            settings = fresh
            rules = []
            recorder = Recorder(store: store, settings: fresh)
            startRecorder()
            if let wasPaused { recorder.pause(until: wasPaused) }
        }
    }

    // MARK: Touch ID

    func unlockMainWindow() {
        Task {
            let ok = (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "show your DayLog activity")) ?? false
            if ok { mainWindowUnlocked = true }
        }
    }

    func completeOnboarding() {
        updateSettings { $0.onboarded = true }
        recorder.resume()
    }
}
