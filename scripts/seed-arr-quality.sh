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

: "${SONARR_API_KEY:?SONARR_API_KEY missing — run 'hs keys' first}"
: "${RADARR_API_KEY:?RADARR_API_KEY missing — run 'hs keys' first}"
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
    needs_move = [i for i in items if i.get(profile_field) != target_id]
    print(f'  profile {target_name} id={target_id}; items needing move: {len(needs_move)}/{len(items)}')
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

print('\nDone' + (' (dry-run, no changes made)' if DRY else ''))
PY
