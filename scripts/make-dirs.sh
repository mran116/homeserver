#!/usr/bin/env bash
# =============================================================================
# make-dirs.sh — create the directory layout and sync the Homepage config.
#
# Creates CONFIG_PATH/MEDIA_PATH/PHOTOS_PATH/DOCS_PATH/SYNC_PATH (+ homepage),
# and MIRRORS dashboard/homepage/*.yaml into CONFIG_PATH/homepage (the repo is
# the source of truth — edit configs in the repo, not on the box). Only copies
# when something changed; Homepage hot-reloads and its runtime logs/ are left
# untouched. Flags: --dry-run, --yes.
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
for d in "${dirs[@]}"; do [[ -d "$d" ]] || require_writable "$d"; done
for d in "${dirs[@]}"; do [[ -d "$d" ]] || plan "create dir $d"; done

# Homepage config: repo is the source of truth. Mirror ./homepage/*.yaml into
# CONFIG_PATH/homepage whenever anything differs (Homepage hot-reloads). Its
# runtime logs/ live alongside and are never touched.
sync_homepage=0
for f in dashboard/homepage/*.yaml; do
  cmp -s "$f" "$CONFIG_PATH/homepage/$(basename "$f")" 2>/dev/null || sync_homepage=1
done
[[ $sync_homepage -eq 1 ]] && plan "sync Homepage config → $CONFIG_PATH/homepage (repo is source of truth)"

show_plan || exit 0
gate || exit 0

mkdir -p "${dirs[@]}"
[[ $sync_homepage -eq 1 ]] && cp dashboard/homepage/*.yaml "$CONFIG_PATH/homepage/"
say "Directory layout ready."
