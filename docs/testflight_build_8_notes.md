# TestFlight 1.0.0 (8)

## What to Test

This build improves cloud-sync reliability and account deletion, including
clearer error messages and recovery after an interrupted deletion attempt.

- Check that existing accounts and transactions remain unchanged after updating.
- Check Sync now, normal entry and editing, and reopening across your devices.
- If a sync or deletion error occurs, report the exact message and steps.
- Account deletion permanently removes your Trackmark sign-in and its data.
  Do not test deletion with data you want to keep. Use only a disposable test
  sign-in if you choose to exercise that flow.

Earlier reminder timezone choices, large-currency layout improvements and form
polish remain included.

## Verification and distribution intent

- 1,249 Flutter tests passed; analysis found no issues.
- Owner verified build 8 launch, existing data and Sync now on Mac, phone and iPad.
- Disposable-account cloud deletion completed; owner confirmed a fresh sign-in
  did not restore old data and Sync now worked.
- Upload iOS/iPadOS and macOS build 8 and submit to existing Private Beta group.
  Leave existing builds available. This is not an App Store release submission.
- Source and archives: `/Users/gordonbowles/Library/Developer/TrackmarkBuilds/TestFlight-1.0.0-8`.
- iOS/iPadOS upload succeeded. External submission completed with the notes
  above and Automatically notify testers enabled. App Store Connect verified
  **Testing** in Private Beta; build ID `9bacd3cf-98d6-4932-858f-12caddc3a8de`.
- macOS upload succeeded at 18:50:25 Eastern on September 12, 2026. External
  submission completed with the same notes and automatic notifications enabled.
  App Store Connect verified **Waiting for Review** in Private Beta; build ID
  `27d27be3-9597-46ad-af31-a0f54b532e0e`.
- Both platform build 8 entries are in Private Beta. Older builds 2 and 5 remain
  Testing; no older build was removed or expired. No App Store release was
  submitted. No commit or push was performed.

## Internal tester assignment correction

The owner could only see builds 1, 2 and 5 in TestFlight because build 8 had
initially been assigned only to Private Beta. With explicit owner approval,
added both iOS and macOS build 8 to **Gordon — Internal**
(`1bb79a62-d472-4df2-a275-8f1c0b9677b3`). Verified both build detail pages list
Gordon — Internal and Private Beta, with one tester each. The Mac external review
was left in place. For future uploads, verify both internal and external group
assignments before telling the owner the update is available to his account.
