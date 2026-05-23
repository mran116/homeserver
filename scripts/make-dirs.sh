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

base_dirs=("$CONFIG_PATH" "$CONFIG_PATH/homepage" "$MEDIA_PATH" "$PHOTOS_PATH" "$DOCS_PATH" "$SYNC_PATH")

# Per-app config dirs. Docker auto-creates a missing bind-mount source as
# root:root mid-`up`, which then locks out any app that runs as PUID. Derive the
# exact ${CONFIG_PATH}/* mount paths from the ACTIVE compose services (commented
# services start with '#' and are skipped) and pre-create them here — owned by
# whoever runs this, normally PUID — so that never happens. DB containers
# re-chown their own data dir on init, so this is safe for them too.
app_dirs=()
while IFS= read -r sub; do
  [[ -n "$sub" ]] && app_dirs+=("$CONFIG_PATH/$sub")
done < <(grep -rhE '^[[:space:]]*-[[:space:]]*\$\{CONFIG_PATH\}/' */docker-compose.yml \
         | grep -oE '\$\{CONFIG_PATH\}/[A-Za-z0-9._/-]+' \
         | sed 's#\${CONFIG_PATH}/##' | sort -u)

dirs=("${base_dirs[@]}" "${app_dirs[@]}")
# Only the base roots need a writability probe; the app dirs all live under
# CONFIG_PATH, which is covered by checking CONFIG_PATH itself.
for d in "${base_dirs[@]}"; do [[ -d "$d" ]] || require_writable "$d"; done
for d in "${base_dirs[@]}"; do [[ -d "$d" ]] || plan "create dir $d"; done
app_missing=0; for d in "${app_dirs[@]}"; do [[ -d "$d" ]] || app_missing=$((app_missing+1)); done
[[ $app_missing -gt 0 ]] && plan "create $app_missing per-app config dir(s) under $CONFIG_PATH"

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
# Best-effort: ensure the per-app dirs are owned by PUID:PGID. A no-op when this
# already runs as that user; silently skipped when not permitted (DB dirs get
# re-chowned by their container anyway). Leaf dirs only — never recursive.
if [[ -n "${PUID:-}" && -n "${PGID:-}" && ${#app_dirs[@]} -gt 0 ]]; then
  chown "$PUID:$PGID" "${app_dirs[@]}" 2>/dev/null || true
fi
[[ $sync_homepage -eq 1 ]] && cp dashboard/homepage/*.yaml "$CONFIG_PATH/homepage/"
say "Directory layout ready."
