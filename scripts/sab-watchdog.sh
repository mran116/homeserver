#!/usr/bin/env bash
# =============================================================================
# sab-watchdog.sh — auto-recover a stalled SABnzbd.
#
# SABnzbd sometimes wedges until the container is restarted — either stuck at
# 0 B/s, or frozen showing traffic/speed while making NO real progress (hung
# news-server connections, a wedged write). This polls SAB's API and, on a
# *genuine* stall, tries a soft pause->resume first, then restarts the container
# only if that fails. Designed to run from cron every ~5 minutes.
#
# False-positive guards (it does NOT act unless ALL hold, sustained):
#   - queue status is exactly "Downloading"   (so Idle / post-processing —
#     Verifying / Repairing / Extracting / Running scripts — never count)
#   - queue is NOT paused                      (user pause / disk-full pause skip)
#   - there is work left (mbleft > 0)
#   - mbleft is UNCHANGED since the last poll (a frozen SAB shows a non-zero
#     speed but makes no real progress), OR kbps is BYTE-IDENTICAL to the last
#     poll while > 0 (SAB's UI caches a stale speed reading even when the
#     download threads are deadlocked; real network speeds never read identical
#     to the byte across a 5-min interval). Either signal counts. mbleft can
#     legitimately rise (Sonarr queuing more) while downloads are frozen, so
#     the kbps-identity check is what catches that case.
#   - the above held for STALL_MINUTES (debounce; any change resets the strikes)
#   - a SUSTAINED unreachable API also strikes (a wedged SAB stops serving HTTP
#     entirely — observed in the wild). Short outages (deploy, manual restart)
#     never reach the threshold because a brief unreachability resets in one
#     cycle if SAB comes back.
# After any action the strike counter resets (cooldown -> no restart loops).
#
# Separately, a par2-zombie guard kills any par2 repair running longer than
# PAR2_MAX_MINUTES (default 60): SAB post-processes serially, so one doomed
# repair otherwise blocks the whole unpack queue for hours (observed 8h+).
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
# Keep the data root clean — state lives in its own subfolder like every app's
# data. mkdir is required: the writes below are guarded with `|| true`, so a
# missing dir would silently drop the state (strikes never accumulate).
STATE_DIR="${CONFIG_PATH:-/opt/docker/data}/sab-watchdog"
mkdir -p "$STATE_DIR" 2>/dev/null || true
STATE="$STATE_DIR/state"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

# check PREV_MBLEFT PREV_KBPS — print verdict: "STALLED ..." | "OK ..." | "UNREACHABLE ..."
# A stall = actively downloading but EITHER mbleft is UNCHANGED versus
# PREV_MBLEFT (a frozen SAB making no real progress) OR kbps reads identical
# to PREV_KBPS while > 0 (SAB serves a cached stale speed even when its
# download threads are deadlocked; real networks never read byte-identical
# across a 5-min poll). The kbps-identity signal catches the case where
# Sonarr is adding items so mbleft rises while downloads are frozen.
# PREV_MBLEFT empty (first poll) falls back to the speed-near-zero signal.
check() {
  python3 - "$API" "$SABNZBD_API_KEY" "${1:-}" "${2:-}" <<'PY'
import sys, json, urllib.request, urllib.parse
api, key = sys.argv[1], sys.argv[2]
prev_mbleft_arg = sys.argv[3] if len(sys.argv) > 3 else ''
prev_kbps_arg   = sys.argv[4] if len(sys.argv) > 4 else ''
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
active = status == 'Downloading' and not paused and mbleft > 0
def parse_int(s):
    try: return int(float(s)) if s not in ('', 'None') else None
    except ValueError: return None
prev_mb, prev_kb = parse_int(prev_mbleft_arg), parse_int(prev_kbps_arg)
if prev_mb is not None:
    mbleft_frozen = round(mbleft) == prev_mb
    kbps_frozen   = prev_kb is not None and round(kbps) == prev_kb and kbps > 0
    stalled = active and (mbleft_frozen or kbps_frozen)
else:
    stalled = active and kbps < 1.0                    # first-poll fallback
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

# --- par2-zombie guard --------------------------------------------------------
# SAB post-processes jobs ONE at a time, so a single doomed par2 repair (an
# incomplete post that can never assemble) can spin at 100% CPU for hours while
# every later job sits "Queued" — downloads keep landing but nothing completes.
# This is invisible to the stall detector below (speed/mbleft keep moving), so
# it gets its own check: kill any par2 inside the container that has been
# running longer than PAR2_MAX_MINUTES. SAB then marks that one job as a failed
# repair and the post-processing queue moves on. A legitimate repair of even a
# multi-GB remux finishes well inside an hour; anything past that is wedged.
PAR2_MAX_MINUTES="${PAR2_MAX_MINUTES:-60}"
while read -r etimes pid comm; do
  [[ "$comm" == *par2* && "$etimes" =~ ^[0-9]+$ && "$pid" =~ ^[0-9]+$ ]] || continue
  (( etimes > PAR2_MAX_MINUTES * 60 )) || continue
  if [[ $DRY_RUN -eq 1 ]]; then
    log "[dry-run] par2 zombie pid=$pid ($(( etimes / 60 )) min) — would kill"
    continue
  fi
  log "killing par2 zombie pid=$pid (running $(( etimes / 60 )) min > ${PAR2_MAX_MINUTES} min cap)"
  docker exec sabnzbd kill -9 "$pid" >/dev/null 2>&1 || true
  notify "SABnzbd: killed a par2 repair wedged for $(( etimes / 60 )) min — it was blocking all post-processing."
done < <(docker exec sabnzbd ps -eo etimes=,pid=,comm= 2>/dev/null || true)

# State carries "<strikes> <last_mbleft> <last_kbps>" — last_mbleft + last_kbps
# both feed the next poll's stall detection. Old 2-field format reads cleanly
# (last_kbps stays empty → kbps-identity check is skipped on the first new poll).
prev_strikes=0; prev_mbleft=""; prev_kbps=""
[[ -f "$STATE" ]] && read -r prev_strikes prev_mbleft prev_kbps < "$STATE" 2>/dev/null
[[ "$prev_strikes" =~ ^[0-9]+$ ]] || prev_strikes=0

verdict="$(check "$prev_mbleft" "$prev_kbps")"; tag="${verdict%% *}"
cur_mbleft="$(sed -n 's/.*mbleft=\([0-9]*\).*/\1/p' <<<"$verdict")"; [[ -n "$cur_mbleft" ]] || cur_mbleft=0
cur_kbps="$(sed -n 's/.*kbps=\([0-9]*\).*/\1/p' <<<"$verdict")";    [[ -n "$cur_kbps" ]]   || cur_kbps=0

# A sustained UNREACHABLE is also a wedge (observed: SAB stops serving HTTP
# entirely when fully deadlocked). Accumulate strikes; the threshold (15 min)
# is far longer than any normal deploy or manual restart, so brief outages
# never escalate.
if [[ "$tag" == "UNREACHABLE" ]]; then
  strikes=$(( prev_strikes + 1 ))
  echo "$strikes ${prev_mbleft:-0} ${prev_kbps:-0}" > "$STATE" 2>/dev/null || true
  log "SAB API unreachable ($verdict) — strike $strikes/$THRESHOLD"
  (( strikes < THRESHOLD )) && exit 0
elif [[ "$tag" != "STALLED" ]]; then
  echo "0 $cur_mbleft $cur_kbps" > "$STATE" 2>/dev/null || true
  exit 0
else
  strikes=$(( prev_strikes + 1 ))
  echo "$strikes $cur_mbleft $cur_kbps" > "$STATE" 2>/dev/null || true
  log "stall detected ($verdict) — strike $strikes/$THRESHOLD"
  (( strikes < THRESHOLD )) && exit 0
fi

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
