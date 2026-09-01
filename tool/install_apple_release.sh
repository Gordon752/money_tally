#!/bin/zsh

set -euo pipefail

readonly script_dir="${0:A:h}"
source "${script_dir}/lib/apple_release_common.zsh"

usage() {
  cat <<'USAGE'
Build and install Trackmark Money through one guarded Apple release workflow.

Usage:
  ./tool/install_apple_release.sh all [options]
  ./tool/install_apple_release.sh ios [iOS options]
  ./tool/install_apple_release.sh macos [macOS options]

Examples:
  ./tool/install_apple_release.sh all
  ./tool/install_apple_release.sh ios --device DEVICE_ID
  ./tool/install_apple_release.sh ios --install-only
  ./tool/install_apple_release.sh macos --install-only
  ./tool/install_apple_release.sh all --preflight-only

Run this from the normal Terminal app so macOS can access the protected Apple
Development signing identity. The global lock prevents overlapping builds.
USAGE
}

platform="${1:-}"
if [[ -z "${platform}" || "${platform}" == '-h' || "${platform}" == '--help' ]]; then
  usage
  exit 0
fi
shift

case "${platform}" in
  ios)
    exec "${script_dir}/install_ios_release.sh" "$@"
    ;;
  macos)
    exec "${script_dir}/install_macos_release.sh" "$@"
    ;;
  all)
    typeset -a ios_args macos_args
    all_mode='build-and-install'
    while (( $# > 0 )); do
      case "$1" in
        --device)
          (( $# >= 2 )) || trackmark_die '--device requires an ID.'
          ios_args+=("$1" "$2")
          shift 2
          ;;
        --build-only|--install-only|--preflight-only)
          [[ "${all_mode}" == 'build-and-install' ]] || \
            trackmark_die 'Choose only one of --build-only, --install-only, or --preflight-only.'
          case "$1" in
            --build-only) all_mode='build-only' ;;
            --install-only) all_mode='install-only' ;;
            --preflight-only) all_mode='preflight-only' ;;
          esac
          ios_args+=("$1")
          macos_args+=("$1")
          shift
          ;;
        *)
          trackmark_die "Unknown all-platform option: $1"
          ;;
      esac
    done

    trackmark_acquire_build_lock all
    trackmark_assert_no_unmanaged_build
    "${script_dir}/install_macos_release.sh" --preflight-only
    "${script_dir}/install_ios_release.sh" "${ios_args[@]}"
    if [[ "${all_mode}" != 'preflight-only' ]]; then
      "${script_dir}/install_macos_release.sh" "${macos_args[@]}"
    fi
    ;;
  *)
    trackmark_die "Unknown platform: ${platform}. Use all, ios, or macos."
    ;;
esac
