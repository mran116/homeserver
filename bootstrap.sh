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
# Two independent, both-safe steps:
#   1. Create .env from the template if it doesn't exist yet (asks system vars).
#   2. Fill ONLY blank machine secrets, never overwriting existing values.
# This handles a fresh box, a partial setup (e.g. mediastack done but other
# stacks not), and a full migration (nothing blank -> nothing changes) without
# needing to declare a "mode".
if [[ -f .env ]]; then
  say "Existing .env found — keeping it. System values left as-is."
  say "(Only blank secrets will be offered for generation below.)"
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

fi

# ---- fill blank machine secrets (safe: never overwrites) --------------------
# Runs in every case. Only lines that are still blank get a random value, so a
# partial setup (e.g. mediastack already configured) keeps everything you've set
# and only the not-yet-used stacks get fresh secrets. A fully configured box has
# no blanks, so nothing changes.
#
# User-facing / external credentials (VPN keys, third-party API keys, admin
# user passwords) are deliberately NOT in this list — they need a human or an
# external account.
SECRET_KEYS='NPM_DB_ROOT_PASSWORD NPM_DB_PASSWORD VAULTWARDEN_ADMIN_TOKEN PAPERLESS_DB_PASSWORD PAPERLESS_SECRET_KEY PAPERLESS_ADMIN_PASSWORD IMMICH_DB_PASSWORD GITEA_DB_PASSWORD'

count_blank_secrets() {
  python3 - "$SECRET_KEYS" <<'PY'
import sys, re, pathlib
keys = sys.argv[1].split()
text = pathlib.Path(".env").read_text()
print(sum(1 for k in keys if re.search(rf"(?m)^{k}=\s*(#.*)?$", text)))
PY
}

blanks="$(count_blank_secrets)"
if [[ "$blanks" -gt 0 ]]; then
  echo
  say "$blanks machine secret(s) are still blank (DB passwords / admin tokens)."
  echo "  Generating fills ONLY the blank ones — anything already set is left alone,"
  echo "  so this is safe on a partial or existing setup."
  warn "If your real secrets live OUTSIDE this .env (e.g. still in Portainer), paste"
  warn "them in first — new random values would not match your existing databases."
  if ask_yn "Generate the $blanks blank secret(s) now?" Y; then
    python3 - "$SECRET_KEYS" <<'PY'
import sys, os, pathlib, re, secrets, string
keys = set(sys.argv[1].split())

# DB-password keys whose value MUST match an already-created database. A
# Postgres/MariaDB container only honours its password env var on first init
# (empty data dir); once the database exists it keeps the original password.
# So if the data dir already exists we must NOT invent a new password — that
# would orphan the DB and break the app. Leave it blank for the human instead.
DB_DIRS = {
    "NPM_DB_ROOT_PASSWORD":  "npm/db",
    "NPM_DB_PASSWORD":       "npm/db",
    "IMMICH_DB_PASSWORD":    "immich/db",
    "PAPERLESS_DB_PASSWORD": "paperless/db",
    "GITEA_DB_PASSWORD":     "gitea/db",
}
text = pathlib.Path(".env").read_text()
m = re.search(r"(?m)^CONFIG_PATH=(.*)$", text)
config_path = (m.group(1).strip() if m else "") or "/opt/docker/data"

def db_exists(sub):
    d = os.path.join(config_path, sub)
    return os.path.isdir(d) and any(os.scandir(d))

gen = lambda n=36: "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(n))
out, filled, guarded = [], [], []
for line in text.splitlines():
    mm = re.match(r"^([A-Z0-9_]+)=\s*(#.*)?$", line)
    if mm and mm.group(1) in keys:
        k = mm.group(1)
        if k in DB_DIRS and db_exists(DB_DIRS[k]):
            out.append(line); guarded.append(k)        # existing DB -> leave blank
        else:
            out.append(f"{k}={gen()}"); filled.append(k)
    else:
        out.append(line)
pathlib.Path(".env").write_text("\n".join(out) + "\n")
for k in filled:
    print(f"   + {k}")
for k in guarded:
    print(f"   ! {k}  EXISTING DATABASE FOUND ({DB_DIRS[k]}) — left blank.")
    print(f"     Paste the password this database was created with, or the app won't connect.")
PY
  else
    say "Skipped — set those secrets in .env yourself before starting those stacks."
  fi
else
  say "No blank machine secrets — nothing to generate."
fi

say "Reminder: VPN keys, third-party tokens (Diun/Tailscale/Cloudflare) and"
say "Homepage widget keys still need filling — run ./scripts/harvest-keys.sh later."

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

# ---- pre-seed *arr API keys (prompted; per-app guarded) ---------------------
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

if ! command -v openssl >/dev/null; then
  warn "openssl not found — skipping *arr key pre-seed; use scripts/harvest-keys.sh later."
else
  echo
  say "Optional: pre-seed *arr API keys"
  echo "  Generates each *arr's API key now and writes a config.xml so Sonarr/Radarr/"
  echo "  Lidarr/Whisparr/Prowlarr boot ready for Recyclarr/Unpackerr/Homepage with no"
  echo "  manual key copying. NOTE: the stub config sets local access with NO login"
  echo "  (AuthenticationMethod=External) — fine on a trusted LAN, and you can switch"
  echo "  to Forms/password auth in each app afterwards. Skips any app already set up."
  if ask_yn "Pre-seed *arr API keys?" Y; then
    seed_arr sonarr   8989 Sonarr   SONARR_API_KEY
    seed_arr radarr   7878 Radarr   RADARR_API_KEY
    seed_arr lidarr   8686 Lidarr   LIDARR_API_KEY
    seed_arr whisparr 6969 Whisparr WHISPARR_API_KEY
    seed_arr prowlarr 9696 Prowlarr HOMEPAGE_VAR_PROWLARR_API_KEY
  else
    say "Skipped — set up each *arr in its UI, then run scripts/harvest-keys.sh."
  fi
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
