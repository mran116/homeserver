#!/usr/bin/env bash
# =============================================================================
# mount-watchdog.sh — detect, AUTO-HEAL, and alert when a storage mount drops.
#
# Why this exists: a storage disk/NAS can detach (a passthrough disk dropping its
# SATA/SCSI link, an NFS/CIFS share going away, a mergerfs pool not mounting).
# Because mounts use `nofail`, the box boots fine but the mount point sits EMPTY
# — and apps fail SILENTLY (e.g. the *arr log "root folder doesn't exist", or
# Jellyfin's ffmpeg can't open files so playback just hangs). This catches that.
#
# On a drop it tries to RECOVER automatically: a SCSI rescan (re-attaches a disk
# whose link dropped) + `mount -a`, then restarts the dependent stack so the
# containers re-bind the now-populated path (Docker binds don't see a remount
# under them until the container restarts). It pushes a phone alert either way:
# "auto-recovered" or "still offline — needs a host/Proxmox fix".
#
# Watches every storage path from .env (MEDIA/PHOTOS/DOCS/SYNC). Records when a
# path is first seen healthy, then acts only if a previously-healthy path later
# goes empty + unmounted. Paths never populated (an unused dir on the OS disk)
# are never flagged — so it works on any layout with zero config, no false alarms.
#
# Auto-heal needs root (rescan + mount), so it only runs when invoked as root
# (the cron is). A manual non-root run (`hs mounts`) just reports + alerts.
#
# Runs from cron (schedule-maintenance.sh installs it every 5 min). Manual run:
#   hs mounts        (or sudo ./scripts/mount-watchdog.sh  to allow auto-heal)
# Flags: --dry-run (report only; no ntfy, no heal). --no-heal (alert, don't repair).
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

# Auto-heal toggle: on unless --dry-run or --no-heal. The privileged step (rescan
# + mount) runs via mount-heal-root.sh — directly when we're root, else via
# `sudo -n` (a sudoers rule grants exactly that one script). If neither works it
# degrades to alert-only, so it's always safe.
HEAL=1
for a in "$@"; do [[ "$a" == "--no-heal" ]] && HEAL=0; done
[[ "${DRY_RUN:-0}" -eq 1 ]] && HEAL=0

# Which stack to restart when a given mount recovers (its containers bind the
# path and hold a stale empty mount until restarted — Docker bind propagation).
stack_for() { case "$1" in
  MEDIA)  echo mediastack ;;
  PHOTOS) echo cloud ;;
  DOCS)   echo records ;;
  SYNC)   echo syncthing ;;
  *)      echo "" ;;
esac; }

# "Present" = the path is a mountpoint OR has any content.
is_present() {
  local path="$1"
  [[ -d "$path" ]] || return 1
  command -v mountpoint >/dev/null 2>&1 && mountpoint -q "$path" 2>/dev/null && return 0
  [[ -n "$(ls -A "$path" 2>/dev/null)" ]] && return 0
  return 1
}

# SCSI rescan + mount -a — the recovery that fixes a dropped disk link. Idempotent
# and safe (probes for devices; mounts only what fstab says, never unmounts). Runs
# at most once per invocation even if several paths are down.
healed_this_run=0
attempt_remount() {
  [[ $healed_this_run -eq 1 ]] && return 0
  healed_this_run=1
  say "auto-heal: SCSI rescan + mount -a (via mount-heal-root.sh)"
  if [[ "$(id -u)" -eq 0 ]]; then
    "$SCRIPT_DIR/mount-heal-root.sh" || true
  elif command -v sudo >/dev/null 2>&1 && sudo -n "$SCRIPT_DIR/mount-heal-root.sh" 2>/dev/null; then
    : # recovered via passwordless sudo rule
  else
    warn "auto-heal needs root: install the sudoers rule (run 'sudo hs schedule' or 'sudo hs mounts' once). Falling back to alert-only."
  fi
}

# Restart the dependent stack so its containers re-bind the recovered path.
restart_stack() {
  local stack; stack="$(stack_for "$1")"
  [[ -z "$stack" || ! -f "$REPO_DIR/$stack/docker-compose.yml" ]] && return 0
  command -v docker >/dev/null 2>&1 || return 0
  say "auto-heal: restarting $stack so it re-binds the remounted volume"
  docker compose --env-file "$REPO_DIR/.env" -f "$REPO_DIR/$stack/docker-compose.yml" restart >/dev/null 2>&1 || true
}

notify() { [[ "${DRY_RUN:-0}" -eq 1 ]] && return 0; "$SCRIPT_DIR/notify.sh" "$@" >/dev/null 2>&1 || true; }

alerts=0
check() {  # check NAME PATH
  local name="$1" path="$2" flag seen
  [[ -z "$path" ]] && return 0
  flag="$STATE_DIR/${name}.down"
  seen="$STATE_DIR/${name}.seen"

  if is_present "$path"; then
    : > "$seen"                         # high-water mark: seen healthy
    if [[ -f "$flag" ]]; then
      say "$name recovered: $path"
      notify "$TOPIC" "✅ Storage recovered: $name" "$path is back."
      rm -f "$flag"
    fi
    return 0
  fi

  # Not present. Only act if it was healthy before (a real drop, not an unused dir).
  [[ -f "$seen" ]] || return 0

  # Try to self-heal (rescan + mount), then re-check.
  if [[ $HEAL -eq 1 ]]; then
    attempt_remount
    if is_present "$path"; then
      : > "$seen"
      restart_stack "$name"
      say "$name AUTO-RECOVERED: $path"
      notify "$TOPIC" "🔧 Storage auto-recovered: $name" \
        "$path had dropped (likely a disk link reset); a SCSI rescan + remount brought it back and $(stack_for "$name") was restarted. If this recurs, fix the disk power-management on the host."
      rm -f "$flag"
      return 0
    fi
  fi

  # Still down — alert once per outage.
  if [[ ! -f "$flag" ]]; then
    warn "$name OFFLINE: $path — was populated before, now empty/not mounted"
    if [[ $HEAL -eq 1 ]]; then
      notify "$TOPIC" "⚠️ Storage offline: $name" \
        "$path dropped and AUTO-RECOVERY (rescan + mount) did NOT bring it back — it's likely detached at the host/Proxmox level. Apps using it will fail. Manual fix needed."
    else
      notify "$TOPIC" "⚠️ Storage offline: $name" \
        "$path was populated before and is now empty / not mounted — the disk or NAS likely dropped. Apps using it will fail (e.g. *arr 'root folder doesn't exist'). Run 'sudo hs mounts' to auto-recover, or check the mount."
    fi
    : > "$flag"
    alerts=$((alerts + 1))
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
