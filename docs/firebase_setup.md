# Firebase Setup

Money Tally is configured for Firebase project `money-tally-gordonbowles`.

## One-time login

Run this in your normal Terminal, not inside Codex:

```sh
firebase login --reauth
```

If FlutterFire is not on your PATH, add this to your shell profile:

```sh
export PATH="$PATH":"$HOME/.pub-cache/bin"
```

## Project configuration

From the Money Tally project root:

```sh
flutterfire configure \
  --project money-tally-gordonbowles \
  --out lib/firebase_options.dart \
  --platforms ios,macos,android
```

Register these bundle/package IDs:

- iOS: `com.gordonbowles.moneytally`
- macOS: `com.gordonbowles.moneytally`
- Android: `com.gordonbowles.moneytally`

Generated files:

- `lib/firebase_options.dart`
- `ios/Runner/GoogleService-Info.plist`
- `macos/Runner/GoogleService-Info.plist`
- `android/app/google-services.json`

## Firestore

Enable Firestore in the Firebase Console, then deploy rules:

```sh
firebase deploy --only firestore:rules
```

Current data path:

```text
users/{userId}/finance/snapshot
```

The initial implementation stores a full finance snapshot per user. This is simple and sufficient for early use. If sync conflicts or data size become a problem, move to per-collection documents:

- `users/{userId}/accounts/{accountId}`
- `users/{userId}/categories/{categoryId}`
- `users/{userId}/transactions/{transactionId}`
- `users/{userId}/scheduled/{scheduledId}`
- `users/{userId}/budgets/{budgetId}`

## Authentication

Money Tally is wired for Firebase Authentication with Sign in with Apple.

Firebase Console setup:

1. Open Authentication > Sign-in method.
2. Enable Apple.
3. Complete the Apple provider settings from the Apple Developer account.

Apple Developer / Xcode setup:

1. Enable the Sign in with Apple capability for the iOS app ID.
2. Enable the Sign in with Apple capability for the macOS app ID.
3. In Xcode, add Signing & Capabilities > Sign in with Apple for both targets.

The app can still be opened in local-only mode. Local-only data remains on the device and does not sync until the user signs in.
