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

## macOS Release Builds

Build and install the Mac app only through the repository's verified installer:

```sh
./tool/install_macos_release.sh
```

Run the installer from the normal Terminal app so macOS can access the
protected Apple Development signing identity. The installer requires at least
20 GB of free disk space and stops before copying or building if that safety
margin is unavailable.

The source checkout lives under an iCloud File Provider-managed `Documents`
folder. Building a signed app directly into the checkout with
`flutter build macos` can attach Finder/File Provider metadata to the app and
its embedded frameworks, causing code signing to fail. The installer builds in
a clean local workspace outside iCloud, verifies the signed bundle, preserves
the previous installed copy for rollback, and installs the current app in
`/Applications`.
