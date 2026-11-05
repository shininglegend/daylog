# DayLog: local macOS menu bar activity timeline

## Goal
A personal macOS menu bar app that records which app, window title, and Chrome website I'm using. It shows a 48-hour timeline and time breakdowns by app and by website. Everything stays on this Mac.

## Hard constraints (do not violate)
- **No network access.** Do not use URLSession, the Network framework, sockets, analytics, crash uploaders, or update checks.
- **No screenshots or Screen Recording permission.** No keystroke logging and no Input Monitoring.
- **Allowed permissions only:** Accessibility (window titles), plus Automation for Google Chrome only (active tab URL).
- **48-hour title retention.** Window titles and per-segment records are purged after 48h. Only aggregated per-app and per-domain daily totals live longer.
- **No titles or URLs in logs.** Never write window titles, URLs, or domains to os_log, stdout, or crash logs.
- **No third-party dependencies** unless clearly justified. Prefer the system SQLite3 C API. If you use GRDB, pin the exact version.

## Platform and stack
- macOS 14 or later, Swift, SwiftUI, `MenuBarExtra`, Swift Charts.
- Set `LSUIElement` so there is no Dock icon.
- Not sandboxed: the App Sandbox blocks Accessibility access to other apps. Use the hardened runtime with the `com.apple.security.automation.apple-events` entitlement.
- Add `NSAppleEventsUsageDescription` to Info.plist.
- Project format is your choice (Xcode project or XcodeGen). It must build from the command line with a script.

## Signing
Sign with a stable identity so macOS permission grants survive rebuilds.
- The build script takes the identity name as a parameter.
- The README explains how to create a self-signed code-signing certificate in Keychain Access (Certificate Assistant → Create a Certificate → Code Signing), and how to use a Developer ID instead if one exists.

## Capture
- **Polling:** every 5s (configurable) on the main run loop.
- **Frontmost app:** `NSWorkspace.shared.frontmostApplication`, recording bundle ID and name.
- **Window title:** read the focused window's `AXTitle` through the Accessibility API. If it's unavailable, store null.
- **Chrome domain:**
  - Only query when Chrome is frontmost, via Apple Events (NSAppleScript or ScriptingBridge).
  - Get `URL of active tab of front window` and `mode of front window`.
  - If the mode is incognito, store domain null and title null.
  - Store the hostname only, with a leading `www.` stripped. Using a bundled public-suffix list snapshot to reduce hosts to the registrable domain is your call.
  - `chrome://` and similar internal pages store the domain `chrome`.
  - Never persist the full URL, path, or query, even temporarily on disk.
- **Idle:** `CGEventSource.secondsSinceLastEventType(.combinedSessionState, ...)`. Idle threshold is 2 minutes (configurable).
- **Stop or mark not-recording on:**
  - screen lock (`com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` distributed notifications)
  - sleep and wake (NSWorkspace notifications)
  - fast user switching (`sessionDidResignActive` / `sessionDidBecomeActive`)
  - user pause
- **Segments:** keep one open segment while the state (app, title, domain, idle, blocked) is unchanged. Close it and open a new one on change. Flush the open segment's end time to disk at least every 60s so a crash loses little.
- **Clock:** inject the clock so purge and rollup logic is testable.

## Blocking
- **Rule types:** app (bundle ID), domain (exact or suffix), title contains (case-insensitive), title regex.
- **Applied at capture time.** Matching activity is stored as a segment with `blocked = true`, the app name "Blocked", and title, domain, and bundle ID set to null. Totals still add up, but nothing identifying is written.
- **From the UI:** right-click a timeline entry to choose "Block this app", "Block this domain", "Block titles containing…", or "Delete entry".
- **Retroactive cleanup:** when a rule is added, offer to delete existing matching segments.

## Storage
- **Location:** `~/Library/Application Support/DayLog.noindex/daylog.sqlite`. The `.noindex` suffix keeps it out of Spotlight.
- **File permissions:** directory 0700, database file 0600.
- **Time Machine:** on first launch, set `URLResourceValues.isExcludedFromBackup = true` on the directory.
- **SQLite settings:** `PRAGMA secure_delete=ON`, with `journal_mode=DELETE`, or WAL with a TRUNCATE checkpoint after every purge. Your choice.
- **Schema (adjust as needed):**
  - `segments(id, start, end, bundle_id, app_name, title, domain, idle, blocked)`
  - `daily_totals(day, kind['app'|'domain'], key, seconds)`. Exclude idle time, and count blocked time under "Blocked".
  - `rules(id, type, pattern, created_at)`
  - `settings(key, value)`

## Retention and purge
- **Schedule:** run at launch, on wake, and hourly.
- **Procedure:**
  1. In a single transaction, roll up segments whose `end` is older than now minus 48h into `daily_totals`.
  2. Delete those segments.
  3. Checkpoint or vacuum as needed so deleted titles don't linger in the database file.
- **Totals retention:** 90 days by default, configurable from 30 days to forever.
- **Breakdown queries** that cover the last 48h must combine live segments and rolled-up totals without double counting.

## UI
- **Menu bar icon:** shows the current state (recording, paused, or a permission is missing).
- **Popover:**
  - today's active time
  - top 5 apps and top 5 domains
  - pause controls: 15m, 1h, until resumed
  - "Open DayLog" and "Quit"
- **Main window, four tabs:**
  1. **Timeline (last 48h):** chronological segments with time range, app, full window title, and domain. Idle, paused, and locked periods appear as gaps. Includes search and filtering by app. The right-click actions from the Blocking section live here.
  2. **Breakdown:** Swift Charts bar charts by app and by domain. Ranges: Today, Yesterday, 7d, 30d, custom. Each row shows a share of total active time.
  3. **Rules:** list, add, edit, and delete block rules.
  4. **Settings:**
     - poll interval and idle threshold
     - totals retention
     - launch at login (`SMAppService.mainApp`)
     - permission status, with buttons that open the right System Settings pane (Accessibility deep link `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`)
     - "Delete all data"
- **Onboarding:**
  - First run explains the two permissions and checks `AXIsProcessTrusted()`.
  - The Chrome Automation prompt appears on the first Chrome query.
  - If Automation is denied (error -1743), keep working with domain null and show a non-blocking banner explaining how to enable it.

## Encryption at rest
- **Columns:** encrypt `segments.title` and `segments.domain` with CryptoKit AES.GCM. Use a random nonce for each value and store the combined box as a BLOB. Keep `app_name` and `bundle_id` as plaintext.
- **Hourly keys:** use one 256-bit key per hour bucket of `segments.start`. Store keys as generic-password items in the login Keychain, named `local.daylog.seg.<yyyyMMddHH>`. Let the default access list (this app only) apply.
- **Purge (crypto-shredding):** after rolling up and deleting segments older than 48h, delete the Keychain keys for those hours. A segment whose key is missing reads as "[expired]" and is deleted on the next purge.
- **Totals:**
  - `daily_totals` for the domain kind stores `key = HMAC-SHA256(totalsKey, domain)`.
  - A `domain_labels(hmac, label_box)` table holds each domain name encrypted with `totalsKey`.
  - `totalsKey` is one long-lived Keychain item, `local.daylog.totals`.
  - Delete a label when its last total expires.
- **In memory:** decrypt in memory only. Searching and filtering the 48h timeline happens in memory.
- **Delete all data:** removes the database and every `local.daylog.*` Keychain item.
- **Tests:**
  - an encrypt/decrypt round trip
  - the purge removes the keys, and raw bytes from a purged hour cannot be decrypted
  - totals group correctly through the HMAC
  - a `strings` scan of the database file finds no plaintext titles or domains
- **Optional:** an LAContext Touch ID prompt before showing the main window, off by default. Document that it locks the UI only and is not a cryptographic protection.D

## Verification
- **Unit tests:** segment state transitions, rule matching, domain extraction (including incognito and internal pages), purge and rollup math with an injected clock, and the combined live-plus-totals breakdown query.
- **No-network build check:** a script that fails if the built binary links Network.framework or references NSURLSession, CFSocket, or `nw_` symbols (checked with `otool -L` and `nm -u`). Run it as part of the build script.
- **Manual test checklist in the README:**
  - grant and deny each permission
  - lock and unlock, sleep and wake
  - Chrome incognito
  - a block rule applying live and retroactively
  - a 48h purge simulated by moving the clock forward
  - Time Machine exclusion, verified with `tmutil isexcluded`
  - LuLu showing zero connection attempts

## Deliverables
- Source, build script that produces a signed `.app` and runs the no-network check, and tests.
- README covering build, signing, permissions, the data location, and how to fully uninstall: delete the app and data folder, then `tccutil reset Accessibility <bundle-id>` and `tccutil reset AppleEvents <bundle-id>`.
- Bundle ID: `local.daylog`, or ask me.

## Decisions left to the agent
UI layout details, icons, schema tweaks, the module structure, and anything not specified above. Prefer the simpler option and note the choice in the README.



