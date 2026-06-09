#!/usr/bin/env bash
# =============================================================================
# modern-pokemon.sh — acquire + own modern Pokémon end-to-end, OUTSIDE Sonarr.
#
# TheTVDB has no usable entry for the modern sub-series (Journeys/Horizons) — it
# files them under the one Pokémon entry which caps at S20, and the releases are
# named with their own "S01E###", so Sonarr has nowhere to import them. This
# bypasses Sonarr entirely:
#   1) IMPORT  — move completed SAB Pokémon grabs into Jellyfin-direct folders
#                (Jellyfin then identifies them via TMDB, which HAS the shows).
#   2) ACQUIRE — search Prowlarr for new English usenet episodes of each
#                configured series and grab the best via SAB (capped per run).
#
# Dedup state: $CONFIG_PATH/modern-pokemon/grabbed (one "<folder>|SxxEyy" / line).
# Designed for cron (e.g. */30). Flags: --dry-run (plan only — no grabs/moves).
# Env knobs: MODERN_POKEMON_MAX (per-run grab cap, default 6), MEDIA_PATH.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
cd "$REPO_DIR"

usage() { sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
parse_common_flags "$@"
require_cmd python3
require_cmd docker
require_env || exit 0
load_env

DATA="${CONFIG_PATH:-/opt/docker/data}"
MEDIA="${MEDIA_PATH:-/mnt/media}"                 # host view of the NAS media share
PKEY="$(sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' "$DATA/prowlarr/config.xml" 2>/dev/null | head -1)"
SABKEY="$(sed -n 's/^[[:space:]]*api_key[[:space:]]*=[[:space:]]*//p' "$DATA/sabnzbd/sabnzbd.ini" 2>/dev/null | head -1)"
[[ -n "$PKEY" && -n "$SABKEY" ]] || { echo "$(date '+%F %T') missing prowlarr/sab key; skipping" >&2; exit 0; }

STATE_DIR="$DATA/modern-pokemon"; mkdir -p "$STATE_DIR" 2>/dev/null || true
STATE="$STATE_DIR/grabbed"; touch "$STATE" 2>/dev/null || true
MAX_GRABS="${MODERN_POKEMON_MAX:-6}"

PROWLARR="http://localhost:9696/api/v1"
SAB="http://${SERVER_IP}:${SABNZBD_PORT:-8080}/api"

python3 - "$PKEY" "$SABKEY" "$PROWLARR" "$SAB" "$MEDIA/usenet/bypass" "$MEDIA/tv" "$STATE" "$MAX_GRABS" "${DRY_RUN:-0}" <<'PY'
import sys, os, re, json, shutil, urllib.request, urllib.parse
pkey, sabkey, PROWLARR, SAB, USENET, TVROOT, STATE, MAXG, DRY = sys.argv[1:10]
MAXG = int(MAXG); DRY = DRY == "1"

# search term -> (Jellyfin folder, regex matching the series part of a release)
SERIES = [
    ("Pokemon Horizons The Series", "Pokémon Horizons (2023)", r"pokemon[. ]+horizons"),
    # The Journeys trilogy is DEFERRED: release groups number Master/Ultimate
    # Journeys inconsistently (same ep appears as S01Exx AND S03Exx), which would
    # grab dupes + confuse Jellyfin. Needs a per-series numbering decision first.
    # ("Pokemon Journeys The Series",         "Pokémon Journeys (2019)",         r"pokemon[. ]+journeys"),
    # ("Pokemon Master Journeys The Series",  "Pokémon Master Journeys (2021)",  r"pokemon[. ]+master[. ]+journeys"),
    # ("Pokemon Ultimate Journeys The Series","Pokémon Ultimate Journeys (2022)",r"pokemon[. ]+ultimate[. ]+journeys"),
]
FOREIGN = re.compile(r"\b(german|french|dutch|italian|spanish|portugu|vostfr|nlsubbed|\.ita\.|sol[. ]e[. ]lua)\b", re.I)
SXE = re.compile(r"\bS(\d{1,2})E(\d{1,3})\b", re.I)

def series_for(name):
    for _, folder, pat in SERIES:
        if re.search(pat, name, re.I):
            return folder
    return None

grabbed = set(l.strip() for l in open(STATE) if l.strip())

# ---- 1) IMPORT: move completed Pokémon files into Jellyfin-direct folders ----
moved = 0
if os.path.isdir(USENET):
    for root, _, files in os.walk(USENET):
        for fn in files:
            if not fn.lower().endswith((".mkv", ".mp4", ".avi")):
                continue
            folder = series_for(fn)
            m = SXE.search(fn)
            if not folder or not m:
                continue
            s, e = int(m.group(1)), int(m.group(2))
            ep = "S%02dE%03d" % (s, e)
            dest_dir = os.path.join(TVROOT, folder, "Season %02d" % s)
            dest = os.path.join(dest_dir, "%s - %s%s" % (folder, ep, os.path.splitext(fn)[1]))
            print("  IMPORT %-44s -> %s/Season %02d/%s" % (fn[:44], folder, s, ep))
            if not DRY:
                os.makedirs(dest_dir, exist_ok=True)
                shutil.move(os.path.join(root, fn), dest)
                moved += 1

# ---- 2) ACQUIRE: search Prowlarr, grab new English usenet episodes via SAB ----
def get(url):
    return json.load(urllib.request.urlopen(url, timeout=45))

def sab_addurl(nzburl, name):
    q = urllib.parse.urlencode({"mode": "addurl", "name": nzburl, "nzbname": name,
                                "cat": "bypass",
                                "apikey": sabkey, "output": "json"})
    try:
        return bool(json.load(urllib.request.urlopen(SAB + "?" + q, timeout=30)).get("status"))
    except Exception as ex:
        print("    SAB error:", ex); return False

grabs = 0
for term, folder, pat in SERIES:
    if grabs >= MAXG:
        break
    try:
        res = get(PROWLARR + "/search?" + urllib.parse.urlencode({"query": term, "limit": "150", "type": "search"}) + "&apikey=" + pkey)
    except Exception as ex:
        print("  search failed for %s: %s" % (term, ex)); continue
    best = {}
    for r in res:
        t = r.get("title", "")
        if (r.get("protocol") != "usenet") or not re.search(pat, t, re.I) or FOREIGN.search(t):
            continue
        m = SXE.search(t)
        dl = (r.get("downloadUrl") or r.get("guid") or "").replace("//localhost:9696", "//prowlarr:9696").replace("//127.0.0.1:9696", "//prowlarr:9696")
        if not m or not dl:
            continue
        key = "%s|S%02dE%03d" % (folder, int(m.group(1)), int(m.group(2)))
        best.setdefault(key, (dl, t))   # first (Prowlarr-ranked) per episode
    new = sorted(k for k in best if k not in grabbed)
    print("  %s: %d eps available, %d new" % (term, len(best), len(new)))
    for key in new:
        if grabs >= MAXG:
            print("    (hit per-run cap %d)" % MAXG); break
        dl, title = best[key]
        print("    GRAB %s  %s" % (key.split("|")[1], title[:46]))
        if not DRY:
            if sab_addurl(dl, title):
                grabbed.add(key); grabs += 1

if not DRY:
    open(STATE, "w").write("\n".join(sorted(grabbed)) + "\n")
print("\n  imported %d file(s), grabbed %d new episode(s)%s" % (moved, grabs, " [DRY-RUN]" if DRY else ""))
PY
