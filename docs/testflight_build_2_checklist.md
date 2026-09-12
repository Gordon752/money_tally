# TestFlight build 2 — polish and device verification

Prepared September 11, 2026. Target: Trackmark Money 1.0.0 (2), iOS/iPadOS and macOS.

## Included changes

- Onboarding Screen 2 retains every explanation and example, with inline definitions,
  one set of example column labels, and a separate 16-point navigation gap.
- New expense/income sheets focus Amount even when the default account is None.
- Selecting an account returns focus to Amount without changing the entered value.
- Existing pending Mac Finance category and privacy-manifest corrections are retained.

## Completed local checks

- Selected developer directory remains Xcode.app; Xcode 26.6 (17F113).
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: 1,060 tests passed.
- Focus regressions cover None, specific account, and last-used account on iOS/macOS.
- Onboarding tests include first-run/replay, realistic safe areas, small and large
  screens, dark mode, enlarged text, and reduced motion. Normal 375×812 and 393×852
  portrait layouts and standard tablet/desktop layouts require no Screen 2 scroll.
  Tiny windows, landscape phones, and accessibility text may scroll safely.
- Phone and Mac rendered layouts inspected. User confirmed both polish items work;
  exact physical-device coverage was not specified.

## External TestFlight release gates

Current progress: iOS build 2 archived, signature verified, uploaded successfully,
processed by Apple, and submitted for TestFlight beta review. The build is attached
to Private Beta (external, no testers/public link) and Gordon — Internal (existing
owner-only group). Beta description, review contact, access instructions, privacy
link, and What to Test notes are saved. Mac build 2 archive is complete and signed
for both arm64 and x86_64; Finance category and bundled privacy manifest verified.
Mac upload completed successfully through the same App Store Connect distribution
method. Mac processing completed and its beta-review submission succeeded (Apple
shows Remove from Review). Both builds are attached to Private Beta and Gordon —
Internal. At the latest check both builds remained Waiting for Review. One
user-authorized external tester (Gordon's wife) was added to Private Beta and
showed No Builds Available. No public invitation link was enabled.

Archives and logs are retained outside the Documents/iCloud source tree at
`/Users/gordonbowles/Library/Developer/TrackmarkBuilds/TestFlight-1.0.0-2/`.
The archived source hashes for the three changed app files match the tested checkout.

- Archive and verify signed build 2 separately for iOS and macOS.
- Upload using App Store Connect distribution, **not TestFlight Internal Only**.
- Verify Apple processing succeeds and the uploaded build number is 2.
- Supply beta description, feedback email, review contact, and access instructions.
- Create/use a private external testing group; do not enable a public invitation link.
- Submit for TestFlight beta review. This does not publish to the App Store.
- Record Apple's result before declaring the external build ready to install.

## Device checks after the new build is available

Use iPhone, iPad, and Mac. Record device/OS, build, actions, expected result, actual
result, and any screenshot.

User confirmed both polish items work in response to the build-2 iPhone/iPad check:
Screen 2 fits comfortably and Amount focus works with None and after account selection.
Exact device coverage was not specified; do not infer that all three devices passed.
User confirmed version 1.0.0 (2) is installed on iPhone, iPad, and Mac. Device models
and OS versions were not supplied. The following manual results are user-reported:

- Created zero-balance Beta Test account on iPhone; appeared on iPad and Mac.
- Created cleared $10 income, note Sync test, on iPhone; transaction and balance
  matched on both other devices.
- Edited that income to $12 on iPad; both other devices showed one $12 transaction
  and a $12 balance, without duplication.
- Deleted that disposable income on Mac; all devices returned to $0. After closing
  and reopening all three apps, the transaction stayed deleted.
- Created $5 Pending test expense as pending on iPhone; pending status synced.
- Cleared that expense on iPad; both other devices updated without duplication.
- Created zero-balance Beta Transfer account on Mac and transferred $2 from Beta
  Test to Beta Transfer; all devices matched Beta Test -$7 and Beta Transfer $2.

- Added cleared $100 Funds test setup income on iPhone; Beta Test $93 and Beta
  Transfer $2 matched on all three devices.
- Created Beta Fund on iPad, funded by Beta Test, with no target; $0 reservation
  and unchanged $93 account balance matched on all three devices.
- Allocated $20 on Mac; all devices showed Fund $20, account balance $93, available $73.
- Spent cleared $5 from Beta Fund on iPhone, note Fund spending test; all devices
  showed Fund $15, account balance $88, available $73.
- Returned $5 reserved money on iPad; all devices showed Fund $10, unchanged
  account balance $88, available $78.

- Created Beta Goal on Mac with Beta Test funding account, $30 target, default
  goal type, and no deadline; all devices showed $0 toward $30 with account balance
  $88 and available $78 unchanged.
- Allocated $15 to Beta Goal on iPhone; all devices showed Goal $15 toward $30,
  Fund $10, account balance $88, and available $63.
- Returned $5 from Beta Goal on iPad; all devices showed Goal $10 toward $30,
  Fund $10, account balance $88, and available $68.

Basic creation/edit/deletion/reopen sync, pending-to-cleared sync, this transfer
case, Fund allocation/spending/return, and Goal creation/allocation/return passed.
Additional user-reported build-2 checks:

- Creating a weekly schedule with an explicitly selected start date appeared on
  all three devices. An earlier October date was corrected by editing; the cause
  of the initial date choice was not established as a bug.
- Three $4 test payments reconciled the observed $76 balance/$56 available.
  User believes all three were manually paid; the earlier duplicate-payment
  concern remains inconclusive rather than a confirmed defect.
- Skip synced without changing $76/$56. Paying the next occurrence with an
  actual $3 amount produced one new payment and matched $73/$53 everywhere.
- Offline iPhone $1 expense gave $72 locally while other devices stayed $73;
  reconnect synced it exactly once to all three ($72/$52), persisting on reopen.
- With iPhone offline again, Mac deletion synced to iPad. Reconnecting and
  reopening iPhone removed the expense and did not resurrect it; all matched
  $73 balance/$53 available with $20 reserved.
- Custom reminder delivered simultaneously on both Central-time mobiles.
  Mac (Eastern) did not deliver; missing native Mac configuration identified.
  Preset time visibility and travel behavior are tracked in reminder_timezones.md.
- Notes on the $100 income were present on iPhone, Mac, and iPad. No missing-note
  defect was established from this check.
- iPhone backup exported to Files and was accepted by Import Backup validation,
  reaching the Restore Backup preview. User was instructed to Cancel, not restore;
  no actual restore was performed or authorized in this check.

Fresh-user, actual restore/recovery, Mac reminder delivery, and travel behavior
remain open. Test records remain in place. Subsequent reminder implementation
changes have not been distributed and must not be confused with build-2 results.

1. **Polish:** replay all onboarding pages. Screen 2's closing sentence and navigation
   must both be visible with comfortable separation at normal text size. Increase
   text size and verify readable scrolling, no clipping, and reachable navigation.
2. **Amount focus:** default account None → open Expense and Income → type immediately.
   Choose an account before entering an amount, and after entering one. Amount should
   regain focus and retain its value. Repeat with specific and last-used defaults.
3. **Basic persistence/sync:** with an explicitly identified disposable test record,
   create/edit/delete on one device, verify the other two, then reopen all three.
   Deleted records must not reappear and edits must not be duplicated.
4. **Financial behavior:** verify pending → cleared, transfers, Fund spending/returns,
   Goal funding, and the corresponding Balance/Reserved/Available figures using a
   small agreed test case. Do not mix synthetic bulk data with personal finances.
5. **Schedules/reminders:** verify Paid, Skip, actual amounts, no duplicate occurrence,
   and a short test notification on each physical platform with permission enabled.
6. **Offline/reconnect:** use a controlled disposable fixture to verify a pending edit
   reaches the other devices once online and does not resurrect a deleted record.
7. **Fresh user:** use a separate test account/device to exercise onboarding and sign-in.
   Reinstalling alone may retain Keychain authentication and is not a fresh-user test.
8. **Recovery:** make and validate a current backup before considering a repeat of
   reset/restore or reinstall tests. Do not reset the shared dataset, uninstall apps,
   clear Keychain, or replace financial records without explicit fresh confirmation.

The previous build's successful sync/restore/reinstall tests are historical evidence,
not substitutes for checking the newly distributed build. Automated synthetic stress
tests are not measurements of release UI performance or production sync costs.
