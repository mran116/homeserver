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

# Local fast-scratch dirs (SAB usenet incomplete, Tdarr cache). Handled best-effort
# below so a root-owned parent (e.g. /mnt) only warns — it never aborts make-dirs.
scratch_dirs=("${SAB_INCOMPLETE_PATH:-/opt/docker/incomplete}" "${TDARR_CACHE:-/opt/docker/tdarr-cache}")

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
for d in "${scratch_dirs[@]}"; do [[ -d "$d" ]] || plan "create scratch dir $d (PUID-owned, best-effort)"; done
# Only the dirs that DON'T exist yet — so a pre-existing dir (e.g. a live DB data
# dir) is never re-created or re-chowned below.
new_app_dirs=(); for d in "${app_dirs[@]}"; do [[ -d "$d" ]] || new_app_dirs+=("$d"); done
[[ ${#new_app_dirs[@]} -gt 0 ]] && plan "create ${#new_app_dirs[@]} per-app config dir(s) under $CONFIG_PATH"

# Homepage config: repo is the source of truth. Mirror ./homepage/*.{yaml,css,js}
# into CONFIG_PATH/homepage whenever anything differs (Homepage hot-reloads — incl.
# custom.css/custom.js). Its runtime logs/ live alongside and are never touched.
shopt -s nullglob
hp_files=(dashboard/homepage/*.yaml dashboard/homepage/*.css dashboard/homepage/*.js)
shopt -u nullglob
sync_homepage=0
for f in "${hp_files[@]}"; do
  cmp -s "$f" "$CONFIG_PATH/homepage/$(basename "$f")" 2>/dev/null || sync_homepage=1
done
[[ $sync_homepage -eq 1 ]] && plan "sync Homepage config → $CONFIG_PATH/homepage (repo is source of truth)"

show_plan || exit 0
gate || exit 0

mkdir -p "${dirs[@]}"
# chown ONLY the dirs we just created — a pre-existing dir (e.g. an existing
# database's data dir) is left exactly as its container set it, so this can never
# disturb live data. No-op when already PUID-owned; needs root otherwise, so
# best-effort. Never recursive.
if [[ -n "${PUID:-}" && -n "${PGID:-}" && ${#new_app_dirs[@]} -gt 0 ]]; then
  chown "$PUID:$PGID" "${new_app_dirs[@]}" 2>/dev/null || true
fi
# Scratch dirs (SAB usenet, Tdarr) — best-effort, NEVER abort. A root-owned parent
# (e.g. /mnt) just warns with a one-time sudo hint; the /opt/docker default works.
for d in "${scratch_dirs[@]}"; do
  [[ -d "$d" ]] && continue
  if mkdir -p "$d" 2>/dev/null; then
    [[ -n "${PUID:-}" && -n "${PGID:-}" ]] && chown "$PUID:$PGID" "$d" 2>/dev/null || true
  else
    warn "scratch dir not created: $d (parent not writable). Once: sudo mkdir -p '$d' && sudo chown ${PUID:-1000}:${PGID:-1000} '$d'"
  fi
done
[[ $sync_homepage -eq 1 ]] && cp "${hp_files[@]}" "$CONFIG_PATH/homepage/"
say "Directory layout ready."
