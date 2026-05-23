#!/usr/bin/env bash
# =============================================================================
# doctor.sh — read-only health check. Changes nothing; tells you what's wrong.
#
# Checks: docker daemon + compose, the `home` network, .env present and in sync
# with .env.example, per-stack .env symlinks, STACKS_PATH, every compose file
# validates, vars referenced by ACTIVE services that are still blank, and the
# port-53 / systemd-resolved conflict that stops AdGuard.
#
# Exit: non-zero if any hard FAIL (handy as a pre-deploy gate). Flags: none.
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
cd "$REPO_DIR"

FAILS=0; WARNS=0
ok()   { printf '  %s✓%s %s\n' "$c_green"  "$c_reset" "$*"; }
bad()  { printf '  %s✗%s %s\n' "$c_red"    "$c_reset" "$*"; FAILS=$((FAILS+1)); }
note() { printf '  %s!%s %s\n' "$c_yellow" "$c_reset" "$*"; WARNS=$((WARNS+1)); }
have_daemon=0

say "Docker"
if ! command -v docker >/dev/null; then bad "docker not installed"
else
  docker compose version >/dev/null 2>&1 && ok "docker compose v2 present" || bad "docker compose v2 missing"
  if docker info >/dev/null 2>&1; then have_daemon=1; ok "docker daemon reachable"
  else note "docker daemon not reachable (not in 'docker' group? network checks skipped)"; fi
fi

if [[ $have_daemon -eq 1 ]]; then
  say "Network"
  docker network inspect home >/dev/null 2>&1 && ok "'home' network exists" \
    || bad "'home' network missing — run ./scripts/create-network.sh"
fi

say ".env"
if [[ -f "$ENV_FILE" ]]; then
  ok ".env present"
  missing="$(comm -13 \
    <(grep -oE '^[A-Z0-9_]+=' "$ENV_FILE"  | sed 's/=$//' | sort -u) \
    <(grep -oE '^[A-Z0-9_]+=' .env.example | sed 's/=$//' | sort -u))"
  if [[ -z "$missing" ]]; then ok "in sync with .env.example"
  else note "$(printf '%s' "$missing" | grep -c .) var(s) missing vs .env.example — run ./scripts/env-sync.sh"; fi
else
  bad ".env missing — run ./scripts/env-init.sh"
fi

say "Stack wiring"
if [[ "$(current_value STACKS_PATH)" == "$REPO_DIR" ]]; then ok "STACKS_PATH = $REPO_DIR"
else note "STACKS_PATH != repo path — run ./scripts/link-env.sh"; fi
bad_links=0
for compose in */docker-compose.yml; do
  d="$(dirname "$compose")"
  [[ "$(readlink "$d/.env" 2>/dev/null)" == "../.env" ]] || { note "missing/incorrect symlink: $d/.env"; bad_links=1; }
done
[[ $bad_links -eq 0 ]] && ok "every stack has its .env symlink" || note "fix with ./scripts/link-env.sh"

say "Compose validity"
ENV_ARG=(); [[ -f "$ENV_FILE" ]] && ENV_ARG=(--env-file "$ENV_FILE") || ENV_ARG=(--env-file .env.example)
if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
  for compose in */docker-compose.yml; do
    if docker compose -f "$compose" "${ENV_ARG[@]}" config -q >/dev/null 2>&1; then
      ok "${compose%/*} compose valid"
    else
      # A stack whose services are all commented out (e.g. devops placeholder)
      # fails config with "no services" — that's intentional, not broken.
      active=$(awk '/^services:/{i=1;next} /^[^[:space:]#]/{i=0} i&&/^  [A-Za-z0-9_-]+:[[:space:]]*$/{n++} END{print n+0}' "$compose")
      if [[ "${active:-0}" -eq 0 ]]; then note "${compose%/*} placeholder (all services commented) — skipped"
      else bad "${compose%/*} compose INVALID — docker compose -f $compose config"; fi
    fi
  done
else
  note "docker compose unavailable — skipped compose validation"
fi

say "Env values referenced by active services"
if [[ -f "$ENV_FILE" ]]; then
  report="$(python3 - "$ENV_FILE" <<'PY'
import glob, re, pathlib, sys
env = {}
for ln in pathlib.Path(sys.argv[1]).read_text().splitlines():
    m = re.match(r'^([A-Z0-9_]+)=(.*)$', ln)
    if m: env[m.group(1)] = re.split(r'\s+#', m.group(2), 1)[0].strip()
REQUIRED = set("WIREGUARD_PRIVATE_KEY WIREGUARD_ADDRESSES NPM_DB_PASSWORD NPM_DB_ROOT_PASSWORD "
               "IMMICH_DB_PASSWORD PAPERLESS_DB_PASSWORD PAPERLESS_SECRET_KEY DONETICK_JWT_SECRET "
               "VAULTWARDEN_ADMIN_TOKEN ARCANE_ENCRYPTION_KEY ARCANE_JWT_SECRET".split())
refs = {}
for f in sorted(glob.glob('*/docker-compose.yml')):
    for ln in pathlib.Path(f).read_text().splitlines():
        if ln.lstrip().startswith('#'):      # skip commented (inactive) services
            continue
        for m in re.finditer(r'\$\{([A-Z0-9_]+)(:-[^}]*|:\?[^}]*)?\}', ln):
            if m.group(2) and m.group(2).startswith(':-'):   # has a default -> fine
                continue
            refs.setdefault(m.group(1), set()).add(pathlib.Path(f).parent.name)
for var in sorted(refs):
    val = env.get(var)
    if val is None or val == '':
        tag = "REQ" if var in REQUIRED else "OPT"
        print(f"{tag} {var} {','.join(sorted(refs[var]))}")
PY
)"
  if [[ -z "$report" ]]; then ok "all active-service vars have values"
  else
    while read -r tag var stacks; do
      [[ -z "$tag" ]] && continue
      if [[ "$tag" == REQ ]]; then bad "$var is blank but required ($stacks)"
      else note "$var blank — fine for optional widgets, set if you use it ($stacks)"; fi
    done <<<"$report"
  fi
else
  note "no .env — skipped value check"
fi

say "AdGuard port 53"
if command -v systemctl >/dev/null && systemctl is-active --quiet systemd-resolved 2>/dev/null; then
  note "systemd-resolved is active and holds :53 — AdGuard won't start until it's freed (see infrastructure/docker-compose.yml)"
elif command -v ss >/dev/null && ss -lntu 2>/dev/null | grep -qE '[:.]53\b'; then
  note "something is listening on :53 — verify it's AdGuard, not a conflict"
else
  ok "no obvious :53 conflict"
fi

echo
if [[ $FAILS -gt 0 ]]; then die "$FAILS problem(s), $WARNS warning(s). Fix the ✗ items above."; fi
[[ $WARNS -gt 0 ]] && say "Healthy with $WARNS warning(s)." || say "All checks passed."
