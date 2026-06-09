#!/usr/bin/env bash
# =============================================================================
# seed-arr-quality.sh
#
# Idempotent post-recyclarr seed: migrates every Sonarr series and Radarr movie
# to the recyclarr-managed quality profiles, and sets the language preference
# (English) on the Radarr quality profile.  Sonarr v4's language filter is
# applied via the Custom Format scores recyclarr already manages — the
# Sonarr quality profile's `language` field is the old v3 mechanism and ignored
# now, so we don't bother setting it.
#
# What this fixes that recyclarr can't:
#   - recyclarr creates profiles but doesn't move existing series/movies onto them
#   - recyclarr doesn't expose the language field on quality profiles
#
# Safe to re-run any time.  Only modifies items not already on the target.
# Soft-skips when target profiles don't exist yet (e.g. before recyclarr's
# first successful sync).
#
# Usage:
#   ./scripts/seed-arr-quality.sh                # interactive (gated)
#   ./scripts/seed-arr-quality.sh --yes          # non-interactive
#   ./scripts/seed-arr-quality.sh --dry-run      # preview only
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: seed-arr-quality.sh [--yes] [--dry-run]

  Move every Sonarr series + Radarr movie onto the recyclarr-managed quality
  profiles, set Radarr's language=English on its quality profile.  Idempotent.

  --yes / -y       apply without prompting
  --dry-run / -n   show plan, change nothing
  --help / -h      this help
EOF
}

parse_common_flags "$@"
require_cmd docker
require_cmd python3

# Load .env so we know SONARR_API_KEY / RADARR_API_KEY.
if [[ -f "$REPO_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  set -a; source "$REPO_DIR/.env"; set +a
fi

# *arr API keys are harvested only AFTER the apps boot once (`hs keys`), so on a
# fresh install they're still blank. This is a post-first-boot seed — skip
# cleanly rather than abort bootstrap. It's idempotent and does its real work on
# the next run once the keys exist.
if [[ -z "${SONARR_API_KEY:-}" || -z "${RADARR_API_KEY:-}" ]]; then
  warn "seed-arr-quality: *arr API keys not set yet — skipping (run 'hs keys' after first boot, then re-run; harmless on first setup)."
  exit 0
fi
: "${SERVER_IP:?SERVER_IP missing from .env}"
: "${SONARR_PORT:?SONARR_PORT missing from .env}"
: "${RADARR_PORT:?RADARR_PORT missing from .env}"

# Containers must be running for this to do anything.
for c in sonarr radarr; do
  if ! docker ps --format '{{.Names}}' | grep -qx "$c"; then
    warn "'$c' not running — skipping seed (run after mediastack is up)"
    exit 0
  fi
done

# Dry-run / preview mode: report what *would* change.
MODE="apply"
[[ $DRY_RUN -eq 1 ]] && MODE="dry"

DRY_RUN_FLAG=$MODE python3 - "$SONARR_API_KEY" "$RADARR_API_KEY" \
    "http://${SERVER_IP}:${SONARR_PORT}/api/v3" \
    "http://${SERVER_IP}:${RADARR_PORT}/api/v3" <<'PY'
import os, sys, urllib.request, urllib.parse, urllib.error, json

sonarr_key, radarr_key, sonarr_base, radarr_base = sys.argv[1:5]
DRY = os.environ.get('DRY_RUN_FLAG') == 'dry'

INSTANCES = [
    ('sonarr', sonarr_base, sonarr_key, 'WEB-1080p', '/series',  'qualityProfileId'),
    ('radarr', radarr_base, radarr_key, 'WEB-Only',  '/movie',   'qualityProfileId'),
]

# Series on these profiles are intentional exceptions (e.g. Star Trek TNG and
# other film-sourced shows that only exist as 1080p Bluray, not WEB-DL). The
# migrate-to-target step below leaves them in place so they keep Bluray-1080p
# access; the global size caps below still bound their bitrate.
KEEP_PROFILES = {'sonarr': {'HD-1080p'}, 'radarr': set()}

# Global Sonarr quality-definition size caps in MB/min: name -> (preferred, max).
# min is left at the TRaSH/stock value. These bound episode bitrate across ALL
# profiles: capping Bluray-1080p pulls film-sourced shows down from DTS-HD MA
# remuxes to ~x264 encodes; the WEBDL/WEBRip caps trim over-bitrate WEB grabs.
# ~90 MB/min ≈ a 4 GB ceiling / ~2.7 GB typical for a 45-min episode. recyclarr's
# `quality_definition` (TRaSH) leaves these Unlimited, so it's removed from
# recyclarr.yml and owned here instead (else the nightly sync would reset them).
SONARR_QUALITY_CAPS = {
    'WEBDL-1080p':  (60, 90),
    'WEBRip-1080p': (60, 90),
    'HDTV-1080p':   (50, 80),
    'Bluray-1080p': (65, 90),
    'Bluray-1080p Remux': (90, 120),   # cap lossless remux episodes (~5.4 GB/45min)
    # 2160p generally unused (profiles are 1080p) but capped as a backstop:
    'WEBDL-2160p':  (80, 130),
    'WEBRip-2160p': (80, 130),
    'HDTV-2160p':   (70, 130),
    'Bluray-2160p': (100, 160),
    'Bluray-2160p Remux': (130, 200),
}

# Global Radarr quality-definition size caps in MB/min: name -> (preferred, max).
# Radarr definitions are GLOBAL too, so one cap per quality bounds bitrate across
# every profile. 1080p capped to ~50 MB/min ~= ~6 GB for a 2 h film (still above
# streaming-premium bitrate); 720p ~25. recyclarr's movie quality_definition
# leaves max "Unlimited", so it's removed from recyclarr.yml and owned here (else
# the nightly sync would reset these).
RADARR_QUALITY_CAPS = {
    'WEBDL-1080p':  (40, 50),
    'WEBRip-1080p': (40, 50),
    'HDTV-1080p':   (35, 50),
    'WEBDL-720p':   (20, 25),
    'WEBRip-720p':  (20, 25),
    'HDTV-720p':    (18, 25),
    'Bluray-1080p': (60, 90),     # was uncapped — the 25 GB hole; ~10.8 GB/2h max
    'Remux-1080p':  (90, 130),    # cap lossless remux; ~15.6 GB/2h max
    'Bluray-720p':  (25, 40),
    # 2160p generally unused (movie profiles are 1080p) but capped as a backstop:
    'WEBDL-2160p':  (60, 120),
    'WEBRip-2160p': (60, 120),
    'HDTV-2160p':   (50, 120),
    'Bluray-2160p': (90, 160),
    'Remux-2160p':  (130, 220),
}

# Per-service cap table consumed by the quality-definition pass below.
QUALITY_CAPS = {'sonarr': SONARR_QUALITY_CAPS, 'radarr': RADARR_QUALITY_CAPS}

def api(base, key, method, path, body=None, query=None):
    url = base + path + (('?' + urllib.parse.urlencode(query)) if query else '')
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
        headers={'X-Api-Key': key, 'Content-Type': 'application/json'})
    try:
        r = urllib.request.urlopen(req, timeout=30)
        b = r.read()
        return json.loads(b) if b else None
    except urllib.error.HTTPError as e:
        msg = e.read().decode(errors='replace')[:300]
        raise SystemExit(f'{method} {path} -> HTTP {e.code}: {msg}')

def english_lang_id(base, key):
    langs = api(base, key, 'GET', '/language')
    eng = next((l for l in langs if l['name'].lower() == 'english'), None)
    if not eng:
        raise SystemExit(f'{base}: English language not found')
    return eng['id'], eng['name']

errors = 0
for service, base, key, target_name, list_path, profile_field in INSTANCES:
    print(f'\n=== {service} ===')
    qps = api(base, key, 'GET', '/qualityprofile')
    target = next((q for q in qps if q['name'] == target_name), None)
    if not target:
        print(f'  skip: profile "{target_name}" does not exist yet — run recyclarr sync first')
        continue
    target_id = target['id']
    eng_id, eng_name = english_lang_id(base, key)

    # Move items to target profile
    items = api(base, key, 'GET', list_path)
    keep_ids = {q['id'] for q in qps if q['name'] in KEEP_PROFILES.get(service, set())}
    needs_move = [i for i in items
                  if i.get(profile_field) != target_id and i.get(profile_field) not in keep_ids]
    pinned = sum(1 for i in items if i.get(profile_field) in keep_ids)
    msg = f'  profile {target_name} id={target_id}; items needing move: {len(needs_move)}/{len(items)}'
    if pinned:
        msg += f' ({pinned} pinned on {sorted(KEEP_PROFILES[service])})'
    print(msg)
    if not DRY:
        for it in needs_move:
            it[profile_field] = target_id
            api(base, key, 'PUT', f'{list_path}/{it["id"]}', body=it)

    # Sonarr v4 ignores the language field on quality profiles (it's the old v3
    # mechanism; v4 filters language via Custom Format scores, which recyclarr
    # already manages).  For Radarr, the language field is still honoured.
    if service != 'sonarr':
        qp = api(base, key, 'GET', f'/qualityprofile/{target_id}')
        cur_lang_id = (qp.get('language') or {}).get('id')
        if cur_lang_id != eng_id:
            print(f'  profile language: current id={cur_lang_id} -> setting to {eng_id} ({eng_name})')
            if not DRY:
                qp['language'] = {'id': eng_id, 'name': eng_name}
                api(base, key, 'PUT', f'/qualityprofile/{target_id}', body=qp)
        else:
            print(f'  profile language already {eng_name}')
    else:
        print('  language filter: applied via CF scoring (Sonarr v4 ignores profile.language)')

    # Global quality-definition size caps (Sonarr + Radarr). Quality definitions
    # are GLOBAL in both apps (not per-profile), so one cap per quality bounds
    # bitrate everywhere — see SONARR_QUALITY_CAPS / RADARR_QUALITY_CAPS above.
    caps = QUALITY_CAPS.get(service)
    if caps:
        defs = api(base, key, 'GET', '/qualitydefinition')
        changed = 0
        for d in defs:
            qn = (d.get('quality') or {}).get('name')
            if qn not in caps:
                continue
            pref, mx = caps[qn]
            if d.get('preferredSize') == pref and d.get('maxSize') == mx:
                continue
            print(f'  cap {qn}: preferred {d.get("preferredSize")}->{pref}, '
                  f'max {d.get("maxSize")}->{mx} (MB/min)')
            changed += 1
            if not DRY:
                # keep minSize <= preferred < max (some remux/2160p stock minSize
                # exceeds the new cap, which the API rejects with HTTP 400)
                d['minSize'] = min(d.get('minSize') or 0, pref)
                d['preferredSize'] = pref
                d['maxSize'] = mx
                api(base, key, 'PUT', f'/qualitydefinition/{d["id"]}', body=d)
        print(f'  quality-definition size caps: {changed} changed'
              if changed else '  quality-definition size caps: already in place')

print('\nDone' + (' (dry-run, no changes made)' if DRY else ''))
PY
