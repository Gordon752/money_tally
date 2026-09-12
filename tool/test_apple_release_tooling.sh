#!/bin/zsh

set -euo pipefail

readonly script_dir="${0:A:h}"
readonly common="${script_dir}/lib/apple_release_common.zsh"
typeset -a scripts=(
  "${common}"
  "${script_dir}/install_ios_release.sh"
  "${script_dir}/install_macos_release.sh"
  "${script_dir}/install_apple_release.sh"
)

for script in "${scripts[@]}"; do
  zsh -n "${script}"
done

"${script_dir}/install_ios_release.sh" --help >/dev/null
"${script_dir}/install_macos_release.sh" --help >/dev/null
"${script_dir}/install_apple_release.sh" --help >/dev/null

readonly test_root="$(mktemp -d /private/tmp/trackmark-tooling-test.XXXXXX)"
trap 'rm -rf -- "${test_root}"' EXIT
readonly test_lock="${test_root}/apple.lock"

TRACKMARK_BUILD_LOCK_DIR="${test_lock}" zsh -c \
  'source "$1"; trackmark_acquire_build_lock test; [[ -f "$TRACKMARK_BUILD_LOCK_DIR/pid" ]]' \
  _ "${common}"
[[ ! -e "${test_lock}" ]]

TRACKMARK_BUILD_LOCK_DIR="${test_lock}" zsh -c '
  source "$1"
  original_path="$PATH"
  trackmark_preflight_disk "$2" 1 >/dev/null
  [[ "$PATH" == "$original_path" ]]
  TRACKMARK_PROGRESS_INTERVAL_SECONDS=0.05
  trackmark_run_logged "Test command" "$2/success.log" /usr/bin/true >/dev/null
  if trackmark_run_logged "Expected failure" "$2/failure.log" /usr/bin/false >/dev/null 2>&1; then
    exit 1
  fi
' _ "${common}" "${test_root}/workspace"

mkdir -p "${test_root}/recovery/build/ios/iphoneos/Runner.app"
print -r -- 'interrupted' > "${test_root}/recovery/.trackmark-ios-build-incomplete"
TRACKMARK_BUILD_LOCK_DIR="${test_lock}" zsh -c '
  source "$1"
  trackmark_prepare_build "$2" ios "$2/build/ios/iphoneos/Runner.app" >/dev/null
  [[ -f "$2/.trackmark-ios-build-incomplete" ]]
  [[ ! -e "$2/build/ios" ]]
' _ "${common}" "${test_root}/recovery"

mkdir "${test_lock}"
print -r -- '999999' > "${test_lock}/pid"
print -r -- 'stale' > "${test_lock}/token"
TRACKMARK_BUILD_LOCK_DIR="${test_lock}" zsh -c \
  'source "$1"; trackmark_acquire_build_lock test; [[ "$(<"$TRACKMARK_BUILD_LOCK_DIR/pid")" == "$$" ]]' \
  _ "${common}"
[[ ! -e "${test_lock}" ]]

mkdir "${test_lock}"
print -r -- "$$" > "${test_lock}/pid"
print -r -- 'live' > "${test_lock}/token"
if TRACKMARK_BUILD_LOCK_DIR="${test_lock}" zsh -c \
    'source "$1"; trackmark_acquire_build_lock test' _ "${common}" >/dev/null 2>&1; then
  print -u2 -r -- 'Active build lock was not rejected.'
  exit 1
fi
rm -rf -- "${test_lock}"

print -r -- 'Apple release tooling checks passed.'
