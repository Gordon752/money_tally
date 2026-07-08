#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-/Users/gordonbowles/development/flutter/bin/flutter}"
DEVICE_NAME="${1:-iPhone 17 Pro}"

export PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"
export COPYFILE_DISABLE=1

cd "$PROJECT_DIR"
"$FLUTTER_BIN" run -d "$DEVICE_NAME"
