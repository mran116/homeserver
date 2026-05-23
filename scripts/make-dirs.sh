#!/usr/bin/env bash
# =============================================================================
# make-dirs.sh — create the directory layout and seed the Homepage config.
#
# Creates CONFIG_PATH/MEDIA_PATH/PHOTOS_PATH/DOCS_PATH/SYNC_PATH (+ homepage),
# and seeds dashboard/homepage/* into CONFIG_PATH/homepage ONLY if it's empty
# (never clobbers your edits). Flags: --dry-run, --yes.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
cd "$REPO_DIR"

usage() { sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
parse_common_flags "$@"
require_env || exit 0
load_env

dirs=("$CONFIG_PATH" "$CONFIG_PATH/homepage" "$MEDIA_PATH" "$PHOTOS_PATH" "$DOCS_PATH" "$SYNC_PATH")
for d in "${dirs[@]}"; do [[ -d "$d" ]] || plan "create dir $d"; done

seed=0
if [[ -z "$(ls -A "$CONFIG_PATH/homepage" 2>/dev/null)" ]]; then
  plan "seed Homepage config → $CONFIG_PATH/homepage"
  seed=1
fi

show_plan || exit 0
gate || exit 0

mkdir -p "${dirs[@]}"
if [[ $seed -eq 1 ]]; then cp -r dashboard/homepage/. "$CONFIG_PATH/homepage/"; fi
say "Directory layout ready."
