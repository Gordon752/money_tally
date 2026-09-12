# Reminder timezone implementation and release checks

## Behavior

- Reminder time is independent of transaction time and is always shown, including
  Same day and other preset offsets. Selecting an enabled preset opens the editor
  to review the clock and timezone before saving. No alert keeps its previous
  clock/zone so toggling reminders off does not erase the user's choice.
- Follow device timezone is the legacy/default choice. On Apple platforms a
  native bridge replaces the plugin's pinned calendar trigger with floating
  year/month/day/hour/minute components. It preserves notification content,
  identifier, and tap payload. If replacement fails, the pinned request is
  cancelled and a visible error is reported rather than retaining wrong timing.
- Fixed reminders store an IANA timezone, not a numeric UTC offset. Initial
  picker choices cover major US zones, Arizona, Hawaii, Alaska, and UTC. Other
  valid IANA identifiers remain readable and editable if already stored.
- Fixed reminders resolve the occurrence's civil date and reminder clock in the
  selected zone. Calendar-day offsets are applied before timezone conversion.
  Details show the equivalent date/time on the viewing device.
- Local timezone conversion cache refreshes on app resume. Apple floating
  triggers, not a background Flutter task, are responsible for following travel
  while the app is suspended. Physical travel/timezone-change delivery is a
  release test, not proven merely by passing Dart tests.

## Mac repair and diagnostics

macOS now supplies Darwin initialization and presentation settings and requests
alert/badge/sound permission. Initialization failure retains the real scheduler
for retry rather than permanently replacing it with a no-op. Errors and denied
permission appear in Settings → Notifications; no notification failure resets
financial data. App restart is the recovery instruction.

## Compatibility

The new optional `reminderTimeZone` field is included in model copy/JSON,
scheduled cloud definitions, and backup validation. Missing/null is local time.
Normal Firestore schedule writes merge, so an older client's omitted field does
not by itself delete the remote timezone. **Older builds still cannot honor that
timezone locally** and can export a backup without understanding it.

Do not activate fixed reminders in a mixed-build household. Update every synced
device before selecting a fixed zone; the editor displays this prerequisite.
No server-side client-version enforcement was deployed. This is an explicit
release prerequisite, not a claim that old-client scheduling is compatible.

Backups with fixed-zone schedules use schema 8, which build 2 rejects as newer.
Local-only reminder datasets remain schema 7 for compatibility. The new validator
accepts and migrates existing supported formats without changing saved clocks.
An unknown IANA zone fails validation/planning; it is not silently treated as UTC.

## Test cases without requiring travel

Gordon expects to remain in Central for weeks. Keep the actual devices' settings:
Mac Eastern, iPhone/iPad Central. Do not alter real bank/settlement records.

1. Use a disposable reminder a few minutes ahead, fixed Eastern. All three must
   notify at the same instant; Mac's displayed clock is one hour ahead of mobiles.
2. Repeat fixed Central and verify the Mac preview converts correctly.
3. Verify a local-time reminder on the two Central mobiles; no forced app closure
   is necessary. Separately verify Mac alert/banner/sound and notification tap.
4. The real-world planner fixture is Thursday 11:40 AM America/New_York → Thursday
   10:40 AM America/Chicago in winter and summer. It schedules a reminder only,
   never an automatic financial transfer. No real reminder was created by this work.
5. Use a simulator/dedicated test device for timezone changes while backgrounded
   and terminated, then reopen; confirm one alert, no duplicate, and preserved
   Paid/Skip cancellation. Do not change Gordon's active devices to simulate travel.
6. Verify across DST boundaries and date offsets, fixed-zone edit/reopen/sync,
   backup export/preview, denied permissions, and native registration failure.

Build 2's earlier mobile-reminder passes do not establish delivery for this new
native trigger implementation. A fresh signed build and physical checks are still
required before declaring the feature release-verified. No upload or install is
part of this implementation pass.

## Verification results

- `flutter analyze --no-pub`: no issues.
- Full `flutter test --no-pub`: 1,077 passed. Includes native-channel requests for
  both Apple platforms, timezone/JSON/cloud serialization, backup format guards,
  new UI selection, and existing financial/sync regressions.
- Reminder layout tests: 11 passed; phone render inspected. Coverage includes
  narrow phones, keyboard, enlarged text, tablets, desktop, and dark mode.
- `tool/check_reminder_calendar.swift`: passed against Apple's actual
  UNCalendarNotificationTrigger. An existing floating trigger changed instant
  with the process-local timezone; fixed Eastern retained its instant and mapped
  to 10:40 Central. No notifications were registered and no system setting changed.
- Final macOS Debug build succeeded with `CODE_SIGNING_ALLOWED=NO`.
- iOS AppDelegate, iCloud backup bridge, and SceneDelegate passed Swift typecheck
  against the iOS SDK and built plugin frameworks (one pre-existing cast warning).
- Full local iOS packaging remains unverified: Flutter's embedded-framework
  ad-hoc signing repeatedly rejected Finder metadata in Documents/iCloud. The
  final signed release must use a fresh clean build folder outside that tree,
  as build 2 did. An earlier Mac debug build succeeded signed; final packaging
  also hit the same metadata issue and was verified unsigned instead.
- CocoaPods refreshed the iOS/macOS lockfiles to include dependencies already in
  the existing Flutter dependency graph. No new Dart package was introduced.

The implementation checks above did not install or launch production apps.

## Authorized local device installation — September 11, 2026

- Built signed release version 1.0.0 (3) for iOS and macOS in a fresh, non-iCloud
  workspace: `/private/tmp/trackmark-reminder-local.rM5iDh/source`.
  Both builds passed deep/strict code-signature verification. This supersedes
  the earlier packaging blocker; no dependency-lock changes were needed.
- Installed over build 2 on GiPhone and GiPad without uninstalling. Both launched
  successfully, and CoreDevice reports installed bundle version 3.
- Installed Mac build 3 at `/Applications/Trackmark Money 2.app`, replacing the
  TestFlight copy. Finder moved the protected previous app into
  `/Users/gordonbowles/Library/Developer/TrackmarkBuilds/Local-reminder-1.0.0-3-backup/Trackmark Money 2.app`.
  The replacement passed signature verification. The older separate
  `/Applications/Trackmark Money.app` was not changed.
- Installers did not reset or modify app-data containers or preferences.
  Device timezones were not changed. No TestFlight upload was performed.
- Live reminder delivery was initially pending after installation; see the
  subsequent user-reported physical test results below.
- Mac build 3 launched and eventually displayed the existing dashboard/accounts.
  Startup was delayed while requesting notification authorization; the system
  log returned `didGrant: 0 hasError: 1`, including repeated requests during
  reconciliation. Gordon subsequently found Mac notifications were off and
  enabled them. The app's permission warning cleared after quitting/reopening.
  Permission-state refresh without restart and repeat-request behavior remain
  follow-up items; the delivery test itself subsequently passed.

## Build 3 physical reminder results — user reported

- **PASS: Follow device, force-closed mobiles.** Gordon created a scheduled
  transaction on GiPhone with Follow device timezone, opened GiPad to sync it,
  then force-closed both apps. Both devices delivered the reminder. Both were
  in Central; this does not establish behavior after an actual timezone change.
- **PASS: Fixed Eastern, three-device delivery.** Gordon saved the short-ahead
  Eastern reminder test and confirmed the Mac, GiPhone, and GiPad all alerted
  at the same instant. Mac remained Eastern; both mobiles remained Central.
- **PASS: Fixed Central, three-device delivery.** After selecting fixed Central
  and repeating the short-ahead reminder, Gordon confirmed it worked; the Mac
  was minimized. The initial attempt had remained on Follow device (confirmed
  in the editor and by the Mac's Device time label), so the non-simultaneous
  result was not evidence of a fixed-Central or timezone-sync defect.
- Still pending: physical travel/timezone-change behavior and live
  cancellation/edit checks on build 3. Automated DST tests
  are not equivalent to physical delivery across a DST transition.
