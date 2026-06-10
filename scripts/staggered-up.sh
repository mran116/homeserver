#!/usr/bin/env bash
# =============================================================================
# staggered-up.sh — bring the whole stack up in ordered WAVES, not all at once.
#
# WHY: on a host reboot the Docker daemon auto-restarts every `restart:`-policy
# container CONCURRENTLY (compose `depends_on` is a `compose up` construct — the
# daemon ignores it on boot). On VM 100 that's a ~50-container I/O storm that
# helped trigger the NVMe link-dropout. This script serialises the bring-up into
# waves with a gap between them so disk/NFS isn't hammered all at once:
#
#   1 foundation   infrastructure (caddy/crowdsec), vaultwarden
#   2 light + media monitoring/dashboard/household/fitness/records/knowledge/
#                  syncthing/cloud  +  jellyfin/plex/navidrome/audiobookshelf
#   3 *arr          prowlarr/flaresolverr → sonarr/radarr/lidarr/whisparr →
#                  bazarr/seerr/recyclarr
#   4 downloaders   gluetun→qbittorrent, sabnzbd, unpackerr
#   5 last (heavy)  tdarr, decluttarr
#
# It owns startup on CLEAN reboots via the homestack-startup.service unit, whose
# ExecStop runs `--stop` to mark every container user-stopped — so the daemon
# skips them on the next boot and this script is the sole, ordered starter.
# (Unclean power-loss boots still let the daemon auto-restart; the 90s docker
# startup-delay drop-in softens that by letting the OS/NFS settle first.)
#
# Honours the stack profile (.stacks.local DENIED) and active COMPOSE_PROFILES
# (tdarr etc. are only touched when their profile is on), so it never starts a
# stack/service you've excluded. Idempotent — already-running containers no-op.
#
#   ./scripts/staggered-up.sh           bring everything up in waves
#   ./scripts/staggered-up.sh --stop    stop all (reverse) — used on shutdown
#   ./scripts/staggered-up.sh --install install the systemd units + docker drop-in
#
# Wave gap is tunable: STARTUP_WAVE_GAP=<seconds> (default 20).
# Flags: -n/--dry-run, -y/--yes, -h/--help.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
cd "$REPO_DIR"

usage() { sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
parse_common_flags "$@"

GAP="${STARTUP_WAVE_GAP:-20}"          # seconds between waves
MEDIA="mediastack"                      # the stack handled service-by-service

in_list() { case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# True if a stack has at least one ACTIVE (uncommented) service — skips the
# all-commented placeholder stacks (e.g. devops) that `docker compose` rejects
# with "services must be a mapping". Same check stack.sh uses.
is_active_stack() {
  local s="$1" n
  [[ -f "$s/docker-compose.yml" ]] || return 1
  n=$(awk '/^services:/{i=1;next} /^[^[:space:]#]/{i=0} i&&/^  [A-Za-z0-9_-]+:[[:space:]]*$/{c++} END{print c+0}' "$s/docker-compose.yml")
  [[ "${n:-0}" -gt 0 ]]
}

# docker compose for a stack, auto-including its gitignored override if present
# (compose skips the auto-override when -f is passed, so add it back) — matches
# stack.sh's dc().
dc() {
  local s="$1"; shift
  local f=(-f "$s/docker-compose.yml")
  [[ -f "$s/docker-compose.override.yml" ]] && f+=(-f "$s/docker-compose.override.yml")
  docker compose "${f[@]}" --env-file "$ENV_FILE" "$@"
}

# Stacks this host deploys (everything minus DENIED), in profile order. Falls
# back to a sane default if the profile helper is unavailable.
mapfile -t ENABLED_STACKS < <("$SCRIPT_DIR/stacks.sh" deploy-list 2>/dev/null)
[[ ${#ENABLED_STACKS[@]} -gt 0 ]] || ENABLED_STACKS=(arcane vaultwarden infrastructure monitoring dashboard mediastack household fitness records knowledge syncthing cloud)

# mediastack services compose would actually start (respects COMPOSE_PROFILES +
# the override). Empty if mediastack is denied/absent.
MEDIA_ENABLED=()
if in_list "$MEDIA" "${ENABLED_STACKS[*]}" && [[ -f "$MEDIA/docker-compose.yml" ]]; then
  mapfile -t MEDIA_ENABLED < <(dc "$MEDIA" config --services 2>/dev/null | sort)
fi

# Track what we've brought up so the catch-all wave can sweep anything new that
# isn't named in a wave below (e.g. a stack/service added later) — nothing is
# silently left down.
STARTED_STACKS=" $MEDIA "   # mediastack is handled per-service, never as a whole
STARTED_SVCS=" "

gap() { [[ "${GAP}" -gt 0 && $DRY_RUN -eq 0 ]] && { say "  …settle ${GAP}s…"; sleep "$GAP"; }; return 0; }

# Bring up one whole stack (skips denied/absent/placeholder/mediastack).
stack_up() {
  local s="$1"
  [[ "$s" == "$MEDIA" ]] && return 0
  in_list "$s" "${ENABLED_STACKS[*]}" || return 0
  is_active_stack "$s" || return 0
  STARTED_STACKS+="$s "
  say "  stack: $s"
  [[ $DRY_RUN -eq 1 ]] && return 0
  dc "$s" up -d ${STACK_UP_ARGS:-} || warn "$s failed"
}

# Bring up the named mediastack services that are actually enabled.
media_up() {
  local want=() s
  for s in "$@"; do
    in_list "$s" "${MEDIA_ENABLED[*]}" || continue
    in_list "$s" "$STARTED_SVCS" && continue
    want+=("$s"); STARTED_SVCS+="$s "
  done
  [[ ${#want[@]} -eq 0 ]] && return 0
  say "  mediastack: ${want[*]}"
  [[ $DRY_RUN -eq 1 ]] && return 0
  dc "$MEDIA" up -d "${want[@]}" || warn "mediastack (${want[*]}) failed"
}

do_up() {
  require_docker
  say "Staggered bring-up (gap ${GAP}s between waves)${DRY_RUN:+ [dry-run]}"

  say "Wave 1/5 — foundation (proxy, secrets)"
  stack_up infrastructure
  stack_up vaultwarden
  gap

  say "Wave 2/5 — light apps + media servers"
  local s
  for s in arcane monitoring dashboard household fitness records knowledge syncthing cloud; do stack_up "$s"; done
  media_up jellyfin plex navidrome audiobookshelf
  gap

  say "Wave 3/5 — *arr (indexers, then managers)"
  media_up prowlarr flaresolverr
  media_up sonarr radarr lidarr whisparr
  media_up bazarr seerr recyclarr
  gap

  say "Wave 4/5 — downloaders"
  media_up gluetun qbittorrent sabnzbd unpackerr
  gap

  say "Wave 5/5 — heavy / last"
  media_up tdarr decluttarr

  # Catch-all: anything enabled but not named in a wave above (future stacks/
  # services). Brought up after the waves so the storm-control still held.
  local extra_stacks=() extra_svcs=()
  for s in "${ENABLED_STACKS[@]}"; do in_list "$s" "$STARTED_STACKS" || { is_active_stack "$s" && extra_stacks+=("$s"); }; done
  for s in "${MEDIA_ENABLED[@]+"${MEDIA_ENABLED[@]}"}"; do in_list "$s" "$STARTED_SVCS" || extra_svcs+=("$s"); done
  if [[ ${#extra_stacks[@]} -gt 0 || ${#extra_svcs[@]} -gt 0 ]]; then
    gap
    say "Catch-all — stacks/services not in a named wave"
    for s in "${extra_stacks[@]+"${extra_stacks[@]}"}"; do stack_up "$s"; done
    [[ ${#extra_svcs[@]} -gt 0 ]] && media_up "${extra_svcs[@]}"
  fi

  say "Done — stack up in waves."
}

# Mark every container user-stopped (reverse order) so the daemon won't auto-
# restart them on the next boot — this script becomes the sole ordered starter.
# `stop` (not `down`) keeps the containers, so the next bring-up is fast.
do_stop() {
  require_docker
  say "Stopping all stacks in reverse (marks containers user-stopped)${DRY_RUN:+ [dry-run]}"
  local rev=() i
  for ((i=${#ENABLED_STACKS[@]}-1; i>=0; i--)); do rev+=("${ENABLED_STACKS[i]}"); done
  local s
  for s in "${rev[@]}"; do
    is_active_stack "$s" || continue
    say "  stop: $s"
    [[ $DRY_RUN -eq 1 ]] && continue
    dc "$s" stop || warn "$s stop failed"
  done
  say "Done — all stacks stopped."
}

# Install the systemd units + docker startup-delay drop-in, templating this
# repo's real path so it works wherever the repo lives.
do_install() {
  command -v systemctl >/dev/null || die "systemctl not found — this host isn't systemd."
  local SUDO=""; [[ $EUID -ne 0 ]] && SUDO="sudo"
  local unit_src="$REPO_DIR/infrastructure/systemd/homestack-startup.service"
  local drop_src="$REPO_DIR/infrastructure/systemd/docker.service.d/startup-delay.conf"
  [[ -f "$unit_src" ]] || die "missing $unit_src"
  [[ -f "$drop_src" ]] || die "missing $drop_src"

  plan "install /etc/systemd/system/homestack-startup.service (ExecStart from $REPO_DIR)"
  plan "install /etc/systemd/system/docker.service.d/startup-delay.conf (90s boot delay)"
  plan "systemctl daemon-reload && enable --now homestack-startup.service"
  show_plan || return 0
  gate || return 0

  # Template the canonical /opt/docker/stacks path → this repo's actual path.
  $SUDO install -m 644 /dev/stdin /etc/systemd/system/homestack-startup.service \
    < <(sed "s#/opt/docker/stacks#$REPO_DIR#g" "$unit_src")
  $SUDO install -d /etc/systemd/system/docker.service.d
  $SUDO install -m 644 "$drop_src" /etc/systemd/system/docker.service.d/startup-delay.conf
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable --now homestack-startup.service
  say "Installed. Wave startup fully applies once the unit has owned one clean shutdown."
  say "Apply the docker boot-delay now with: $SUDO systemctl restart docker  (restarts containers — do when convenient)."
}

case "${1:-up}" in
  --stop|stop)       do_stop ;;
  --install|install) do_install ;;
  -n|--dry-run|-y|--yes|"" ) do_up ;;   # flags already parsed; default = up
  up)                do_up ;;
  *)                 do_up ;;
esac
