#!/bin/zsh

# Shared safety primitives for Trackmark's Apple release installers.

set -euo pipefail
unsetopt BG_NICE

typeset -g TRACKMARK_BUILD_LOCK_OWNED=0
typeset -g TRACKMARK_ACTIVE_CHILD_PID=''
typeset -g TRACKMARK_BUILD_LOCK_DIR_ACTIVE=''

trackmark_info() {
  print -r -- "Trackmark: $*"
}

trackmark_warn() {
  print -u2 -r -- "Trackmark warning: $*"
}

trackmark_die() {
  print -u2 -r -- "Trackmark error: $*"
  exit 1
}

trackmark_require_command() {
  command -v "$1" >/dev/null 2>&1 || trackmark_die "Required tool not found: $1"
}

trackmark_resolve_flutter() {
  local flutter_bin="${FLUTTER_BIN:-}"
  if [[ -z "${flutter_bin}" ]]; then
    flutter_bin="$(command -v flutter 2>/dev/null || true)"
  fi
  [[ -n "${flutter_bin}" && -x "${flutter_bin}" ]] || \
    trackmark_die 'Flutter was not found. Set FLUTTER_BIN to the Flutter executable.'
  REPLY="${flutter_bin}"
}

trackmark_preflight_disk() {
  local disk_path="$1"
  local minimum_free_gib="$2"
  [[ "${minimum_free_gib}" == <-> && "${minimum_free_gib}" -gt 0 ]] || \
    trackmark_die 'The minimum free-space setting must be a positive whole number.'

  mkdir -p "${disk_path}"
  local available_kib="$(df -Pk "${disk_path}" | awk 'NR == 2 { print $4 }')"
  [[ "${available_kib}" == <-> ]] || \
    trackmark_die 'Could not determine available disk space.'
  local minimum_free_kib=$((minimum_free_gib * 1024 * 1024))
  local available_gib=$((available_kib / 1024 / 1024))
  if (( available_kib < minimum_free_kib )); then
    trackmark_die "At least ${minimum_free_gib} GB is required; ${available_gib} GB is available. No build was started."
  fi
  trackmark_info "Disk-space preflight passed (${available_gib} GB available)."
}

trackmark_remove_lock_files() {
  local lock_dir="$1"
  rm -f -- \
    "${lock_dir}/pid" \
    "${lock_dir}/token" \
    "${lock_dir}/started" \
    "${lock_dir}/command"
  rmdir "${lock_dir}" 2>/dev/null || true
}

trackmark_kill_process_tree() {
  local pid="$1"
  local child
  for child in ${(f)"$(pgrep -P "${pid}" 2>/dev/null || true)"}; do
    [[ -n "${child}" ]] && trackmark_kill_process_tree "${child}"
  done
  kill -TERM "${pid}" 2>/dev/null || true
}

trackmark_cleanup() {
  # zsh propagates global traps into command substitutions. Only the top-level
  # installer may stop its build or release its lock.
  (( ${ZSH_SUBSHELL:-0} == 0 )) || return 0

  if [[ -n "${TRACKMARK_ACTIVE_CHILD_PID}" ]] && \
      kill -0 "${TRACKMARK_ACTIVE_CHILD_PID}" 2>/dev/null; then
    trackmark_warn 'Stopping the active build before exiting.'
    trackmark_kill_process_tree "${TRACKMARK_ACTIVE_CHILD_PID}"
    wait "${TRACKMARK_ACTIVE_CHILD_PID}" 2>/dev/null || true
  fi
  TRACKMARK_ACTIVE_CHILD_PID=''

  if (( TRACKMARK_BUILD_LOCK_OWNED == 1 )) && \
      [[ -n "${TRACKMARK_BUILD_LOCK_DIR_ACTIVE}" ]]; then
    local token_file="${TRACKMARK_BUILD_LOCK_DIR_ACTIVE}/token"
    local active_token=''
    [[ -f "${token_file}" ]] && active_token="$(<"${token_file}")"
    if [[ "${active_token}" == "${TRACKMARK_BUILD_LOCK_TOKEN:-}" ]]; then
      trackmark_remove_lock_files "${TRACKMARK_BUILD_LOCK_DIR_ACTIVE}"
    fi
  fi
}

trackmark_acquire_build_lock() {
  local lock_dir="${TRACKMARK_BUILD_LOCK_DIR:-/private/tmp/trackmark_apple_release.lock}"
  TRACKMARK_BUILD_LOCK_DIR_ACTIVE="${lock_dir}"

  local inherited_token="${TRACKMARK_BUILD_LOCK_TOKEN:-}"
  if [[ -n "${inherited_token}" && -f "${lock_dir}/token" && \
        "$(<"${lock_dir}/token")" == "${inherited_token}" ]]; then
    return
  fi

  mkdir -p "${lock_dir:h}"
  if ! mkdir "${lock_dir}" 2>/dev/null; then
    local owner_pid=''
    [[ -f "${lock_dir}/pid" ]] && owner_pid="$(<"${lock_dir}/pid")"
    if [[ "${owner_pid}" == <-> ]] && kill -0 "${owner_pid}" 2>/dev/null; then
      local started='an unknown time'
      local command='another Trackmark installer'
      [[ -f "${lock_dir}/started" ]] && started="$(<"${lock_dir}/started")"
      [[ -f "${lock_dir}/command" ]] && command="$(<"${lock_dir}/command")"
      trackmark_die "A build is already running (PID ${owner_pid}, started ${started}: ${command}). Wait for it to finish; do not open another installer."
    fi
    trackmark_info 'Recovering a stale build lock from an interrupted installer.'
    trackmark_remove_lock_files "${lock_dir}"
    mkdir "${lock_dir}" || trackmark_die 'Could not claim the Apple build lock.'
  fi

  local token="$(uuidgen)"
  print -r -- "$$" > "${lock_dir}/pid"
  print -r -- "${token}" > "${lock_dir}/token"
  print -r -- "$(date '+%Y-%m-%d %H:%M:%S')" > "${lock_dir}/started"
  print -r -- "$0 $*" > "${lock_dir}/command"
  export TRACKMARK_BUILD_LOCK_TOKEN="${token}"
  TRACKMARK_BUILD_LOCK_OWNED=1
}

trackmark_assert_no_unmanaged_build() {
  local line pid command_text
  local matches=()
  local process_list=''
  if ! process_list="$(ps -axo pid=,command= 2>/dev/null)"; then
    trackmark_die 'Could not inspect running processes. Run the installer from the normal Terminal app so it can confirm no Apple build is already active.'
  fi
  while IFS= read -r line; do
    line="${line#${line%%[![:space:]]*}}"
    pid="${line%% *}"
    command_text="${line#* }"
    [[ "${pid}" == "$$" || "${pid}" == "${PPID}" ]] && continue
    if [[ "${command_text}" == *'flutter_tools.snapshot build ios'* ||
          "${command_text}" == *'flutter_tools.snapshot build macos'* ||
          ( "${command_text}" == *'/xcodebuild'* &&
            "${command_text}" == *'Runner.xcworkspace'* ) ]]; then
      matches+=("PID ${pid}: ${command_text}")
    fi
  done <<< "${process_list}"

  if (( ${#matches[@]} > 0 )); then
    print -u2 -r -- 'Trackmark error: An unmanaged Apple build is already active:'
    printf '  %s\n' "${matches[@]}" >&2
    trackmark_die 'Let that process finish or stop it before running the installer.'
  fi
}

trackmark_sync_project() {
  local project_dir="$1"
  local workspace="$2"
  mkdir -p "${workspace}"
  env COPYFILE_DISABLE=1 rsync -a --delete \
    --exclude '.dart_tool' \
    --exclude '.git' \
    --exclude 'build' \
    --exclude 'ios/Pods' \
    --exclude 'macos/Pods' \
    --exclude 'previous-installed.app' \
    "${project_dir}/" "${workspace}/"
}

trackmark_prepare_build() {
  local workspace="$1"
  local platform="$2"
  local artifact="$3"
  local marker="${workspace}/.trackmark-${platform}-build-incomplete"

  if [[ -f "${marker}" ]]; then
    trackmark_info "A previous ${platform} build was interrupted; clearing only its generated output."
    rm -rf -- "${workspace}/build/${platform}"
  fi
  rm -rf -- "${artifact}"
  print -r -- "$(date '+%Y-%m-%d %H:%M:%S')" > "${marker}"
  REPLY="${marker}"
}

trackmark_complete_build() {
  rm -f -- "$1"
}

trackmark_run_logged() {
  local label="$1"
  local log_file="$2"
  shift 2
  mkdir -p "${log_file:h}"
  : > "${log_file}"

  print -n -r -- "Trackmark: ${label}"
  "$@" > "${log_file}" 2>&1 &
  TRACKMARK_ACTIVE_CHILD_PID=$!
  while kill -0 "${TRACKMARK_ACTIVE_CHILD_PID}" 2>/dev/null; do
    sleep "${TRACKMARK_PROGRESS_INTERVAL_SECONDS:-10}"
    kill -0 "${TRACKMARK_ACTIVE_CHILD_PID}" 2>/dev/null && print -n -r -- '.'
  done

  local exit_code=0
  wait "${TRACKMARK_ACTIVE_CHILD_PID}" || exit_code=$?
  TRACKMARK_ACTIVE_CHILD_PID=''
  print
  if (( exit_code != 0 )); then
    print -u2 -r -- "Trackmark error: ${label} failed. Last log lines:"
    tail -n 80 "${log_file}" >&2
    print -u2 -r -- "Full log: ${log_file}"
    return "${exit_code}"
  fi
  trackmark_info "${label} completed. Log: ${log_file}"
}

trackmark_check_app_bundle() {
  local app="$1"
  local expected_bundle_id="$2"
  if [[ ! -d "${app}" ]]; then
    trackmark_warn "Expected app bundle was not produced: ${app}"
    return 1
  fi

  if ! xattr -cr "${app}"; then
    trackmark_warn "Could not remove unsupported metadata from: ${app}"
    return 1
  fi
  local codesign_output=''
  if ! codesign_output="$(codesign --verify --deep --strict --verbose=2 "${app}" 2>&1)"; then
    trackmark_warn "Code-signing verification failed: ${app}"
    [[ -n "${codesign_output}" ]] && print -u2 -r -- "${codesign_output}"
    return 1
  fi

  local info_plist
  if [[ -f "${app}/Contents/Info.plist" ]]; then
    info_plist="${app}/Contents/Info.plist"
  else
    info_plist="${app}/Info.plist"
  fi
  if [[ ! -f "${info_plist}" ]]; then
    trackmark_warn "App bundle has no Info.plist: ${app}"
    return 1
  fi
  local built_bundle_id=''
  if ! built_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${info_plist}")"; then
    trackmark_warn "Could not read the bundle ID from: ${app}"
    return 1
  fi
  if [[ "${built_bundle_id}" != "${expected_bundle_id}" ]]; then
    trackmark_warn "Refusing unexpected bundle ID: ${built_bundle_id}"
    return 1
  fi
}

trackmark_verify_app_bundle() {
  trackmark_check_app_bundle "$1" "$2" || \
    trackmark_die "App bundle verification failed: $1"
}

# Install traps at source scope. In zsh, an EXIT trap created inside a function
# runs when that function returns instead of remaining active for the script.
trap trackmark_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
