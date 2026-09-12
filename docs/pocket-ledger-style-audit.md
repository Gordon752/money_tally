# Trackmark legacy-style audit

## Implemented after user approval

The user reviewed the listed forms and authorized polishing all items, including
scheduled fund/goal funding after initially considering leaving those alone.
The following is now implemented locally; the audit below records the original
findings rather than the current appearance.

- All listed main amount fields use the shared opt-in inline amount style.
  Allocation line items retain their editable outlines and right alignment with
  lighter, smaller typography. Default amount-field behavior elsewhere is unchanged.
- Name, description, and note inputs in the audited fund/goal forms now use the
  borderless form treatment. Zero allocation remaining uses neutral coloring;
  positive balanced allocations and nonzero mismatch feedback are retained.
- Adjust Balance now uses TransactionSheetFrame and its fixed 48-point action
  footer, preserving debt/credit choice, signed input, preview, overdraw
  confirmation, and save/cancel semantics.
- Scheduled transaction and transfer creation focus Amount even with no account;
  choosing a source or destination account requests focus back without clearing
  the entered amount. Existing regular transaction focus behavior is preserved.
- A return/allocation dismissal regression test exposed premature disposal of
  the external focus node. AmountEntryField now owns its node through the closing
  animation rather than disposing it when the dialog's result first completes.
- Full suite: **1,159 passed**. Static analysis: **no issues**. New coverage includes
  77 form/layout combinations, zero-summary coloring, and four platform variants
  of scheduled/transfer focus tests. Existing reservation, split, payment, sync,
  and reminder regressions remain in the full suite.
- Rendered previews in `/private/tmp/trackmark-polish-layouts`; inspected phone,
  large-text phone, keyboard-visible phone, iPad, landscape iPad with keyboard,
  Mac, and dark-mode examples. Test data only; no live money was changed.
- No signed rebuild, installation, or upload for this polish pass. Installed
  devices remain on the earlier local build 3 pending a new packaging pass.

### Subsequent authorized installation

After the user requested installation, built signed local version **1.0.0 (4)**
using the previous non-iCloud workspace and cached dependencies. Both iOS and
macOS builds passed deep/strict code-signature verification. The four changed
app source files in the build workspace matched the tested repository files.

Installed over build 3 on GiPhone and GiPad without uninstalling; both launched,
and CoreDevice confirmed bundle version 4. Installed Mac build 4 at
`/Applications/Trackmark Money 2.app`, retaining its previous build 3 bundle at
`/Users/gordonbowles/Library/Developer/TrackmarkBuilds/Local-polish-1.0.0-4-backup/Trackmark Money 2.app`.
No app-data containers were reset and no TestFlight upload was performed.
Mac build 4 launched normally and displayed the existing dashboard/accounts.
The user subsequently confirmed that the installed polish works.

### Subsequent authorized TestFlight upload

Prepared fresh version **1.0.0 (4)** release archives for iOS and universal macOS
(Intel and Apple Silicon). Both passed deep/strict archive signature verification.
Xcode Organizer confirmed successful App Store Connect uploads for both platforms.
iOS processing completed with status **Ready to Submit**; Mac was **Processing**
at the final App Store Connect check. Build 4 has not been submitted for external beta review.
Existing build 2 external-review submissions were left unchanged.

Release source snapshot, archives, and build logs are retained at
`/Users/gordonbowles/Library/Developer/TrackmarkBuilds/TestFlight-1.0.0-4/`.
The iOS archive is in `source/build/ios/archive/Runner.xcarchive`, its exported IPA
in `source/build/ios/ipa/`, and the Mac archive is `Trackmark-macOS.xcarchive`.
This packaging/upload pass did not change installed apps or app-data containers.

Scope: source audit of shared Flutter forms, theme defaults, branding strings,
and the user-provided Return Funds screenshot. No app code or live data changed.
These shared forms affect iPhone, iPad, and Mac. This is not a complete visual
walkthrough of every state on every device; dark mode, large text, and keyboard
layouts need render checks when implementing the polish.

## Confirmed inconsistency

`AmountEntryField` defaults to a right-aligned, heavy titleLarge amount and an
InputDecoration that inherits the app theme's outlined box. Current transaction,
transfer, scheduled-transaction, and Mark Paid forms explicitly opt into lighter,
left-aligned, borderless amount rows. Several fund/goal forms omit those overrides.
This establishes a style inconsistency, not the historical origin of every form.

The sheet frame, circular icons, and shared action buttons are also used by
current polished forms. They should not be treated as obsolete merely because
they appear in the supplied screenshot. Avoid a blanket global-theme change.

## Findings to include in the polish pass

| Surface | Evidence | Recommended treatment |
| --- | --- | --- |
| Return Funds; Return Goal Reservation; individual fund allocation | `lib/src/funds/funds_ui.dart:1759`, amount at 1915; same shared form | Match current amount rows; remove duplicate Amount label; retain reservation/account context, preview, validation, and save guards. |
| Fund create/edit target balance | `lib/src/funds/funds_ui.dart:2138` | Replace default boxed amount treatment; avoid extra Amount label below Target balance. |
| Goal create/edit target amount | `lib/src/goals/goals_ui.dart:1265` | Match current amount typography and decoration. |
| Allocate Funds and Fund Goals totals | `lib/src/funds/funds_ui.dart:923`, `lib/src/goals/goals_ui.dart:1629` | Match current primary amount rows. |
| Scheduled fund/goal funding amounts | `lib/src/funds/funds_ui.dart:1362`, `lib/src/goals/goals_ui.dart:2143` | Match current scheduled-transaction amount rows. |
| Add goal progress/contribution | `lib/src/goals/goals_ui.dart:2478` | Amount and note retain default input decoration; review together. |
| Account balance adjustment | `lib/src/finance_home.dart:15537`, amount at 15643 | Separate sheet/group layout with inherited boxed input; align deliberately, preserving debt/credit controls and adjustment preview. |

Allocation line-item fields also inherit boxes: funds at 1035; goals at 1742 and
2225. These need visual review, not automatic removal of all boundaries: compact
multi-row allocations and split tables may need field outlines for clarity.

## Related interaction findings

- Scheduled transaction amount at `lib/src/finance_home.dart:20037` only
  autofocuses on create when an account is already selected; it lacks the regular
  transaction form's focusRequest mechanism. This confirms the requested fix.
- Regular transfer amount at `lib/src/finance_home.dart:18838` has the analogous
  source-account-dependent autofocus and no explicit amount refocus after source
  selection. Include it in focus review rather than assuming all transfer flows
  already received the regular expense/income fix.

## Do not confuse with visible legacy UI

- `showSplitTransactionDialog` at `lib/src/finance_home.dart:7288` is an older
  AlertDialog/dropdown editor. Search found its declaration but no calls in lib
  or test. Treat as unused-code review, not a confirmed reachable screen.
- Generic AlertDialogs for delete/restore confirmations are not automatically
  obsolete; their use alone is not evidence of a branding defect.
- No literal Pocket Ledger label was found in the searched source/assets.
  MoneyTally class names and `com.gordonbowles.moneytally` identifiers remain.
  Bundle IDs, Firebase/iCloud identifiers, storage keys, and backup compatibility
  are technical identity, not cosmetic rebranding targets. Preserve them.

## Verification for implementation

Render affected sheets on phone, iPad portrait/landscape, and Mac, with light/dark
themes, enlarged text, and keyboard visible. Retest amount input, over-reservation
validation, live previews, cancel behavior, and single-submit protection. Confirm
scheduled/transfer focus with no default account and after account selection.
No signed rebuild, device installation, or TestFlight upload was performed by
this audit.
