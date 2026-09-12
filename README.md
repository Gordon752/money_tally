# Trackmark Money

Simple finance tracking without the clutter.

Trackmark Money is a cross-platform Flutter finance app targeting iPhone, iPad,
Mac, and future Android support. The initial scope focuses on accounts,
ledgers, editable categories, scheduled transactions, alerts, simple budgets,
and sync-ready architecture without attachments or bank sync.

## Local Testing

Run the iPhone simulator from the project root:

```sh
./tool/run_simulator.sh
```

To use a different simulator, pass its device name:

```sh
./tool/run_simulator.sh "iPhone 17 Pro"
```

## Apple Release Builds and Device Installs

Use the repository's guarded installers instead of running overlapping Flutter
or Xcode builds by hand. To build once, install the same signed iOS app on every
connected iPhone/iPad, and then replace and launch the Mac app:

```sh
./tool/install_apple_release.sh all
```

Individual workflows and safe retries are also available:

```sh
./tool/install_apple_release.sh ios
./tool/install_apple_release.sh ios --install-only
./tool/install_apple_release.sh macos
./tool/install_apple_release.sh macos --install-only
./tool/install_apple_release.sh all --preflight-only
./tool/install_apple_release.sh all --build-only
```

Run Apple installers from the normal Terminal app so macOS can access the
protected Apple Development signing identity. Keep physical devices connected,
unlocked, and trusted until installation finishes. If only a device install
fails, correct the connection and use `--install-only`; the verified build is
retained and does not need to be rebuilt.

The workflow uses one global lock so two Apple builds cannot overlap, refuses
to start beside an unmanaged Flutter/Xcode build, checks for at least 20 GB of
free space, and keeps full logs while showing concise progress. It builds in a
stable local workspace outside the iCloud File Provider-managed source checkout
to avoid signing metadata problems. Interrupted builds are marked for focused
cleanup on the next run. Signed app bundles and bundle identifiers are verified
before installation, and the Mac installer preserves the previous app until
post-install verification succeeds.
