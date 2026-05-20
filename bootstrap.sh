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

update_env() {
  # update_env KEY VALUE — set (or append) KEY=VALUE in .env, in place
  python3 - "$1" "$2" <<'PY'
import sys, re, pathlib
key, value = sys.argv[1], sys.argv[2]
p = pathlib.Path(".env")
text = p.read_text()
if re.search(rf"(?m)^{re.escape(key)}=", text):
    text = re.sub(rf"(?m)^{re.escape(key)}=.*$", f"{key}={value}", text, count=1)
else:
    text = text.rstrip() + f"\n{key}={value}\n"
p.write_text(text)
PY
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

  # ---- auto-generate machine secrets ----------------------------------------
  # Fill any blank password/token/secret line in .env with a random value.
  # User-facing credentials (admin passwords, API keys from third parties, VPN
  # keys) are left blank — they need a human decision or an external account.
  say "Generating random secrets for empty DB passwords / admin tokens"
  python3 - <<'PY'
import pathlib, re, secrets, string

# Lines we fill automatically when they are empty in .env.
# Anything not in this list (VPN keys, API keys from notifiarr/cloudflare/etc.,
# admin user passwords) is intentionally left for the human.
AUTO_FILL = {
    "NPM_DB_ROOT_PASSWORD",
    "NPM_DB_PASSWORD",
    "VAULTWARDEN_ADMIN_TOKEN",
    "PAPERLESS_DB_PASSWORD",
    "PAPERLESS_SECRET_KEY",
    "PAPERLESS_ADMIN_PASSWORD",
    "IMMICH_DB_PASSWORD",
    "GITEA_DB_PASSWORD",
}

def gen(length=36):
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))

p = pathlib.Path(".env")
out = []
filled = []
for line in p.read_text().splitlines():
    m = re.match(r"^([A-Z0-9_]+)=\s*$", line)
    if m and m.group(1) in AUTO_FILL:
        key = m.group(1)
        out.append(f"{key}={gen()}")
        filled.append(key)
    else:
        out.append(line)
p.write_text("\n".join(out) + "\n")
for k in filled:
    print(f"   + {k}")
PY

  say ".env written. The remaining blank fields need a human:"
  say "  - VPN (WIREGUARD_*, VPN_SERVER_COUNTRIES)"
  say "  - third-party API keys (DIUN webhook, TS_AUTHKEY, CLOUDFLARE_TUNNEL_TOKEN)"
  say "  - Homepage widget keys (HOMEPAGE_VAR_*_API_KEY) — gather after each app is up"
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

# ---- pre-seed *arr API keys (fresh installs only) ---------------------------
# Each *arr reads its API key from config.xml on first boot. We generate the
# key now and write BOTH .env and a stub config.xml so the app comes up already
# matching — no UI copy/paste. The internal <Port> is the image default (the
# right-hand side of the compose port mapping), NOT the host port from .env.
#
# Guarded twice: we skip if config.xml already exists (existing/migrated
# install) OR if the .env key is already set. Safe to run on top of a live
# setup — it will simply do nothing for apps you've already configured.
seed_arr() {
  local dir="$1" internal_port="$2" name="$3" envvar="$4"
  local cfg="$CONFIG_PATH/$dir/config.xml"
  [[ -f "$cfg" ]] && return 0
  local existing; existing="$(grep -E "^${envvar}=" .env | head -n1 | cut -d= -f2-)"
  [[ -n "$existing" ]] && return 0

  local key; key="$(openssl rand -hex 16)"
  mkdir -p "$CONFIG_PATH/$dir"
  cat > "$cfg" <<XML
<Config>
  <BindAddress>*</BindAddress>
  <Port>$internal_port</Port>
  <EnableSsl>False</EnableSsl>
  <LaunchBrowser>False</LaunchBrowser>
  <ApiKey>$key</ApiKey>
  <AuthenticationMethod>External</AuthenticationMethod>
  <AuthenticationRequired>DisabledForLocalAddresses</AuthenticationRequired>
  <Branch>main</Branch>
  <LogLevel>info</LogLevel>
  <UrlBase></UrlBase>
  <InstanceName>$name</InstanceName>
</Config>
XML
  chown "$PUID:$PGID" "$cfg" 2>/dev/null || true
  update_env "$envvar" "$key"
  printf '   + %s  (seeded %s)\n' "$envvar" "$cfg"
}

if command -v openssl >/dev/null; then
  say "Pre-seeding *arr API keys (skips any app that already has config.xml)"
  seed_arr sonarr   8989 Sonarr   SONARR_API_KEY
  seed_arr radarr   7878 Radarr   RADARR_API_KEY
  seed_arr lidarr   8686 Lidarr   LIDARR_API_KEY
  seed_arr whisparr 6969 Whisparr WHISPARR_API_KEY
  seed_arr prowlarr 9696 Prowlarr HOMEPAGE_VAR_PROWLARR_API_KEY
else
  warn "openssl not found — skipping *arr key pre-seed; use scripts/harvest-keys.sh later."
fi

# ---- link root .env into each stack folder ----------------------------------
# Compose only auto-loads .env from the stack's own directory, and Dockge runs
# `docker compose up` inside each stack folder with no --env-file flag. A
# symlink per folder means every stack reads this single root .env — no
# duplication, and no flag needed on reload (UI or CLI). Idempotent.
say "Linking root .env into each stack folder"
for compose in */docker-compose.yml; do
  d="$(dirname "$compose")"
  ln -sf ../.env "$d/.env"
done

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
  3. After the apps are up, gather the keys that must come from each UI
     (Jellyfin, Immich, Mealie, SABnzbd, NPM login, etc.):
       ./scripts/harvest-keys.sh
     The *arr keys (Sonarr/Radarr/Lidarr/Whisparr/Prowlarr) are already
     pre-seeded and live in .env.
  4. Create a Home Assistant webhook and set DIUN_NOTIF_WEBHOOK_URL in .env
     so update notifications land in your HA notification stream.
EOF
