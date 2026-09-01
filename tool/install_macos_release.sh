#!/bin/zsh

set -euo pipefail

readonly script_dir="${0:A:h}"
readonly project_dir="${script_dir:h}"
source "${script_dir}/lib/apple_release_common.zsh"

usage() {
  cat <<'USAGE'
Build, verify, install, and launch Trackmark Money for macOS.

Usage:
  ./tool/install_macos_release.sh [options]

Options:
  --build-only      Build and verify without installing.
  --install-only    Install the last verified build without rebuilding.
  --preflight-only  Check requirements, signing, disk, and build lock only.
  -h, --help        Show this help.

Run from the normal Terminal app so macOS can access the protected Apple
Development signing identity. The existing installed app is preserved until
the replacement has been independently verified.
USAGE
}

mode='build-and-install'
while (( $# > 0 )); do
  case "$1" in
    --build-only)
      [[ "${mode}" == 'build-and-install' ]] || \
        trackmark_die 'Choose only one release mode.'
      mode='build-only'
      ;;
    --install-only)
      [[ "${mode}" == 'build-and-install' ]] || \
        trackmark_die 'Choose only one release mode.'
      mode='install-only'
      ;;
    --preflight-only)
      [[ "${mode}" == 'build-and-install' ]] || \
        trackmark_die 'Choose only one release mode.'
      mode='preflight-only'
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      trackmark_die "Unknown option: $1"
      ;;
  esac
  shift
done

trackmark_resolve_flutter
readonly flutter_bin="${REPLY}"
readonly install_dir="${TRACKMARK_MAC_INSTALL_DIR:-/Applications}"
readonly workspace="${TRACKMARK_MAC_WORKSPACE:-/private/tmp/trackmark_macos_release_workspace}"
readonly minimum_free_gib="${TRACKMARK_MAC_MIN_FREE_GIB:-20}"
readonly app_name='Trackmark Money.app'
readonly bundle_id='com.gordonbowles.moneytally'
readonly installed_app="${install_dir}/${app_name}"
readonly staging_app="${install_dir}/.Trackmark Money.installing.app"
readonly previous_app="${workspace}/previous-installed.app"
readonly built_app="${workspace}/build/macos/Build/Products/Release/${app_name}"

for tool in rsync xattr codesign security uuidgen pgrep ps ditto osascript open; do
  trackmark_require_command "${tool}"
done
trackmark_acquire_build_lock macos
trackmark_assert_no_unmanaged_build
trackmark_preflight_disk "${workspace}" "${minimum_free_gib}"

identity_output="$(security find-identity -v -p codesigning 2>&1 || true)"
if [[ "${identity_output}" != *'Apple Development'* ]]; then
  trackmark_die 'The Apple Development signing identity is unavailable. Run this installer from the normal Terminal app and confirm the certificate in Xcode > Settings > Accounts.'
fi
trackmark_info 'Apple Development signing identity is available.'

if [[ "${mode}" == 'preflight-only' ]]; then
  trackmark_info 'macOS release preflight passed. No build or installation was performed.'
  exit 0
fi

if [[ "${mode}" != 'install-only' ]]; then
  trackmark_info 'Preparing the clean local macOS workspace.'
  trackmark_sync_project "${project_dir}" "${workspace}"
  cd "${workspace}"
  timestamp="$(date '+%Y%m%d-%H%M%S')"
  trackmark_run_logged 'Resolving Flutter dependencies' "${workspace}/logs/macos-pub-${timestamp}.log" \
    env COPYFILE_DISABLE=1 "${flutter_bin}" pub get

  trackmark_prepare_build "${workspace}" macos "${built_app}"
  marker="${REPLY}"
  if ! trackmark_run_logged 'Building signed macOS release' "${workspace}/logs/macos-build-${timestamp}.log" \
      env COPYFILE_DISABLE=1 "${flutter_bin}" build macos --release; then
    trackmark_die 'The macOS build failed. Its incomplete marker was retained for safe recovery on the next run.'
  fi
  trackmark_verify_app_bundle "${built_app}" "${bundle_id}"
  trackmark_complete_build "${marker}"
  trackmark_info "Verified macOS release: ${built_app}"
else
  trackmark_verify_app_bundle "${built_app}" "${bundle_id}"
  trackmark_info "Reusing verified macOS release: ${built_app}"
fi

if [[ "${mode}" == 'build-only' ]]; then
  trackmark_info 'macOS build-only run completed; the installed app was not changed.'
  exit 0
fi

rm -rf -- "${staging_app}"
ditto "${built_app}" "${staging_app}"
trackmark_verify_app_bundle "${staging_app}" "${bundle_id}"

osascript -e "tell application id \"${bundle_id}\" to quit" >/dev/null 2>&1 || true

rm -rf -- "${previous_app}"
if [[ -d "${installed_app}" ]]; then
  mv "${installed_app}" "${previous_app}"
fi

if ! mv "${staging_app}" "${installed_app}"; then
  [[ -d "${previous_app}" && ! -e "${installed_app}" ]] && \
    mv "${previous_app}" "${installed_app}"
  trackmark_die 'The new app could not be installed; the previous copy was restored.'
fi

if ! trackmark_check_app_bundle "${installed_app}" "${bundle_id}"; then
  rm -rf -- "${installed_app}"
  [[ -d "${previous_app}" ]] && mv "${previous_app}" "${installed_app}"
  trackmark_die 'Post-install verification failed; the previous copy was restored.'
fi
rm -rf -- "${previous_app}"

if ! open "${installed_app}"; then
  trackmark_warn "The app was installed but could not be launched automatically: ${installed_app}"
  exit 0
fi
trackmark_info "Installed and launched ${installed_app}"
