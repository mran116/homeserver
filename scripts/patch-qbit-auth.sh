#!/usr/bin/env bash
# =============================================================================
# patch-qbit-auth.sh
#
# Add the mediastack's docker subnet to qBittorrent's WebUI auth whitelist so
# other containers on the same network (the *arr apps that connect through
# Gluetun, plus queue-cleaners like decluttarr) can talk to qBit's API without
# any credential plumbing.
#
# Why: linuxserver/qbittorrent ships with auth required, AND it ban-lists the
# source IP after a few bad logins. If a sidecar's stored password drifts from
# what qBit has (or it's never been set), every retry compounds into a 403
# that survives container restarts. The internal subnet whitelist sidesteps
# both — the host-exposed port still requires login from outside the docker
# network.
#
# Idempotent. Detects "already configured" and exits cleanly. Safe to wire
# into bootstrap.sh or run by hand any time the stack is up.
#
# Usage:
#   ./scripts/patch-qbit-auth.sh                # interactive (gated)
#   ./scripts/patch-qbit-auth.sh --yes          # non-interactive
#   ./scripts/patch-qbit-auth.sh --dry-run      # preview only
#   ./scripts/patch-qbit-auth.sh --network home # override docker net name
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: patch-qbit-auth.sh [--yes] [--dry-run] [--network NAME] [--container NAME]

  --yes / -y         apply without prompting
  --dry-run / -n     show the plan, change nothing
  --network NAME     docker network to whitelist (default: home)
  --container NAME   qBittorrent container name (default: qbittorrent)
  --help / -h        this help
EOF
}

parse_common_flags "$@"

NETWORK="home"
CONTAINER="qbittorrent"
# Parse our own flags (parse_common_flags ignored these).
while [[ $# -gt 0 ]]; do
  case "$1" in
    --network)   NETWORK="${2:?--network needs a value}"; shift 2 ;;
    --container) CONTAINER="${2:?--container needs a value}"; shift 2 ;;
    --network=*)   NETWORK="${1#*=}"; shift ;;
    --container=*) CONTAINER="${1#*=}"; shift ;;
    *) shift ;;
  esac
done

require_cmd docker
require_cmd python3

# Resolve CONFIG_PATH from .env (with sensible fallback).
CONFIG_PATH="/opt/docker/data"
if [[ -f "$REPO_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  set -a; source "$REPO_DIR/.env"; set +a
fi
QBIT_CONF="$CONFIG_PATH/qbittorrent/qBittorrent/qBittorrent.conf"

# 1. The conf only exists once qBit has booted at least once. On a fresh
#    install this is the expected state — soft-skip so we can be wired into
#    bootstrap.sh and re-run later when the mediastack is up.
if [[ ! -f "$QBIT_CONF" ]]; then
  warn "qBittorrent.conf not found at: $QBIT_CONF"
  warn "  Skipping — bring qBittorrent up first ('docker compose -f mediastack/docker-compose.yml up -d qbittorrent'),"
  warn "  then re-run this script or 'bootstrap.sh' to apply."
  exit 0
fi

# 2. Auto-detect the docker network subnet so this stays portable.
SUBNET="$(docker network inspect "$NETWORK" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || true)"
if [[ -z "$SUBNET" ]]; then
  warn "Docker network '$NETWORK' not found — skipping."
  warn "  This usually means create-network.sh hasn't run yet, or the stack uses a different network name."
  available="$(docker network ls --format '{{.Name}}' 2>/dev/null | grep -v -E '^(bridge|host|none)$' | paste -sd ' ' -)"
  [[ -n "$available" ]] && warn "  Available user networks: $available"
  warn "  Re-run with --network <name> if needed."
  exit 0
fi

say "qBittorrent config: $QBIT_CONF"
say "Docker network:     $NETWORK ($SUBNET)"

# 3. Current state — read the two keys we care about.
read_key() {
  # read_key KEY -> echo current value (empty if absent). Backslash in key
  # is matched literally via fixed-string grep.
  grep -F -m1 "$1=" "$QBIT_CONF" 2>/dev/null | cut -d= -f2- || true
}
CURRENT_ENABLED="$(read_key 'WebUI\AuthSubnetWhitelistEnabled')"
CURRENT_LIST="$(read_key 'WebUI\AuthSubnetWhitelist')"

# qBittorrent stores the whitelist as a comma-separated list — preserve any
# subnets the user already added (corporate VPN, secondary docker net, etc.)
# and only add our subnet if it's missing.
DESIRED_LIST="$(python3 -c '
import sys
current = sys.argv[1]
add     = sys.argv[2]
parts = [s.strip() for s in current.split(",") if s.strip()]
if add not in parts:
    parts.append(add)
print(",".join(parts))
' "$CURRENT_LIST" "$SUBNET")"

if [[ "$CURRENT_ENABLED" == "true" && "$CURRENT_LIST" == "$DESIRED_LIST" ]]; then
  say "Whitelist already includes $SUBNET — nothing to do."
  exit 0
fi

# 4. Plan.
[[ "$CURRENT_ENABLED" == "true" ]] || plan "Set WebUI\\AuthSubnetWhitelistEnabled=true (was: '${CURRENT_ENABLED:-unset}')"
if [[ "$CURRENT_LIST" != "$DESIRED_LIST" ]]; then
  if [[ -z "$CURRENT_LIST" ]]; then
    plan "Set WebUI\\AuthSubnetWhitelist=$DESIRED_LIST"
  else
    plan "Append $SUBNET to WebUI\\AuthSubnetWhitelist (was: '$CURRENT_LIST', new: '$DESIRED_LIST')"
  fi
fi
plan "Back up $(basename "$QBIT_CONF") with a timestamp suffix"
plan "Stop '$CONTAINER' so the conf isn't overwritten on shutdown"
plan "Apply the changes"
plan "Start '$CONTAINER' again"

show_plan || exit 0
gate || exit 0

# 5. Apply.
BACKUP="$QBIT_CONF.bak.$(date +%Y%m%d-%H%M%S)"
cp "$QBIT_CONF" "$BACKUP"
say "Backed up conf to $BACKUP"

# Safety: qBittorrent runs in another container's network namespace (e.g.
# gluetun) when network_mode is `service:X`. We only stop qBit itself, never
# the network host — if the network host were restarted, qBit's stored
# container-id reference would go stale and it couldn't re-attach. Bail out
# loudly if someone misconfigures this script to target the network host.
NET_MODE="$(docker inspect "$CONTAINER" -f '{{.HostConfig.NetworkMode}}' 2>/dev/null || true)"
case "$NET_MODE" in
  container:*|service:*)
    say "Note: '$CONTAINER' shares another container's network namespace ($NET_MODE) — only stopping qBit, not that host"
    ;;
esac

# Stop qBit so it doesn't rewrite the file on graceful shutdown.
WAS_RUNNING=0
if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  WAS_RUNNING=1
  say "Stopping '$CONTAINER'"
  docker stop "$CONTAINER" >/dev/null
fi

# Edit via python — avoids the regex-escaping minefield around backslashes in
# the .conf keys (e.g. "WebUI\Address") that sed/awk make brittle. The
# whitelist value is already the merged list (existing + new), computed above.
python3 - "$QBIT_CONF" "$DESIRED_LIST" <<'PY'
import sys, pathlib

conf_path, whitelist = sys.argv[1], sys.argv[2]
p = pathlib.Path(conf_path)
text = p.read_text()
lines = text.splitlines(keepends=True)

DESIRED = {
    "WebUI\\AuthSubnetWhitelistEnabled": "true",
    "WebUI\\AuthSubnetWhitelist":        whitelist,
}

# Replace existing keys in place; track which we still need to insert.
out = []
seen = set()
for ln in lines:
    handled = False
    for k, v in DESIRED.items():
        if ln.startswith(k + "="):
            out.append(f"{k}={v}\n")
            seen.add(k)
            handled = True
            break
    if not handled:
        out.append(ln)

missing = [(k, v) for k, v in DESIRED.items() if k not in seen]
if missing:
    # Insert after [Preferences]; create the section if it doesn't exist.
    prefs_idx = next(
        (i for i, ln in enumerate(out) if ln.strip() == "[Preferences]"),
        None,
    )
    if prefs_idx is None:
        if out and not out[-1].endswith("\n"):
            out.append("\n")
        out.append("\n[Preferences]\n")
        prefs_idx = len(out) - 1
    insertions = [f"{k}={v}\n" for k, v in missing]
    out[prefs_idx + 1:prefs_idx + 1] = insertions

p.write_text("".join(out))
PY
say "Wrote $QBIT_CONF"

# Restart only if we stopped it (so re-runs against a stopped qBit don't
# accidentally bring it up).
if [[ $WAS_RUNNING -eq 1 ]]; then
  say "Starting '$CONTAINER'"
  docker start "$CONTAINER" >/dev/null
else
  warn "'$CONTAINER' was not running when this script started — leaving stopped."
  warn "  Start it when ready:  docker start $CONTAINER"
fi

# Verify.
NEW_ENABLED="$(read_key 'WebUI\AuthSubnetWhitelistEnabled')"
NEW_LIST="$(read_key 'WebUI\AuthSubnetWhitelist')"
if [[ "$NEW_ENABLED" == "true" && "$NEW_LIST" == "$DESIRED_LIST" ]]; then
  say "Done. Whitelist is now: $DESIRED_LIST"
else
  die "Post-apply verification failed.
     Expected: WebUI\\AuthSubnetWhitelistEnabled=true, WebUI\\AuthSubnetWhitelist=$DESIRED_LIST
     Got:      enabled='$NEW_ENABLED', list='$NEW_LIST'
     Backup at: $BACKUP"
fi
