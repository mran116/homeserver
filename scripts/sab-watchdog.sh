#!/usr/bin/env bash
# =============================================================================
# sab-watchdog.sh — auto-recover a stalled SABnzbd.
#
# SABnzbd sometimes wedges with downloads stuck at 0 B/s until the container is
# restarted (hung news-server connections). This polls SAB's API and, on a
# *genuine* stall, tries a soft pause->resume first, then restarts the container
# only if that fails. Designed to run from cron every ~5 minutes.
#
# False-positive guards (it does NOT act unless ALL hold, sustained):
#   - queue status is exactly "Downloading"   (so Idle / post-processing —
#     Verifying / Repairing / Extracting / Running scripts — never count)
#   - queue is NOT paused                      (user pause / disk-full pause skip)
#   - there is work left (mbleft > 0)
#   - speed is ~0 (< 1 KB/s)
#   - the above held for STALL_MINUTES (debounce; any healthy poll resets it)
#   - an unreachable API is treated as "no action" (won't restart a SAB you
#     stopped on purpose or one that's mid-deploy)
# After any action the strike counter resets (cooldown -> no restart loops).
#
# Flags: --dry-run (detect + log, never act).
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
cd "$REPO_DIR"

usage() { sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
parse_common_flags "$@"
require_cmd python3
require_env || exit 0
load_env

# --- tunables (keep STALL_MINUTES a multiple of the cron interval) -----------
POLL_MINUTES=5
STALL_MINUTES=15
THRESHOLD=$(( STALL_MINUTES / POLL_MINUTES )); (( THRESHOLD < 1 )) && THRESHOLD=1

: "${SERVER_IP:?SERVER_IP missing from .env}"
SAB_PORT="${SABNZBD_PORT:-8080}"
if [[ -z "${SABNZBD_API_KEY:-}" ]]; then
  echo "$(date '+%F %T') SABNZBD_API_KEY not set — run ./scripts/harvest-keys.sh; skipping" >&2
  exit 0
fi
API="http://${SERVER_IP}:${SAB_PORT}/api"
STATE="${CONFIG_PATH:-/opt/docker/data}/sab-watchdog.state"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

# check — print verdict: "STALLED ..." | "OK ..." | "UNREACHABLE ..."
check() {
  python3 - "$API" "$SABNZBD_API_KEY" <<'PY'
import sys, json, urllib.request, urllib.parse
api, key = sys.argv[1], sys.argv[2]
url = api + '?' + urllib.parse.urlencode({'mode': 'queue', 'output': 'json', 'apikey': key})
try:
    with urllib.request.urlopen(url, timeout=15) as r:
        q = json.load(r).get('queue', {})
except Exception as e:
    print(f"UNREACHABLE {e}"); sys.exit(0)
status = q.get('status', '?')
paused = bool(q.get('paused', False))
def num(v):
    try: return float(v)
    except (TypeError, ValueError): return 0.0
kbps, mbleft = num(q.get('kbpersec')), num(q.get('mbleft'))
stalled = status == 'Downloading' and not paused and mbleft > 0 and kbps < 1.0
print(f"{'STALLED' if stalled else 'OK'} status={status} paused={paused} kbps={kbps:.0f} mbleft={mbleft:.0f}")
PY
}

# sab_api MODE — fire a SAB control command (pause/resume)
sab_api() {
  python3 - "$API" "$SABNZBD_API_KEY" "$1" <<'PY' || true
import sys, urllib.request, urllib.parse
api, key, mode = sys.argv[1], sys.argv[2], sys.argv[3]
url = api + '?' + urllib.parse.urlencode({'mode': mode, 'output': 'json', 'apikey': key})
try: urllib.request.urlopen(url, timeout=15).read()
except Exception: sys.exit(1)
PY
}

# notify MSG — best-effort ntfy push (topic: sab-watchdog)
notify() {
  [[ -n "${NTFY_PORT:-}" ]] || return 0
  python3 - "http://${SERVER_IP}:${NTFY_PORT}/sab-watchdog" "$1" <<'PY' 2>/dev/null || true
import sys, urllib.request
try:
    urllib.request.urlopen(urllib.request.Request(sys.argv[1], data=sys.argv[2].encode(), method='POST'), timeout=10).read()
except Exception: pass
PY
}

verdict="$(check)"; tag="${verdict%% *}"

# Anything but a real stall -> reset the counter and stop.
if [[ "$tag" != "STALLED" ]]; then
  echo 0 > "$STATE" 2>/dev/null || true
  [[ "$tag" == "UNREACHABLE" ]] && log "SAB API unreachable ($verdict) — no action"
  exit 0
fi

prev="$(cat "$STATE" 2>/dev/null || echo 0)"; [[ "$prev" =~ ^[0-9]+$ ]] || prev=0
strikes=$(( prev + 1 )); echo "$strikes" > "$STATE" 2>/dev/null || true
log "stall detected ($verdict) — strike $strikes/$THRESHOLD"
(( strikes < THRESHOLD )) && exit 0

if [[ $DRY_RUN -eq 1 ]]; then
  log "[dry-run] threshold reached — would pause/resume, then restart sabnzbd if still stalled"
  exit 0
fi

# Soft recovery: pause -> resume (no downtime, keeps partial downloads).
log "recovering: pause -> resume"
sab_api pause; sleep 10; sab_api resume; sleep 30
verdict2="$(check)"
if [[ "${verdict2%% *}" != "STALLED" ]]; then
  log "recovered via pause/resume ($verdict2)"
  echo 0 > "$STATE" 2>/dev/null || true
  notify "SABnzbd was stalling — recovered with pause/resume."
  exit 0
fi

# Hard recovery: restart the container.
log "still stalled ($verdict2) — restarting sabnzbd container"
if docker restart sabnzbd >/dev/null 2>&1; then
  log "restarted sabnzbd"
  notify "SABnzbd was stalled — restarted the container."
else
  log "ERROR: 'docker restart sabnzbd' failed"
  notify "SABnzbd stalled and the restart FAILED — check it."
fi
echo 0 > "$STATE" 2>/dev/null || true   # cooldown: require a fresh stall window
