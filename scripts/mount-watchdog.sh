#!/usr/bin/env bash
# =============================================================================
# mount-watchdog.sh — alert (ntfy) when a critical storage mount drops offline.
#
# Why this exists: a storage disk/NAS can detach (a passthrough disk dropping, an
# NFS/CIFS share going away, a mergerfs pool not mounting). Because mounts use
# `nofail`, the box boots fine but the mount point sits EMPTY — and the apps fail
# SILENTLY (e.g. the *arr log "root folder doesn't exist" forever). This catches
# that and pushes a phone alert so you know immediately, not days later.
#
# Watches the storage paths from .env that are declared as their own mount in
# /etc/fstab (a dedicated disk, NAS share, or mergerfs pool); if such a path is
# not currently mounted, it pushes ONE ntfy alert per outage plus a recovery
# notice. Plain local dirs (single-disk setups) have no fstab entry and are
# never flagged — so it works unchanged, false-alarm-free, on any deployment.
#
# Runs from cron (schedule-maintenance.sh installs it every 5 min). Manual run:
#   hs mounts        (or ./scripts/mount-watchdog.sh)
# Flags: --dry-run (report only, no ntfy).
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
cd "$REPO_DIR" || exit 1
parse_common_flags "$@"
require_env || exit 0
load_env

# ntfy topic: reuse the alert channel the stack already publishes to (matches
# seed-uptime-kuma.sh + diun). Override with NTFY_TOPIC in .env if you like.
TOPIC="${NTFY_TOPIC:-diun-updates}"

# Per-mount state (so we alert once on outage + once on recovery, not every run).
STATE_DIR="${CONFIG_PATH:-/opt/docker/data}/.mount-watchdog"
mkdir -p "$STATE_DIR" 2>/dev/null || { STATE_DIR="/tmp/.mount-watchdog"; mkdir -p "$STATE_DIR"; }

# Returns a reason string (and rc 0) if the path is "offline", else rc 1.
#
# To avoid false alarms (best UX), we ONLY watch paths that are SUPPOSED to be
# their own mount — i.e. they have an /etc/fstab entry (a dedicated disk, a NAS
# share, a mergerfs pool). Such a path "offline" = it has an fstab entry but is
# not currently mounted (exactly the disk-detach / NAS-down case). A plain local
# directory with no fstab entry (e.g. a single-disk setup, or an unused folder)
# is never flagged — so this adapts to each deployment with zero config.
down_reason() {
  local path="$1"
  [[ -z "$path" ]] && return 1
  # Is this path a declared mount target in fstab? (field 2, skipping comments)
  awk -v p="$path" '$0 !~ /^[[:space:]]*#/ && $2==p {f=1} END{exit !f}' /etc/fstab 2>/dev/null || return 1
  # It's meant to be a mount — is it actually mounted right now?
  if command -v mountpoint >/dev/null 2>&1; then
    mountpoint -q "$path" 2>/dev/null && return 1
    echo "declared in /etc/fstab but not mounted"; return 0
  fi
  # No mountpoint(1): fall back to an emptiness check.
  [[ -d "$path" && -n "$(ls -A "$path" 2>/dev/null)" ]] && return 1
  echo "declared in /etc/fstab but appears unmounted (empty)"; return 0
}

alerts=0
check() {  # check NAME PATH
  local name="$1" path="$2" reason flag
  [[ -z "$path" ]] && return 0
  flag="$STATE_DIR/${name}.down"
  if reason="$(down_reason "$path")"; then
    if [[ ! -f "$flag" ]]; then
      warn "$name OFFLINE: $path — $reason"
      if [[ "${DRY_RUN:-0}" -ne 1 ]]; then
        "$SCRIPT_DIR/notify.sh" "$TOPIC" "⚠️ Storage offline: $name" \
          "$path is $reason. Apps using it will fail (e.g. *arr 'root folder doesn't exist'). Check the disk/NAS and remount." || true
        : > "$flag"
      fi
      alerts=$((alerts + 1))
    fi
  elif [[ -f "$flag" ]]; then
    say "$name recovered: $path"
    [[ "${DRY_RUN:-0}" -ne 1 ]] && "$SCRIPT_DIR/notify.sh" "$TOPIC" "✅ Storage recovered: $name" "$path is mounted again." || true
    rm -f "$flag"
  fi
}

# The storage roots that, if they vanish, break apps. All optional — a blank var
# is skipped, so this adapts to whatever a given deployment actually uses.
check MEDIA  "${MEDIA_PATH:-}"
check PHOTOS "${PHOTOS_PATH:-}"
check DOCS   "${DOCS_PATH:-}"
check SYNC   "${SYNC_PATH:-}"

[[ $alerts -eq 0 ]] && say "all storage mounts present"
exit 0
