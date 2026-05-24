#!/usr/bin/env bash
# =============================================================================
# schedule-maintenance.sh — install the low-maintenance cron jobs:
#
#   - nightly *arr key auto-sync (harvest-keys.sh --sync) @ 04:00 — self-heals
#     if an *arr API key changes; no-op on a normal night.
#   - weekly `docker image prune -af` @ Sun 05:00 — reclaims unused images
#     (never containers, volumes, or your bind-mounted data).
#   - SABnzbd stall watchdog (sab-watchdog.sh) every 5 min — recovers a wedged
#     SAB (pause/resume, then container restart as a last resort).
#
# Idempotent (keyed off marker comments). Flags: --dry-run, --yes.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
cd "$REPO_DIR"

usage() { sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
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
sw_marker="# homestack-sab-watchdog"
sw_line="*/5 * * * * cd $REPO_DIR && ./scripts/sab-watchdog.sh >> $REPO_DIR/sab-watchdog.log 2>&1 $sw_marker"

cron_now="$(crontab -l 2>/dev/null || true)"
# Reconcile each managed line to EXACTLY match the repo. The drift fix: re-apply
# a line when the existing one DIFFERS (repo changed), not only when its marker
# is missing — so an improved schedule/command actually reaches the box.
plan_line() {  # plan_line MARKER DESIRED_LINE DESCRIPTION
  local existing; existing="$(grep -F "$1" <<<"$cron_now" || true)"
  if   [[ -z "$existing"   ]]; then plan "add $3"
  elif [[ "$existing" != "$2" ]]; then plan "update $3 (repo changed)"
  fi
}
plan_line "$ks_marker" "$ks_line" "nightly *arr key-sync cron (04:00) → key-sync.log"
plan_line "$pr_marker" "$pr_line" "weekly image-prune cron (Sun 05:00) → image-prune.log"
plan_line "$sw_marker" "$sw_line" "SABnzbd stall watchdog cron (every 5 min) → sab-watchdog.log"

show_plan || exit 0
gate || exit 0

new_cron="$( { printf '%s\n' "$cron_now" | grep -vF "$ks_marker" | grep -vF "$pr_marker" | grep -vF "$sw_marker"; echo "$ks_line"; echo "$pr_line"; echo "$sw_line"; } )"
if printf '%s\n' "$new_cron" | crontab -; then
  say "Cron installed. Remove later with 'crontab -e' (delete the homestack-* lines)."
else
  warn "Could not write crontab — add these yourself:"
  warn "  $ks_line"
  warn "  $pr_line"
  warn "  $sw_line"
fi
