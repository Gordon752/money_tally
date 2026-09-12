# Ledger and Settings polish — September 12, 2026

User-approved scope: prevent long currency amounts from fading in monthly ledger
summaries and transaction rows; open Settings Help & Guides directly on the
existing website; move technical sync activity behind Last successful sync.

- MoneyText has opt-in measured fitting using the current font, locale, direction,
  and accessibility text scaler. Unchanged consumers retain their prior behavior.
- Monthly summaries retain three columns when amounts fit at a readable size
  (13→12 compact, 15→13 regular). Otherwise they show label/value rows.
- Transaction primary amounts gain space when needed, fit from 16 to 14, then
  move below the payee if necessary. Rows can grow beyond their 72-point minimum.
  Extreme amounts wrap rather than lose currency symbols, signs, or digits.
- Settings Help & Guides uses the existing external browser link and its
  failure/copy-link handling. Replay Onboarding is unchanged and remains offline.
  The shared guide page remains available from the onboarding flow.
- Last successful sync opens Sync Details with status, timestamp, and diagnostic
  activity. Main settings still shows sync errors and actions. No scheduling,
  telemetry collection, cloud requests, or synchronization behavior changed.

Verification: 1,231 tests passed; static analysis clean; diff whitespace checks
clean. 72 new layout cases cover PHP values through trillions, negative amounts,
320/393/1024 widths, normal/compact summaries, and text scales 1/1.6/2. Every
visible amount character is checked against its rendered bounds. Existing ledger
metadata alignment, support link, onboarding, and sync settings tests also pass.
Synthetic phone previews inspected for PHP 160,000.00 and PHP 123,456,789.00.

No app-data changes, device installation, App Store upload, commit, or push were
part of this implementation pass. Physical-device review is still required.

## Subsequent authorized local installation

Built signed version 1.0.0 (5) for iOS and macOS in the persistent non-iCloud
workspace `~/Library/Developer/TrackmarkBuilds/Local-ledger-1.0.0-5/source`.
The previous temporary build cache was no longer present, so both platforms
required fresh native builds. Both signed bundles passed deep/strict verification.

Installed over the existing apps on GiPhone and GiPad without uninstalling.
CoreDevice verified version 1.0.0 / bundle version 5 on each and confirmed launch.
Installed Mac build 5 at `/Applications/Trackmark Money 2.app`, preserving the
previous bundle at
`~/Library/Developer/TrackmarkBuilds/Local-ledger-1.0.0-5-backup/Trackmark Money 2.app`.
The installer did not reset data containers or preferences. No TestFlight upload,
commit, or push was performed. User visual checks remain separate from installation.
