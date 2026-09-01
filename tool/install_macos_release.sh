#!/bin/zsh

set -euo pipefail

readonly script_dir="${0:A:h}"
readonly project_dir="${script_dir:h}"
readonly flutter_bin="${FLUTTER_BIN:-$(command -v flutter)}"
readonly install_dir="${TRACKMARK_MAC_INSTALL_DIR:-/Applications}"
readonly app_name="Trackmark Money.app"
readonly bundle_id="com.gordonbowles.moneytally"
readonly installed_app="${install_dir}/${app_name}"
readonly staging_app="${install_dir}/.Trackmark Money.installing.app"
readonly build_project="/private/tmp/trackmark_macos_release_workspace"
readonly previous_app="${build_project}/previous-installed.app"
readonly minimum_free_gib="${TRACKMARK_MAC_MIN_FREE_GIB:-20}"

if [[ "${minimum_free_gib}" != <-> ]] || (( minimum_free_gib <= 0 )); then
  echo "TRACKMARK_MAC_MIN_FREE_GIB must be a positive whole number." >&2
  exit 1
fi

readonly minimum_free_kib=$((minimum_free_gib * 1024 * 1024))

echo "Preparing a clean Trackmark Money macOS build..."
mkdir -p "${build_project}"

readonly available_kib="$(df -Pk "${build_project}" | awk 'NR == 2 { print $4 }')"
if [[ "${available_kib}" != <-> ]]; then
  echo "Could not determine available disk space; refusing to start the Mac build." >&2
  exit 1
fi

readonly available_gib=$((available_kib / 1024 / 1024))
if (( available_kib < minimum_free_kib )); then
  echo "At least ${minimum_free_gib} GB of free disk space is required for a safe Mac build; ${available_gib} GB is available." >&2
  echo "Free additional space and run the installer again. The installed app was not changed." >&2
  exit 1
fi

echo "Disk-space preflight passed (${available_gib} GB available)."
rsync -a --delete \
  --exclude '.dart_tool' \
  --exclude '.git' \
  --exclude 'build' \
  --exclude 'ios/Pods' \
  --exclude 'macos/Pods' \
  --exclude 'macos/Podfile.lock' \
  --exclude 'previous-installed.app' \
  "${project_dir}/" "${build_project}/"

# CocoaPods records absolute paths. Regenerate it inside the clean workspace so
# a build can never reuse paths from the File Provider-backed source checkout.
# The stable temporary workspace then keeps those safe paths and build caches,
# making subsequent verified installs substantially faster.

cd "${build_project}"
env COPYFILE_DISABLE=1 "${flutter_bin}" pub get

# A cancelled or overlapping Xcode build can leave an incomplete app bundle and
# stale intermediates behind. Always start the release portion clean while
# retaining downloaded dependencies and the generated CocoaPods workspace.
rm -rf "${build_project}/build/macos"
env COPYFILE_DISABLE=1 "${flutter_bin}" build macos --release

readonly built_app="${build_project}/build/macos/Build/Products/Release/${app_name}"
if [[ ! -d "${built_app}" ]]; then
  echo "The release build completed without producing ${built_app}." >&2
  exit 1
fi

# File Provider metadata is not part of the app and can invalidate signing when
# copied into a bundle. Strip it before verifying or installing the release.
xattr -cr "${built_app}"
codesign --verify --deep --strict --verbose=2 "${built_app}"

readonly built_bundle_id="$(defaults read "${built_app}/Contents/Info" CFBundleIdentifier)"
if [[ "${built_bundle_id}" != "${bundle_id}" ]]; then
  echo "Refusing to install unexpected bundle ID: ${built_bundle_id}" >&2
  exit 1
fi

rm -rf "${staging_app}"
ditto "${built_app}" "${staging_app}"
codesign --verify --deep --strict --verbose=2 "${staging_app}"

osascript -e "tell application id \"${bundle_id}\" to quit" >/dev/null 2>&1 || true

rm -rf "${previous_app}"
if [[ -d "${installed_app}" ]]; then
  mv "${installed_app}" "${previous_app}"
fi

if ! mv "${staging_app}" "${installed_app}"; then
  if [[ -d "${previous_app}" && ! -e "${installed_app}" ]]; then
    mv "${previous_app}" "${installed_app}"
  fi
  echo "The new app could not be installed; the previous copy was restored." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "${installed_app}"
open "${installed_app}"

echo "Installed and launched ${installed_app}"
