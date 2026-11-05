# DayLog

A personal macOS menu bar app that records which app, window title, and Chrome website you're using, and shows a 48-hour timeline plus time breakdowns by app and by website. Everything stays on this Mac.

- **No network.** The app makes no network connections, and the build fails if the binary links Network.framework or references URLSession, CFSocket, or `nw_` symbols.
- **No screenshots, no keystrokes.** It needs only Accessibility (window titles) and Automation for Google Chrome (active tab domain). Screen Recording and Input Monitoring aren't used.
- **Encrypted, short-lived detail.** Window titles and domains are encrypted with a key per hour (AES-GCM, keys in your login keychain). After 48 hours, entries are rolled into daily per-app and per-domain totals, deleted, and their hour keys are destroyed.

Requires macOS 14 or later. The full spec is in [PLAN.md](PLAN.md).

## Build

Prerequisites: Xcode (tested with 27.2) and [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46.0 or later (`brew install xcodegen`).

```sh
./build.sh "DayLog Local Signing"   # name of your code-signing certificate
```

The script generates `DayLog.xcodeproj` from `project.yml`, runs the unit tests, builds Release, runs the no-network check (`scripts/check-no-network.sh`), and verifies the signature, hardened runtime, and Apple Events entitlement. The result is `build/DayLog.app`. Copy it to `/Applications` for daily use; launch at login works best from there.

`./build.sh -` signs ad-hoc. That's fine for a quick try, but macOS ties permission grants and keychain access to the signature. With ad-hoc signing, every rebuild loses the Accessibility and Automation grants and triggers keychain prompts. Use a stable identity for anything longer.

### Working in Xcode

Run `xcodegen generate`, then open `DayLog.xcodeproj`. The project file is generated and gitignored, so put target and build-setting changes in `project.yml`; regenerating overwrites anything edited in Xcode's project editor. To give Xcode builds the same stable identity, run `cp Local.xcconfig.example Local.xcconfig` and set your certificate name in it. `Local.xcconfig` is gitignored, and `build.sh`'s argument overrides it.

## Signing

macOS remembers Accessibility, Automation, and keychain access per code signature. Signing every build with the same certificate keeps those grants across rebuilds.

### Self-signed certificate (free, recommended for personal use)

1. Open **Keychain Access**.
2. Choose **Keychain Access → Certificate Assistant → Create a Certificate…**
3. Set the name to `DayLog Local Signing`, Identity Type to **Self-Signed Root**, and Certificate Type to **Code Signing**. Click **Create**.
4. Confirm codesign can see it: `security find-identity -p codesigning` lists `DayLog Local Signing`. It may be marked `CSSMERR_TP_NOT_TRUSTED`; codesign can still use it. To clear that, open the certificate in Keychain Access, expand **Trust**, and set **Code Signing** to **Always Trust**.
5. Build with `./build.sh "DayLog Local Signing"`.

The first build may ask permission for codesign to use the key. Choose **Always Allow**.

### Developer ID

If you have an Apple Developer account, pass the full identity name:

```sh
./build.sh "Developer ID Application: Your Name (TEAMID)"
```

Notarization isn't needed for an app you build and run yourself.

## Permissions

| Permission | Why | If denied |
|---|---|---|
| Accessibility | Read the focused window's title (`AXTitle`). | Only app names are recorded. The menu bar icon shows a warning triangle. |
| Automation → Google Chrome | Ask Chrome for the front window's mode and active tab URL. Only the hostname is kept (with `www.` stripped); the URL is never written to disk. | Domains aren't recorded. Chrome window titles are dropped too, because DayLog can't tell whether a window is incognito. A banner explains how to turn it on. |

The first run shows an explanation and doesn't record until you click **Start Recording**. macOS asks for Chrome Automation the first time Chrome is in front while recording. Settings → Permissions shows the status of both and opens the right System Settings pane.

## How it works

- **Capture:** Every 5 seconds (configurable), DayLog reads the frontmost app, the focused window's title, and the Chrome domain when Chrome is in front, then applies block rules. After 2 minutes without input (configurable), time is recorded as idle and back-dated to the last input.
- **Not recording:** Nothing is recorded while the screen is locked, the Mac is asleep, you've switched to another user, or recording is paused (15 minutes, 1 hour, or until resumed). These periods show as gaps in the timeline.
- **Segments:** One row is kept open while app, title, domain, idle, and blocked are unchanged. Its end time is written at least every 60 seconds, so a crash loses at most a minute.
- **Incognito:** If Chrome reports the front window is incognito, both title and domain are stored as empty.
- **Block rules:** Rules can match an app (bundle ID), a domain (including subdomains), a title substring (case-insensitive), or a title regex. They're applied at capture time: matching time is stored as "Blocked" with no bundle ID, title, or domain. When you add a rule, DayLog offers to delete existing entries it matches. You can also right-click any timeline entry to block or delete it.

## Data

- **Location:** `~/Library/Application Support/DayLog.noindex/daylog.sqlite`. The `.noindex` suffix keeps it out of Spotlight. The directory is mode `0700` and the database `0600`. The directory is excluded from Time Machine; check with `tmutil isexcluded ~/Library/Application\ Support/DayLog.noindex`.
- **Keychain:** Generic-password items in your login keychain named `local.daylog.seg.<yyyyMMddHH>` (one key per UTC hour) and `local.daylog.totals`.
- **Retention:** Purges run at launch, on wake, and hourly. Each purge rolls entries that ended more than 48 hours ago into `daily_totals` (idle excluded, blocked time counted as "Blocked"), deletes them, deletes the hour keys no remaining entry needs, and vacuums the database. Daily totals are kept 90 days by default (30 days to forever, in Settings).
- **Totals:** Domain totals are keyed by `HMAC-SHA256(totalsKey, domain)`. The readable domain names live in `domain_labels`, encrypted with the totals key, and are deleted when their last total expires. App names and bundle IDs are stored in plaintext.
- **Delete all data:** Settings → **Delete All Data…** removes the database folder and every `local.daylog.*` keychain item.

## Uninstall

1. Quit DayLog and delete `DayLog.app`.
2. `rm -rf ~/Library/Application\ Support/DayLog.noindex`
3. Delete the keychain items: in Keychain Access, search for `local.daylog` and delete the results. Or use Settings → Delete All Data before step 1.
4. Reset the permission grants:
   ```sh
   tccutil reset Accessibility local.daylog
   tccutil reset AppleEvents local.daylog
   ```
5. If you turned on launch at login, also remove DayLog under System Settings → General → Login Items.

## Tests

```sh
xcodegen generate
xcodebuild test -project DayLog.xcodeproj -scheme DayLog -destination "platform=macOS,arch=$(uname -m)"
```

The tests cover segment state transitions, rule matching, domain extraction (including incognito and internal pages), purge and rollup math with an injected clock, the combined live-plus-totals breakdown, and encryption: round trip, crypto-shredding (a purged hour's raw bytes can't be decrypted), HMAC grouping of totals, and a scan of the database file for plaintext titles and domains. Tests use an in-memory key store and a temporary database, so they never touch your keychain or real data.

## Manual test checklist

- [ ] **Accessibility granted:** Titles appear in the timeline.
- [ ] **Accessibility denied:** Remove DayLog in System Settings → Privacy & Security → Accessibility. Only app names are recorded, and the icon shows a warning triangle.
- [ ] **Chrome Automation granted:** Domains appear for Chrome entries.
- [ ] **Chrome Automation denied:** Turn it off in Privacy & Security → Automation. The banner appears, recording continues, and Chrome entries have no domain or title.
- [ ] **Lock and unlock:** Lock the screen for over a minute. A "Not recording" gap appears.
- [ ] **Sleep and wake:** Same as lock: a gap appears, and a purge runs on wake.
- [ ] **Chrome incognito:** Entries for an incognito window have no title or domain.
- [ ] **Block rule, live:** Add a rule for something you're using. New time records as "Blocked".
- [ ] **Block rule, retroactive:** Accept the prompt. Matching entries disappear from the timeline.
- [ ] **48h purge:** Quit DayLog and relaunch with the clock moved forward: `DAYLOG_CLOCK_OFFSET_HOURS=49 /Applications/DayLog.app/Contents/MacOS/DayLog`. Earlier entries disappear from the timeline but still count in Breakdown, and their `local.daylog.seg.*` keychain items are gone. Entries recorded in this mode carry future timestamps, so use Delete All Data afterwards.
- [ ] **Time Machine:** `tmutil isexcluded ~/Library/Application\ Support/DayLog.noindex` prints `[Excluded]`.
- [ ] **No network:** [LuLu](https://objective-see.org/products/lulu.html) shows zero connection attempts from DayLog over a day of use.

## Design decisions

These are choices PLAN.md left open.

- **Project:** XcodeGen (`project.yml`) plus `xcodebuild`, with no checked-in `.xcodeproj`. Targets are `DayLogCore` (all testable logic), `DayLog` (the app), and `DayLogCoreTests`.
- **Static core library:** `DayLogCore` is a static library rather than an embedded framework. Hardened runtime's library validation rejects an embedded framework when the app is signed without a Team ID (ad-hoc or self-signed). Linking statically avoids that without turning off library validation.
- **Hostnames only:** No public-suffix list. Domains are the hostname with `www.` stripped, so `docs.google.com` and `mail.google.com` are separate. A domain block rule covers subdomains. `chrome://`, `about:`, `devtools://`, and extension pages record as `chrome`. `file://` records as `file`.
- **SQLite:** The system SQLite3 C API with no third-party dependencies. `journal_mode=DELETE`, `secure_delete=ON`, and `VACUUM` after any purge that deleted rows.
- **Hour keys in UTC:** Daylight-saving changes never make two hours share a key. Daily totals use your local calendar day, and entries that cross midnight are split.
- **Idle:** Idle time is stored as entries without app, title, or domain, shown as gaps and excluded from totals. Paused, locked, asleep, and switched-out time has no entries at all.
- **Missed polls:** If polls stop for more than 30 seconds (or 3× the poll interval) without a sleep or lock notification, the open entry ends at the last poll instead of stretching over the gap.
- **Main window:** AppKit-managed, so it can open at first launch and from the popover in an app with no Dock icon.
- **Touch ID lock:** Optional (Settings), off by default. It only locks the window; it's not encryption.
- **Logging:** `os_log` records only counts, states, and error codes, never titles, URLs, or domains.
