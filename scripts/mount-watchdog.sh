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
# Watches every storage path from .env (MEDIA/PHOTOS/DOCS/SYNC). It records when
# a path is first seen healthy, then alerts only if a previously-healthy path
# later goes empty + unmounted — i.e. the disk/NAS dropped. Paths that were never
# populated (an unused dir on the OS disk) are never flagged, so it works on any
# layout (mergerfs, NAS, plain dirs) with zero config and no false alarms. One
# ntfy alert per outage + a recovery notice.
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

# "Present" = the path is a mountpoint OR has any content. This watches EVERY
# configured path (not just fstab entries), but to avoid false alarms it only
# ALERTS on a regression: a path we've previously seen healthy that has since
# gone empty + unmounted (the disk/NAS dropped). A path that was never populated
# (e.g. an unused sync dir on the OS disk) is never marked "seen", so it never
# alerts. Adapts to any layout — mergerfs pools, NAS shares, plain dirs — with
# zero config and no crying wolf.
is_present() {
  local path="$1"
  [[ -d "$path" ]] || return 1
  command -v mountpoint >/dev/null 2>&1 && mountpoint -q "$path" 2>/dev/null && return 0
  [[ -n "$(ls -A "$path" 2>/dev/null)" ]] && return 0
  return 1
}

alerts=0
check() {  # check NAME PATH
  local name="$1" path="$2" flag seen
  [[ -z "$path" ]] && return 0
  flag="$STATE_DIR/${name}.down"
  seen="$STATE_DIR/${name}.seen"
  if is_present "$path"; then
    : > "$seen"                       # high-water mark: we've seen it healthy
    if [[ -f "$flag" ]]; then
      say "$name recovered: $path"
      [[ "${DRY_RUN:-0}" -ne 1 ]] && "$SCRIPT_DIR/notify.sh" "$TOPIC" "✅ Storage recovered: $name" "$path is back." || true
      rm -f "$flag"
    fi
  elif [[ -f "$seen" && ! -f "$flag" ]]; then   # was healthy before, now gone → real drop
    warn "$name OFFLINE: $path — was populated before, now empty/not mounted"
    if [[ "${DRY_RUN:-0}" -ne 1 ]]; then
      "$SCRIPT_DIR/notify.sh" "$TOPIC" "⚠️ Storage offline: $name" \
        "$path was populated before and is now empty / not mounted — the disk or NAS likely dropped. Apps using it will fail (e.g. *arr 'root folder doesn't exist'). Check the mount." || true
      : > "$flag"
    fi
    alerts=$((alerts + 1))
  fi
  # else: down but never seen healthy → an unused/empty dir; stay quiet.
}

# The storage roots that, if they vanish, break apps. All optional — a blank var
# is skipped, so this adapts to whatever a given deployment actually uses.
check MEDIA  "${MEDIA_PATH:-}"
check PHOTOS "${PHOTOS_PATH:-}"
check DOCS   "${DOCS_PATH:-}"
check SYNC   "${SYNC_PATH:-}"

[[ $alerts -eq 0 ]] && say "all storage mounts present"
exit 0
