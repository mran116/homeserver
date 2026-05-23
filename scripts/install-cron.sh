#!/usr/bin/env bash
# =============================================================================
# install-cron.sh — install the low-maintenance cron jobs.
#
#   - nightly *arr key auto-sync (harvest-keys.sh --sync) — self-heals if an
#     *arr API key ever changes; no-op on a normal night.
#   - weekly `docker image prune -af` — reclaims unused images (never
#     containers, volumes, or your bind-mounted data).
#
# Idempotent (keyed off marker comments). Flags: --dry-run, --yes.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
cd "$REPO_DIR"

usage() { sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
parse_common_flags "$@"

if ! command -v crontab >/dev/null 2>&1; then
  warn "cron not found — skipping. To automate maintenance, schedule these yourself:"
  warn "  cd $REPO_DIR && ./scripts/harvest-keys.sh --sync   (nightly)"
  warn "  docker image prune -af                             (weekly)"
  exit 0
fi

ks_marker="# homestack-key-sync"
ks_line="0 4 * * * cd $REPO_DIR && ./scripts/harvest-keys.sh --sync >> $REPO_DIR/key-sync.log 2>&1 $ks_marker"
pr_marker="# homestack-image-prune"
pr_line="0 5 * * 0 docker image prune -af >> $REPO_DIR/image-prune.log 2>&1 $pr_marker"

cron_now="$(crontab -l 2>/dev/null || true)"
grep -qF "$ks_marker" <<<"$cron_now" || plan "add nightly *arr key-sync cron (04:00) → key-sync.log"
grep -qF "$pr_marker" <<<"$cron_now" || plan "add weekly image-prune cron (Sun 05:00) → image-prune.log"

show_plan || exit 0
gate || exit 0

new_cron="$( { printf '%s\n' "$cron_now" | grep -vF "$ks_marker" | grep -vF "$pr_marker"; echo "$ks_line"; echo "$pr_line"; } )"
if printf '%s\n' "$new_cron" | crontab -; then
  say "Cron installed. Remove later with 'crontab -e' (delete the homestack-* lines)."
else
  warn "Could not write crontab — add these yourself:"
  warn "  $ks_line"
  warn "  $pr_line"
fi
