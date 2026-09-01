#!/bin/zsh

set -euo pipefail

readonly script_dir="${0:A:h}"
readonly project_dir="${script_dir:h}"
source "${script_dir}/lib/apple_release_common.zsh"

usage() {
  cat <<'USAGE'
Build and install Trackmark Money on connected physical iOS devices.

Usage:
  ./tool/install_ios_release.sh [options]

Options:
  --device ID       Install on a specific connected device (repeatable).
  --build-only      Build and verify without installing.
  --install-only    Install the last verified build without rebuilding.
  --preflight-only  Check requirements and connected devices only.
  -h, --help        Show this help.

With no --device option, every connected physical iPhone/iPad is selected.
If installation fails because a device is locked, unlock it and rerun with
--install-only; the verified build is retained.
USAGE
}

mode='build-and-install'
typeset -a requested_devices
while (( $# > 0 )); do
  case "$1" in
    --device)
      (( $# >= 2 )) || trackmark_die '--device requires an ID.'
      requested_devices+=("$2")
      shift 2
      ;;
    --build-only)
      [[ "${mode}" == 'build-and-install' ]] || \
        trackmark_die 'Choose only one release mode.'
      mode='build-only'
      shift
      ;;
    --install-only)
      [[ "${mode}" == 'build-and-install' ]] || \
        trackmark_die 'Choose only one release mode.'
      mode='install-only'
      shift
      ;;
    --preflight-only)
      [[ "${mode}" == 'build-and-install' ]] || \
        trackmark_die 'Choose only one release mode.'
      mode='preflight-only'
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      trackmark_die "Unknown option: $1"
      ;;
  esac
done

trackmark_resolve_flutter
readonly flutter_bin="${REPLY}"
readonly workspace="${TRACKMARK_IOS_WORKSPACE:-/private/tmp/trackmark_ios_release_workspace}"
readonly minimum_free_gib="${TRACKMARK_IOS_MIN_FREE_GIB:-20}"
readonly bundle_id='com.gordonbowles.moneytally'
readonly built_app="${workspace}/build/ios/iphoneos/Runner.app"

for tool in jq rsync xcrun xattr codesign uuidgen pgrep ps; do
  trackmark_require_command "${tool}"
done
trackmark_acquire_build_lock ios
trackmark_assert_no_unmanaged_build
trackmark_preflight_disk "${workspace}" "${minimum_free_gib}"

typeset -a device_ids device_names
if [[ "${mode}" != 'build-only' ]]; then
  devices_json="$(${flutter_bin} devices --machine)"
  if (( ${#requested_devices[@]} == 0 )); then
    while IFS=$'\t' read -r id name; do
      [[ -n "${id}" ]] || continue
      device_ids+=("${id}")
      device_names+=("${name}")
    done < <(print -r -- "${devices_json}" | jq -r '.[] | select(.targetPlatform == "ios" and .emulator == false and .isSupported == true) | [.id, .name] | @tsv')
  else
    local_id=''
    for local_id in "${requested_devices[@]}"; do
      name="$(print -r -- "${devices_json}" | jq -r --arg id "${local_id}" '.[] | select(.id == $id and .targetPlatform == "ios" and .emulator == false and .isSupported == true) | .name' | head -n 1)"
      [[ -n "${name}" ]] || trackmark_die "Physical iOS device is not connected or supported: ${local_id}"
      device_ids+=("${local_id}")
      device_names+=("${name}")
    done
  fi
  (( ${#device_ids[@]} > 0 )) || \
    trackmark_die 'No connected physical iPhone or iPad was found.'
  trackmark_info "Selected devices: ${(j:, :)device_names}"
fi

if [[ "${mode}" == 'preflight-only' ]]; then
  trackmark_info 'iOS release preflight passed. No build or installation was performed.'
  exit 0
fi

if [[ "${mode}" != 'install-only' ]]; then
  trackmark_info 'Preparing the clean local iOS workspace.'
  trackmark_sync_project "${project_dir}" "${workspace}"
  cd "${workspace}"
  timestamp="$(date '+%Y%m%d-%H%M%S')"
  trackmark_run_logged 'Resolving Flutter dependencies' "${workspace}/logs/ios-pub-${timestamp}.log" \
    env COPYFILE_DISABLE=1 "${flutter_bin}" pub get

  trackmark_prepare_build "${workspace}" ios "${built_app}"
  marker="${REPLY}"
  if ! trackmark_run_logged 'Building signed iOS release' "${workspace}/logs/ios-build-${timestamp}.log" \
      env COPYFILE_DISABLE=1 "${flutter_bin}" build ios --release; then
    trackmark_die 'The iOS build failed. Its incomplete marker was retained for safe recovery on the next run.'
  fi
  trackmark_verify_app_bundle "${built_app}" "${bundle_id}"
  trackmark_complete_build "${marker}"
  trackmark_info "Verified iOS release: ${built_app}"
else
  trackmark_verify_app_bundle "${built_app}" "${bundle_id}"
  trackmark_info "Reusing verified iOS release: ${built_app}"
fi

if [[ "${mode}" == 'build-only' ]]; then
  trackmark_info 'iOS build-only run completed; no devices were changed.'
  exit 0
fi

typeset -a failed_devices
integer index=1
for id in "${device_ids[@]}"; do
  name="${device_names[${index}]}"
  trackmark_info "Installing on ${name} (${id})."
  if ! xcrun devicectl device install app --device "${id}" "${built_app}"; then
    failed_devices+=("${name} (${id})")
  fi
  (( index += 1 ))
done

if (( ${#failed_devices[@]} > 0 )); then
  trackmark_die "Installation failed on ${(j:, :)failed_devices}. Unlock/reconnect those devices and rerun with --install-only."
fi
trackmark_info "Installed Trackmark Money on ${(j:, :)device_names}."
