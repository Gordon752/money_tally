# Account deletion hardening — September 12, 2026

## Status and scope

Implemented and tested locally. **Backend deployed with explicit owner approval
on September 12, 2026. Final build 8 was installed and owner-verified on all three
devices, uploaded for both platforms, and submitted to Private Beta. iOS is
Testing; macOS is Waiting for Review. See `testflight_build_8_notes.md`.
No real account or production data was deleted. Changes are not committed or pushed.**
Existing ledger/settings polish changes were preserved.

## Authorized local build 6 installation

The owner authorized building and installing on Mac, GiPhone, and GiPad.
Version override: **1.0.0 (6)**; no TestFlight upload is included.
Build source and logs are preserved at
`/Users/gordonbowles/Library/Developer/TrackmarkBuilds/Local-deletion-1.0.0-6`.
The four changed auth/store/sync source files were compared with the working
repository and match exactly. Locked dependencies were enforced.

- iOS release succeeded, with deep/strict signature verification. Installed
  over build 5 on GiPhone and GiPad without uninstalling. CoreDevice confirmed
  bundle version 6 and successful launch on both devices.
- **Owner confirmed existing data looks normal and Sync now works on both
  mobile devices after installation.**
- Mac release succeeded and passed deep/strict signature verification.
  Installed and launched **1.0.0 (6)** at `/Applications/Trackmark Money 2.app`.
  Preserved the previous build 5 bundle at
  `/Users/gordonbowles/Library/Developer/TrackmarkBuilds/Local-deletion-1.0.0-6/previous-macos/Trackmark Money 2.app`.
  The installer did not change app-data containers or preferences. The owner
  subsequently confirmed that Mac sync works as well.
- No account deletion was exercised. Disposable-account deletion testing remains
  a separate step. The owner confirmed his wife's test sign-in has no real data
  and authorized using it when she is available. Do not test Gordon's real account.

## Production deployment verification

### Build 7: visible deletion failures

Josephine confirmed build 6 retained her only Cash account and Sync now worked.
Cancelling the initial deletion confirmation preserved the account. She then
typed DELETE and completed Apple verification, but the app returned to Accounts
with Cash still present and no visible error. Read-only production checks found
no deletion-function request or new deletion marker since this test began.
This was not a successful deletion. Build 7 subsequently exposed the underlying
failure: Apple authorization revocation returned `operation-not-allowed`.

Reproduced a UI bug: AuthGate's full-screen deletion progress unmounts Settings,
so Settings' error snackbar cannot be shown after the asynchronous failure.
With owner approval, AuthGate now presents an acknowledgement dialog after
loading ends. It handles typed and unexpected errors; raw internal exceptions
are not displayed. Firebase failures include the operation stage and a bounded
SDK code, not tokens, emails, authorization codes or raw service messages.
Pre-request typed failures keep the original recovery behavior; unconfirmed
requests continue to block sync. No deletion protection was bypassed.

Four error-visibility assertions failed before the fix and passed afterward.
Full Flutter suite: **1,247 passing**; analyze: **no issues**; diff check clean.
Logs: `/tmp/trackmark-deletion-error-regression-before.log`,
`/tmp/trackmark-deletion-error-regression-after.log`,
`/tmp/trackmark-deletion-error-full-tests.log`,
`/tmp/trackmark-deletion-error-analyze.log`.

Built 1.0.0 (7) using the unchanged build-6 native workspace and its existing
`/tmp/trackmark-josephine-build-6` derived-data cache, with
`FLUTTER_APPLICATION_PATH` explicitly pointing to the tested working repository.
Native project and Podfile.lock were compared equal before reuse. Xcode logged
the current repository as the successfully packaged Dart project. Signature,
bundle version and compiled new error-message strings were verified. Build log:
`/tmp/trackmark-josephine-build-7.log`. Installed over Josephine's build 6 without
uninstalling or clearing data. No TestFlight upload or other-device install.
The error-dialog retest passed: it exposed the Apple revocation failure above.
Successful end-to-end deletion remains pending; don't mark deletion acceptance
as passed.

### Apple authorization revocation configuration repaired

Read-only Firebase provider inspection showed Apple enabled, but no Services ID
and an empty Apple OAuth configuration. Apple Developer had an existing Sign in
with Apple key associated with the correct primary app, but no Services IDs.
Firebase's documented token-revocation setup requires these missing settings.

With explicit owner approval on September 12, 2026:

- Registered `com.gordonbowles.moneytally.firebase` (Trackmark Money Firebase
  Authentication), enabled Sign in with Apple, and associated primary app
  `com.gordonbowles.moneytally`.
- Registered domain `money-tally-gordonbowles.firebaseapp.com` and return URL
  `https://money-tally-gordonbowles.firebaseapp.com/__/auth/handler`.
  Reopened the saved Apple configuration and verified both URLs and association.
- Saved the Services ID and existing Apple team/key configuration to Firebase's
  Apple provider using a narrow update mask. Existing enabled state and other
  provider settings were preserved. The existing private key was read directly
  from its saved local file and transmitted only to Firebase over HTTPS, with
  request/response body logging disabled; no key material was copied into the
  repository or conversation. No new key was created or existing key revoked.
- Firebase accepted the update; non-secret read-back verified Apple remains
  enabled and the saved Services ID, team ID and key ID match.

No app rebuild was needed for this configuration repair. No deletion was
initiated by the setup. The owner then retried Josephine's disposable-account
deletion on build 7. The callable returned HTTP 200, and the deletion marker
recorded `completed` at **2026-09-12 22:05:13.095 UTC** (5:05:13 PM Central).
Her phone returned to sign-in. The earlier revocation error remained visible,
but the owner confirmed it disappeared after closing and reopening the app.
This confirms the original revocation blocker was resolved; the leftover error
was a separate client UI issue, not a failed cloud deletion.

### Stale error after successful retry

With owner approval, clear the previous authentication error when starting a
deletion retry and before signing out after confirmed cleanup. Actual failures
still populate the error and preserve the existing recovery protections.
Two new widget regressions reproduce failure followed by successful retry,
covering both pre-request failure and an unconfirmed sent request. Both failed
before the fix and passed afterward, checking that local data is cleared before
sign-out, the recovery marker is removed, and no old error appears at sign-in.
Verification: **1,249 Flutter tests passed**, Flutter analyze found no issues,
and `git diff --check` passed. Logs:
`/tmp/trackmark-stale-deletion-error-tests.log` and
`/tmp/trackmark-stale-deletion-error-analyze.log`.
The owner subsequently signed back into Josephine's account and confirmed old
test data was gone and Sync now worked. Disposable-account deletion and clean
sign-in acceptance passed.

### Final local build 8 installation

With owner approval, built and installed **1.0.0 (8)** on GiPhone, GiPad and Mac.
The unchanged build-6 native workspaces/caches were reused with an explicit
`FLUTTER_APPLICATION_PATH` pointing to the tested current working repository;
native project files were compared before reuse. Both Xcode builds succeeded.
Deep/strict signatures and bundle version 8 were verified, and the iOS profile
includes both target devices. CoreDevice confirmed version 8 and launch on both
mobiles. The Mac was installed and launched at `/Applications/Trackmark Money 2.app`.
No app-data containers were modified or cleared by installation.

Verified artifacts are preserved at
`/Users/gordonbowles/Library/Developer/TrackmarkBuilds/Local-final-1.0.0-8`;
the previous installed Mac build 6 is retained there as
`previous-macos-build-6.app`. Build logs:
`/tmp/trackmark-final-build-8-ios.log` and
`/tmp/trackmark-final-build-8-macos.log`.
Owner confirmed existing data looks normal and Sync now works on all three.
Both platforms were subsequently uploaded and submitted for external testing;
see `testflight_build_8_notes.md`. No commit or push was performed.

Reference: https://firebase.google.com/docs/auth/ios/apple#token_revocation

### Josephine's phone prepared for acceptance testing

On September 12, 2026, the owner reconfirmed that Josephine's Trackmark sign-in
contains only disposable test data. Her phone was paired and Developer Mode
enabled by the owner. The installed app was build 5. A device-authorized copy
of 1.0.0 (6) was built from the preserved build-6 source with Xcode automatic
provisioning/device registration, using separate derived data at
`/tmp/trackmark-josephine-build-6` (log: `/tmp/trackmark-josephine-build-6.log`).
Deep/strict signature verification passed and its provisioning profile includes
her device. Build 6 was installed over build 5 without uninstalling, and
CoreDevice confirmed version 6 and successful launch at 21:38:55 UTC.
Existing-data/Sync now checks and deletion/cancellation tests are still pending;
no deletion was initiated during installation.

Project: `money-tally-gordonbowles`. Deployment order preserved:

1. Firestore rules released at **19:55:57 UTC (3:55 PM Eastern)**. Read-back
   source matches the locally tested `firestore.rules` exactly.
2. `resumeTrackmarkAccountDeletion` became **ACTIVE at 20:00:07 UTC**.
   Initial creation hit Eventarc service-agent permission propagation; verified
   `roles/eventarc.serviceAgent`, then retried successfully. The explicit retry
   billing acknowledgement was limited to this function's deployment.
3. `deleteTrackmarkAccount` updated and became **ACTIVE at 20:02:06 UTC**.

Verified both functions use Node.js 22, `us-central1`, a 540-second timeout,
and a maximum of two instances. Verified the recovery trigger in `nam5`:
Firestore document creation, default database/namespace, path pattern
`accountDeletions/{uid}`, and `RETRY_POLICY_RETRY`. Eventarc destination matches
the recovery function. Runtime identity has data/auth access plus Eventarc
receiver and Cloud Run invocation roles; the worker has no public invoker grant.

The deployed callable rejected an empty unauthenticated request with HTTP 401
and `UNAUTHENTICATED`, before entering deletion logic. The operator read-only
check found **zero pending deletion requests**. No synthetic deletion markers
or financial records were written to production for verification.

The owner confirmed that **Sync now works after deployment**.
Apple-authenticated deletion and interrupted cleanup
on real devices remain untested until a disposable account is available.
An automatic pending-request/failure alert was configured in the follow-up below.
End-to-end synthetic alert delivery was subsequently confirmed by the owner.

## Deletion monitoring follow-up

With owner approval, deployed `monitorTrackmarkAccountDeletions` at
20:49:41 UTC on September 12, 2026. Node.js 22, us-central1, 256 MiB,
60-second timeout, maximum one instance. Its authenticated Cloud Scheduler job
is enabled, runs every 30 minutes in UTC, and retries once. No client rebuild
or TestFlight upload is needed for this backend-only monitoring addition.

The monitor reads only pending deletion markers, projecting `requestedAt` and
limiting each scan to 501 documents. It never writes data or invokes deletion.
Requests at least 15 minutes old, invalid timestamps, or reaching the scan cap
emit an error with counts only, never account IDs or financial contents.
Normal detection is 15–45 minutes after a request, plus service/email latency.
Database errors emit an error and fail the job so Scheduler can retry.

Email channel: `projects/money-tally-gordonbowles/notificationChannels/427832249399154957`.
Owner-approved recipient: `gordob39@icloud.com`.
Policy: `projects/money-tally-gordonbowles/alertPolicies/6397586413385287044`.
Both were read back enabled. The policy matches ERROR-and-higher logs from the
callable, recovery worker, monitor and its Scheduler job, plus an explicitly
labeled operator delivery-test log. All matching errors share a one-hour
notification rate limit. Log incidents close after 24 hours without matching
logs; closure is **not** evidence that a pending deletion completed.

A synthetic delivery-test log was accepted by Cloud Logging at 20:50:20 UTC;
the owner initially reported no email yet. The first health check completed at
20:53:59 UTC with zero pending requests and all health flags clear; Scheduler
recorded HTTP 200. IAM read-back confirms only the runtime service account has
the service-level invoker grant, with no public grant. A second labeled test
was written at 20:55:32 UTC after initial provisioning. The exact live policy
filter matched both tests, but the Monitoring incident list still showed no
incident at that check and the owner had not received an email. See the successful
follow-up verification below. No deletion request or
financial record was created for this test. Scheduler or Logging outages, a
disabled job, and email delivery failures can prevent timely notification;
this is not a guaranteed-delivery paging service or an independent watchdog.

Operations helper: `tool/deletion_alerts.cjs` (configure, inspect, logs, run-check,
test). It uses the existing Firebase CLI sign-in without printing credentials.
Monitor logic is in `functions/deletion_monitor.js`; five added tests cover
empty/fresh, stale, invalid timestamps, scan cap and database failures.
All **19 backend tests** and ESLint passed after this addition.

### Email delivery confirmed

After the initial missing email, read-only diagnostics found no incidents,
snoozes, notification-failure logs or log exclusions. A fresh synthetic test at
21:15:31 UTC included an explicit timestamp, unique insert ID and per-entry
resource/log name. Google opened incident `0.ocjwb0vl4h1p` at **21:16:17 UTC**;
the owner then confirmed receipt at the approved iCloud address. No additional
test emails were sent after that confirmation.

The existing policy was also patched at 21:16:58 UTC to explicitly set
`notificationPrompts: [OPENED]`, retaining the filter, recipient and limits.
**The incident predates this patch**, so the implicit notification setting was
not established as the cause. Initial provisioning versus the test-entry format
cannot be distinguished from this evidence. Synthetic log-to-incident-to-email
delivery is now verified; do not claim a proven root cause for the early delay.
The production monitor's successful read-only execution was verified separately;
actual disposable-account deletion testing remains outstanding.

Cost update: [sync-security-cost-update.md](sync-security-cost-update.md).
Billing settings and the $25 budget were not changed.

Deployment receipts and read-back evidence:

- `/tmp/trackmark-deletion-rules-deploy.log`
- `/tmp/trackmark-deletion-worker-deploy.log`
- `/tmp/trackmark-deletion-callable-deploy.log`
- `/tmp/trackmark-deletion-backend-verification.log`

The read-only verification script `/tmp/trackmark-verify-deletion-backend.cjs`
can repeat the pending-count, rules, IAM, and trigger checks using the existing
Firebase CLI login. It does not fetch financial records or invoke deletion.

## Deletion protocol

1. Persist a device-local recovery record before requesting deletion. Invalidate
   queued upload authority and wait for already-submitted writes to settle.
   Pause foreground/background cloud sync and scheduled maintenance.
2. Verify with Apple and revoke the Apple authorization grant. A new server-side
   deletion request requires authentication within the preceding five minutes.
3. Transactionally create `accountDeletions/{uid}` outside the financial-data
   tree. Every allowed user-data rule checks that this marker does not exist.
   Once created, even a still-valid old ID token cannot read/write that user's
   financial records, restored generations, legacy snapshot, or sync metadata.
4. Recursively delete `users/{uid}`, then delete the Firebase Authentication
   identity, then mark the deletion completed. Missing auth identity is an
   idempotent success; other failures leave the request pending.
5. A new Firestore creation-triggered worker retries interrupted cleanup. The
   callable also performs cleanup so normal requests receive confirmation.
   Duplicate execution is safe while the durable barrier remains in place.
6. Only confirmed server completion allows local financial-data cleanup and
   sign-out. Persisted confirmation allows local cleanup to finish after restart
   without requiring a deleted identity to authenticate again.

The UI now distinguishes the Trackmark account from the user's Apple Account.
It no longer claims that “nothing was deleted” after an uncertain response.
Cancelling verification before sending the request preserves local data and
removes the local pause. Once a request may have been sent, sync stays paused.

## Recovery limitations and operational obligations

- If confirmation is lost, the signed-in client may retry the same request.
  If its authentication token expires first, support must verify server state;
  the app intentionally does not infer successful deletion from being signed out.
  It retains local data and an explicit sync pause until recovery is resolved.
- A confirmed deletion interrupted during local cleanup is retried on startup.
  A strictly local-only auth service has no cloud uploader and keeps synchronous
  startup; cloud-capable sessions must pass the recovery check.
- Other devices may retain offline copies. The server barrier prevents writes
  to the deleted UID, not remote wiping of devices or user-created backup files.
  Do not sign into a newly created account with retained old local data without
  first deciding whether those records should be kept or cleared.
- The server-only marker retains a UID, status, and request/completion timestamps,
  **not financial data**. It is deliberately not recursively deleted or expired.
  Document this minimal security/operational retention in the privacy policy;
  do not promise that all identifying metadata is immediately erased.
- Second-generation background retries have a finite 24-hour window. Before
  production rollout, establish an operator check/alert for pending deletion
  markers and worker failures. If the window expires, investigate the failure
  and explicitly resume that authorized UID's cleanup; never remove its barrier
  to restore sync. The read-only monitor and error alert above now cover this
  operational follow-up, subject to delivery verification.
  See [Firebase retry semantics](https://firebase.google.com/docs/functions/retries).
- App Check enforcement, general restore-generation pruning, and the App Store
  privacy questionnaire are not included in this code change.

## Cost impact

The additional `exists()` rule introduces potentially billable dependent-document
reads on client requests. Some accesses can be cached within rule evaluation;
do not multiply the cost by every document returned without checking actual
request/batch behavior. The incremental-cost update is recorded in
[sync-security-cost-update.md](sync-security-cost-update.md), with explicit
activity assumptions and verified NAM5 pricing.
The worker executes for account-deletion requests, not routine synchronization.
Retries can incur additional deletion/read/function charges during failures.
See [Firestore rules pricing](https://firebase.google.com/docs/firestore/pricing#cloud_firestore_security_rules).

## Local verification

- Node backend tests: 14 passing. Covers barrier-first ordering, missing barrier,
  failed barrier transaction, partial financial cleanup, auth failure,
  already-deleted identity, lost completion write, duplicate completion,
  authorized retries, and rejection of stale/invalid authentication.
- Flutter final full regression suite: **1,244 passing**, including the four UI
  recovery tests. Includes normal sync,
  timeout/lease behavior, queue invalidation, persistent deletion state, and
  fail-closed handling of corrupt recovery state.
- UI recovery tests cover cancellation, uncertain response with local data
  preserved, successful local cleanup before sign-out, and restart after
  confirmed deletion with no remaining signed-in identity.
- Real local Firestore emulator: 25 paths tested before/after marker creation,
  using the same still-valid synthetic token. Verified denied reads, writes,
  deletes, recreation after removal, client marker tampering, cross-user and
  anonymous access; an unaffected user's normal access remains available.
  The emulator checks security rules, not production IAM/Eventarc delivery,
  Apple reauthentication, or billing metering.
- Flutter analysis, Node lint, and whitespace validation: all passed.

Repeatable commands (from the repository root):

```sh
flutter analyze --no-pub
flutter test --no-pub
npm --prefix functions test
npm --prefix functions run lint
npm --prefix functions run test:rules
```

The emulator command hard-codes the isolated `demo-trackmark-deletion` project.
Its test script refuses a non-loopback host or different project. On this Mac,
Java 21 is bundled at `/Applications/Android Studio.app/Contents/jbr/Contents/Home`;
set `JAVA_HOME` there and prepend its `bin` directory to PATH if needed.
The downloaded emulator used `/tmp/trackmark-deletion-emulators`, not a system
Java installation. Test logs are in `/tmp/trackmark-deletion-{tests,rules,widget}.log`.

## Deployment and disposable-account acceptance checklist

Require separate owner approval before any production deployment or account test.

1. Deploy the Firestore barrier rules first; verify ordinary signed-in sync still
   works. No existing user has a marker merely because the rules are deployed.
2. Deploy and verify `resumeTrackmarkAccountDeletion` and its Eventarc trigger
   before updating the callable that creates markers. Verify trigger location,
   service-account IAM, retry policy, logs, and operational pending-request alert.
3. Deploy the updated `deleteTrackmarkAccount` callable. Keep the barrier and
   recovery worker if rolling back client code; do not roll back the protection
   while any deletion is pending.
4. Build/install the updated app. Existing build 5 can use the hardened callable,
   but its client does not have the new local pause/recovery/error handling.
5. Use a **disposable account**, never Gordon's real account. The owner has
   confirmed his wife's test sign-in is disposable and approved using it when
   she is available. Verify Apple confirmation/cancellation; use synthetic
   records only and reconfirm no real data was added before testing.
6. Sync the disposable account on two or three devices. Leave queued/offline
   edits on another device, delete from the first, then reconnect the others.
   Confirm all financial generations and auth identity are gone, the minimal
   completion marker remains, and stale devices cannot recreate cloud records.
7. Test an interrupted request and restart using controlled faults in an
   emulator/staging environment, not deliberately breaking production services.
   Verify retry completion, honest unconfirmed messaging, and local cleanup.
8. Rule-dependent read cost update is complete in the linked document. Review
   privacy retention wording and complete the App Store privacy/review metadata
   separately.

Passing local tests does not substitute for these deployment and device checks.
