#!/usr/bin/env bash
# =============================================================================
# Homeserver bootstrap
#
# One-shot host setup: prereq check, interactive .env, directory layout,
# docker network, homepage seed, optional Dockge start.
#
# Safe to re-run — it never overwrites an existing .env or existing data.
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

# ---- helpers ----------------------------------------------------------------
c_reset=$'\033[0m'; c_bold=$'\033[1m'; c_green=$'\033[32m'
c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_dim=$'\033[2m'

say()  { printf '%s==>%s %s\n' "$c_bold$c_green" "$c_reset" "$*"; }
warn() { printf '%s!!%s %s\n'  "$c_bold$c_yellow" "$c_reset" "$*"; }
die()  { printf '%sxx%s %s\n'  "$c_bold$c_red"    "$c_reset" "$*" >&2; exit 1; }

ask() {
  # ask "Prompt" default_value var_name
  local prompt="$1" default="$2" __var="$3" answer
  read -r -p "$(printf '%s  [%s%s%s]: ' "$prompt" "$c_dim" "$default" "$c_reset")" answer || true
  printf -v "$__var" '%s' "${answer:-$default}"
}

ask_yn() {
  # ask_yn "Prompt" default(Y|n)
  local prompt="$1" default="${2:-Y}" answer
  read -r -p "$(printf '%s [%s]: ' "$prompt" "$default")" answer || true
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy]$ ]]
}

# ---- prereqs ----------------------------------------------------------------
say "Checking prerequisites"
command -v docker >/dev/null || die "docker not found. Install Docker first: https://docs.docker.com/engine/install/"
docker compose version >/dev/null 2>&1 || die "docker compose v2 not found. Upgrade Docker to a recent version."
docker info >/dev/null 2>&1 || die "Cannot talk to the docker daemon. Is your user in the 'docker' group? (Try: sudo usermod -aG docker \$USER, then log out and back in.)"

# ---- gather config ----------------------------------------------------------
if [[ -f .env ]]; then
  warn ".env already exists — skipping interactive setup."
  warn "Delete or back up .env first if you want to reconfigure."
else
  say "Configuring .env (press Enter to accept each default)"
  echo

  default_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  default_ip="${default_ip:-192.168.1.100}"
  default_tz="$(cat /etc/timezone 2>/dev/null || echo America/Chicago)"
  default_puid="$(id -u)"
  default_pgid="$(id -g)"

  ask "Server LAN IP"        "$default_ip"        SERVER_IP
  ask "Timezone (TZ format)" "$default_tz"        TZ
  ask "PUID (user id)"       "$default_puid"      PUID
  ask "PGID (group id)"      "$default_pgid"      PGID
  echo
  say "Storage paths (will be created if missing)"
  ask "Config / bind-mount root" "/opt/docker/data" CONFIG_PATH
  ask "Media library root"       "/mnt/media"       MEDIA_PATH
  ask "Photos library root"      "/mnt/photos"      PHOTOS_PATH
  ask "Documents library root"   "/mnt/documents"   DOCS_PATH

  say "Writing .env from .env.example"
  cp .env.example .env

  # sed -i in-place; use a unique delimiter so paths with slashes work
  python3 - "$SERVER_IP" "$TZ" "$PUID" "$PGID" "$CONFIG_PATH" "$MEDIA_PATH" "$PHOTOS_PATH" "$DOCS_PATH" <<'PY'
import sys, re, pathlib
ip, tz, puid, pgid, cfg, media, photos, docs = sys.argv[1:]
p = pathlib.Path(".env")
text = p.read_text()
subs = {
    "SERVER_IP":   ip,
    "TZ":          tz,
    "PUID":        puid,
    "PGID":        pgid,
    "CONFIG_PATH": cfg,
    "MEDIA_PATH":  media,
    "PHOTOS_PATH": photos,
    "DOCS_PATH":   docs,
}
for k, v in subs.items():
    text = re.sub(rf"(?m)^{k}=.*$", f"{k}={v}", text, count=1)
p.write_text(text)
PY

  say ".env written. Secrets are still blank — fill them in before starting"
  say "any stack that needs them (Vaultwarden, Paperless, Immich, VPN...)."
fi

# Load whatever is in .env now (whether we just wrote it or it pre-existed)
set -a
# shellcheck disable=SC1091
source .env
set +a

# ---- directories ------------------------------------------------------------
say "Creating directory layout"
mkdir -p "$CONFIG_PATH" "$CONFIG_PATH/homepage" \
         "$MEDIA_PATH" "$PHOTOS_PATH" "$DOCS_PATH"

# Seed homepage configs only if the target is empty (don't clobber user edits)
if [[ -z "$(ls -A "$CONFIG_PATH/homepage" 2>/dev/null)" ]]; then
  say "Seeding Homepage config to $CONFIG_PATH/homepage"
  cp -r dashboard/homepage/. "$CONFIG_PATH/homepage/"
else
  warn "Homepage config dir not empty — leaving it alone."
fi

# ---- docker network ---------------------------------------------------------
if ! docker network inspect home >/dev/null 2>&1; then
  say "Creating shared docker network 'home'"
  docker network create home >/dev/null
else
  say "Docker network 'home' already exists"
fi

# ---- optional: start Dockge -------------------------------------------------
echo
if ask_yn "Start Dockge now? (deploy every other stack from its UI afterwards)" Y; then
  say "Starting Dockge"
  ( cd dockge && docker compose --env-file ../.env up -d )
  say "Dockge running at http://${SERVER_IP}:${DOCKGE_PORT:-5001}"
fi

echo
say "Bootstrap complete."
cat <<EOF

Next steps:
  1. Open http://${SERVER_IP}:${DOCKGE_PORT:-5001} and create the Dockge admin.
  2. Deploy stacks in this order from the Dockge UI:
       vaultwarden → infrastructure → monitoring → dashboard
       → mediastack → household → records → cloud
  3. Fill any remaining secrets in .env (Vaultwarden, Paperless, Immich, VPN, etc.)
     then redeploy the affected stack(s).
  4. Create a Home Assistant webhook and set DIUN_NOTIF_WEBHOOK_URL in .env
     so update notifications land in your HA notification stream.
EOF
