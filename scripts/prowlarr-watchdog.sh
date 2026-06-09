#!/usr/bin/env bash
# =============================================================================
# prowlarr-watchdog.sh — auto-recover a wedged Prowlarr search path.
#
# Prowlarr occasionally jams: its management API still answers, but the SEARCH
# path — the single funnel every Sonarr/Radarr query flows through — hangs, so
# all grabbing silently stops and Sonarr/Radarr raise "Indexers unavailable due
# to failures". Flooding it with searches (aggressive backlog runs) is the usual
# trigger. The fix is a `docker restart prowlarr flaresolverr`.
#
# Rather than fire our own test SEARCH every cycle (which would burn the very
# indexer API limits that caused the jam), this watches the SYMPTOM: Sonarr +
# Radarr health. On a sustained "indexers unavailable" across a debounce window
# it restarts prowlarr (+ flaresolverr) so the lockup self-heals — adding ZERO
# indexer load itself. Designed to run from cron every ~5 minutes.
#
# False-positive guards:
#   - must hold for STALL_MINUTES sustained (strikes; any healthy poll resets)
#   - an *arr being unreachable does NOT strike (that's a different problem)
#   - after a restart the strike counter resets (cooldown -> no restart loops)
#
# Flags: --dry-run (detect + log, never act).
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
cd "$REPO_DIR"

usage() { sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
parse_common_flags "$@"
require_cmd python3
require_cmd docker
require_env || exit 0
load_env

# --- tunables (keep STALL_MINUTES a multiple of the cron interval) -----------
POLL_MINUTES=5
STALL_MINUTES=15
THRESHOLD=$(( STALL_MINUTES / POLL_MINUTES )); (( THRESHOLD < 1 )) && THRESHOLD=1

DATA="${CONFIG_PATH:-/opt/docker/data}"
# *arr API keys read straight from their config.xml — always present once the
# apps have booted, so no dependency on the keys being harvested into .env.
arr_key() { sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' "$DATA/$1/config.xml" 2>/dev/null | head -1; }
SONARR_KEY="$(arr_key sonarr)"; RADARR_KEY="$(arr_key radarr)"; PROWLARR_KEY="$(arr_key prowlarr)"

# State dir lives beside every app's data, like sab-watchdog. mkdir is required:
# the writes below are guarded with `|| true`, so a missing dir would silently
# drop the strike counter (it would never accumulate).
STATE_DIR="$DATA/prowlarr-watchdog"
mkdir -p "$STATE_DIR" 2>/dev/null || true
STATE="$STATE_DIR/state"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

# check — two stage, so a single flaky indexer never triggers a restart:
#   1. SYMPTOM: do Sonarr/Radarr report indexers unavailable? (cheap, no indexer
#      load). If neither does -> OK, done.
#   2. CONFIRM: only when (1) fires, run ONE Prowlarr search. If it RETURNS (even
#      with some indexers erroring) the search funnel is healthy -> OK. If it
#      HANGS/errors, the funnel itself is wedged -> STALLED.
# Because the confirming search runs only while the *arr are complaining, the
# watchdog adds ~zero indexer load in steady state. An *arr we can't reach is
# ignored, so a Sonarr/Radarr outage can't trigger a needless Prowlarr restart.
check() {
  python3 - "$SONARR_KEY" "$RADARR_KEY" "$PROWLARR_KEY" <<'PY'
import sys, json, urllib.request, urllib.parse
sk, rk, pk = sys.argv[1], sys.argv[2], sys.argv[3]
down = []
for name, port, key in (("sonarr", "8989", sk), ("radarr", "7878", rk)):
    if not key:
        continue
    try:
        req = urllib.request.Request(f"http://localhost:{port}/api/v3/health",
                                     headers={"X-Api-Key": key})
        msgs = [h.get("message", "").lower() for h in json.load(urllib.request.urlopen(req, timeout=10))]
        if any("indexer" in m and ("unavailable" in m or "failure" in m) for m in msgs):
            down.append(name)
    except Exception:
        pass  # arr unreachable = different problem; do not act on it
if not down:
    print("OK"); sys.exit(0)
if not pk:
    print("STALLED indexers-unavailable=" + ",".join(down) + " (no prowlarr key to confirm)"); sys.exit(0)
url = "http://localhost:9696/api/v1/search?" + urllib.parse.urlencode({"query": "interstellar", "limit": "3", "apikey": pk})
try:
    urllib.request.urlopen(url, timeout=30).read()
    print("OK arr-warned=" + ",".join(down) + " but prowlarr search returned (funnel healthy)")
except Exception as e:
    print("STALLED indexers-unavailable=" + ",".join(down) + " prowlarr-search-hung=" + type(e).__name__)
PY
}

# notify MSG — best-effort ntfy push (same homestack topic as the other alerts)
notify() {
  [[ -n "${NTFY_PORT:-}" && -n "${SERVER_IP:-}" ]] || return 0
  python3 - "http://${SERVER_IP}:${NTFY_PORT}/homestack" "$1" <<'PY' 2>/dev/null || true
import sys, urllib.request
try:
    urllib.request.urlopen(urllib.request.Request(
        sys.argv[1], data=sys.argv[2].encode(), method="POST",
        headers={"Title": "Prowlarr watchdog", "Priority": "high",
                 "Tags": "mag,arrows_counterclockwise"}), timeout=10).read()
except Exception:
    pass
PY
}

prev_strikes=0
[[ -f "$STATE" ]] && read -r prev_strikes < "$STATE" 2>/dev/null
[[ "$prev_strikes" =~ ^[0-9]+$ ]] || prev_strikes=0

verdict="$(check)"
if [[ "${verdict%% *}" != "STALLED" ]]; then
  echo 0 > "$STATE" 2>/dev/null || true
  exit 0
fi

strikes=$(( prev_strikes + 1 ))
echo "$strikes" > "$STATE" 2>/dev/null || true
log "indexers unavailable ($verdict) — strike $strikes/$THRESHOLD"
(( strikes < THRESHOLD )) && exit 0

if [[ ${DRY_RUN:-0} -eq 1 ]]; then
  log "[dry-run] threshold reached — would restart prowlarr + flaresolverr"
  exit 0
fi

log "restarting prowlarr + flaresolverr"
if docker restart prowlarr flaresolverr >/dev/null 2>&1; then
  log "restarted prowlarr + flaresolverr"
  notify "Prowlarr search path was jammed (Sonarr/Radarr indexers unavailable) — restarted Prowlarr + flaresolverr."
else
  log "ERROR: 'docker restart prowlarr flaresolverr' failed"
  notify "Prowlarr jammed and the restart FAILED — check it."
fi
echo 0 > "$STATE" 2>/dev/null || true   # cooldown: require a fresh stall window
