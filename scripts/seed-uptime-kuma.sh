#!/usr/bin/env bash
# seed-uptime-kuma.sh — apply monitoring/uptime-kuma/seed.json into Uptime Kuma:
# every service as a monitor, plus one ntfy alert channel they all notify through.
# Idempotent (only adds missing monitors). Uptime Kuma loads monitors at startup,
# so this stops the container, seeds its DB, and starts it again.
# Flags: --dry-run, --yes, --force (seed even if monitors exist), --topic=NAME.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
cd "$REPO_DIR"

NTFY_TOPIC="diun-updates"
NTFY_SERVER="http://ntfy"
FORCE=""
usage() { sed -n '2,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
parse_common_flags "$@"
for a in "$@"; do
  case "$a" in
    --force)   FORCE="--force" ;;
    --topic=*) NTFY_TOPIC="${a#*=}" ;;
  esac
done

require_docker
require_env || exit 0
load_env

DB="${CONFIG_PATH:-/opt/docker/data}/uptime-kuma/kuma.db"
SEED="$REPO_DIR/monitoring/uptime-kuma/seed.json"
[[ -f "$SEED" ]] || die "seed file missing: $SEED"
docker ps -a --format '{{.Names}}' | grep -qx uptime-kuma \
  || die "uptime-kuma container not found — deploy the monitoring stack first."

# kuma.db is root-owned (Uptime Kuma runs as root in-container), so writing needs sudo.
SUDO=""; [[ -w "$DB" ]] || SUDO="sudo"
$SUDO test -f "$DB" || die "kuma.db not found at $DB — has uptime-kuma started at least once?"

plan "stop uptime-kuma → apply $SEED (alerts via ntfy $NTFY_SERVER/$NTFY_TOPIC) → restart"
show_plan || exit 0
gate || exit 0

say "Stopping uptime-kuma…"; docker stop uptime-kuma >/dev/null
rc=0
$SUDO python3 "$SCRIPT_DIR/seed-uptime-kuma.py" \
  --db "$DB" --seed "$SEED" \
  --ntfy-server "$NTFY_SERVER" --ntfy-topic "$NTFY_TOPIC" $FORCE || rc=$?
say "Starting uptime-kuma…"; docker start uptime-kuma >/dev/null
[[ $rc -eq 0 ]] || die "seeder failed (rc=$rc) — uptime-kuma restarted; no partial state (single transaction)."
say "Done. A down service now alerts via ntfy topic '$NTFY_TOPIC'."
