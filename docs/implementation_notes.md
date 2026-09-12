# Trackmark Money Implementation Notes

## Current Direction

- Flutter app targeting iPhone, iPad, Mac, and future Android.
- App name: Trackmark Money.
- Visual direction follows the first expense app: restrained green accent, white panels, compact operational layout.
- Initial scope excludes attachments and bank sync.

## Core Modules

- Accounts with adjustable balances.
- Ledger transactions.
- Editable categories.
- Scheduled and recurring transactions.
- Required alerts for scheduled transactions.
- Simple monthly budget experiments.
- Local persistence through `shared_preferences`.
- Sync metadata on persisted records: `createdAt`, `updatedAt`, `deletedAt`, `deviceId`, and `version`.
- Firebase/Firestore repository scaffold for full-snapshot sync.
- Firebase project configured: `money-tally-gordonbowles`.
- Firestore database enabled and security rules deployed.

## Next Decisions

1. Confirm app name.
2. Confirm sync provider: Firebase is the current default recommendation.
3. Decide sign-in approach: Apple-only, email/password, Google, or anonymous first-run account.
4. Decide whether balances should be recomputed from transactions or stored as adjustable account state with balance-adjustment ledger entries.
5. Decide alert behavior: remind only, or optionally auto-post recurring transactions.

## Technical Next Steps

1. Add authentication and replace placeholder `userId` plumbing with real user IDs.
2. Add a first-run sync flow that can push local data or pull cloud data.
3. Add local notification scheduling for iOS, iPadOS, macOS, and later Android.

## Current File Structure

- `lib/main.dart`: app bootstrap and root widget.
- `lib/src/app_theme.dart`: shared theme colors and Material theme.
- `lib/src/domain.dart`: accounts, categories, transactions, budgets, recurrence models, and JSON helpers.
- `lib/src/local_finance_repository.dart`: local snapshot load/save.
- `lib/src/firestore_finance_repository.dart`: Firestore snapshot load/save scaffold.
- `lib/src/finance_store.dart`: app state, seed data, mutations, and persistence commits.
- `lib/src/finance_home.dart`: navigation, screens, cards, tiles, and dialogs.

## Firebase Setup Plan

1. Firebase project: `money-tally-gordonbowles`.
2. Registered iOS, macOS, and Android apps using `com.gordonbowles.moneytally`.
3. Generated `lib/firebase_options.dart` with FlutterFire CLI.
4. Enabled Firestore and deployed `firestore.rules`.
5. Enable the chosen auth provider, likely Sign in with Apple first.
6. Store each user's snapshot at `users/{userId}/finance/snapshot`.
7. Start with snapshot sync, then move to per-collection documents if sync conflicts or data size demands it.

See `docs/firebase_setup.md` for commands, bundle IDs, and Firestore rules.
