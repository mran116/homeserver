#!/usr/bin/env bash
# =============================================================================
# harvest-keys.sh
#
# Walk through every external API key / credential the stack uses and prompt
# for each one, with a direct link to the page where you find it. Writes
# values straight into .env so you never edit it by hand.
#
# Re-run any time. Existing values are shown and kept by default; press Enter
# to skip, type a new value to replace, or "-" to clear.
#
# Pass --force to re-prompt for keys that already have a value.
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

[[ -f .env ]] || { echo "No .env found. Run ./bootstrap.sh first." >&2; exit 1; }

FORCE=0; SYNC=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --sync)  SYNC=1 ;;   # non-interactive: detect *arr keys, redeploy consumers on change
  esac
done

# Keep the cron log bounded. The scheduled job redirects to key-sync.log; cap it
# at ~1 MB by truncating IN PLACE (same inode) so cron's open append-fd keeps
# working — safe, unlike a tail-to-temp+mv which would orphan that fd. Truncate
# before producing any output so this run's lines are preserved.
LOG="$REPO_DIR/key-sync.log"
if [[ $SYNC -eq 1 && -f "$LOG" && "$(wc -c < "$LOG" 2>/dev/null || echo 0)" -gt 1048576 ]]; then
  : > "$LOG"
fi

# shellcheck disable=SC1091
set -a; source .env; set +a
: "${SERVER_IP:?SERVER_IP missing from .env}"

c_b=$'\033[1m'; c_d=$'\033[2m'; c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[0m'

# -----------------------------------------------------------------------------
# Keys we harvest, in the order a user would naturally hit them.
# Format (pipe-separated, # for comments):
#   ENV_VAR | service URL on this server | UI path to find the value
# The URLs are display-only hints, so relax `set -u` while expanding them — a
# missing port just yields a blank URL rather than aborting (matters for --sync,
# which doesn't need ports at all).
# -----------------------------------------------------------------------------
set +u
KEYS=$(cat <<EOF
# ---- *arr stack (Settings → General → Security → API Key) ----
SONARR_API_KEY           | http://${SERVER_IP}:${SONARR_PORT}     | Settings → General → Security
RADARR_API_KEY           | http://${SERVER_IP}:${RADARR_PORT}     | Settings → General → Security
LIDARR_API_KEY           | http://${SERVER_IP}:${LIDARR_PORT}     | Settings → General → Security
WHISPARR_API_KEY         | http://${SERVER_IP}:${WHISPARR_PORT}   | Settings → General → Security
PROWLARR_API_KEY         | http://${SERVER_IP}:${PROWLARR_PORT}   | Settings → General → Security
BAZARR_API_KEY           | http://${SERVER_IP}:${BAZARR_PORT}     | Settings → General → Security
SABNZBD_API_KEY          | http://${SERVER_IP}:${SABNZBD_PORT}    | Config → General → Security

# ---- Media servers ----
JELLYFIN_API_KEY         | http://${SERVER_IP}:${JELLYFIN_PORT}   | Dashboard → API Keys → "+" (any name)
SEERR_API_KEY            | http://${SERVER_IP}:${SEERR_PORT}      | Settings → General → API Key
KAVITA_USER              | http://${SERVER_IP}:${KAVITA_PORT}     | Your Kavita username
KAVITA_PASSWORD          | http://${SERVER_IP}:${KAVITA_PORT}     | Your Kavita password

# ---- Navidrome (token + salt are derived; see https://gethomepage.dev/widgets/services/navidrome/) ----
NAVIDROME_USER           | http://${SERVER_IP}:${NAVIDROME_PORT}  | Your Navidrome username
NAVIDROME_TOKEN          | http://${SERVER_IP}:${NAVIDROME_PORT}  | md5(password + salt)  — see Homepage docs
NAVIDROME_SALT           | http://${SERVER_IP}:${NAVIDROME_PORT}  | Random salt you pick (any string)

# ---- Downloader credentials ----
APP_USERNAME             | http://${SERVER_IP}:${BITTORRENT_PORT} | qBittorrent username (default: admin)
APP_PASSWORD             | http://${SERVER_IP}:${BITTORRENT_PORT} | qBittorrent password (default: adminadmin — change in WebUI)

# ---- Household ----
MEALIE_API_KEY           | http://${SERVER_IP}:${MEALIE_PORT}     | User profile (top-right) → API Tokens → Generate

# ---- Records (admin user/pass are set at install; press Enter to keep) ----
PAPERLESS_ADMIN_USER     | http://${SERVER_IP}:${PAPERLESS_PORT}  | Set in .env at install time (default: admin)
PAPERLESS_ADMIN_PASSWORD | http://${SERVER_IP}:${PAPERLESS_PORT}  | Set in .env at install time

# ---- Cloud ----
IMMICH_API_KEY           | http://${SERVER_IP}:${IMMICH_PORT}     | Account Settings → API Keys → New API Key

# ---- Infrastructure ----
NPM_EMAIL                | http://${SERVER_IP}:${NPM_PORT}        | Your NPM login email
NPM_PASSWORD             | http://${SERVER_IP}:${NPM_PORT}        | Your NPM login password

# ---- Notifications / external ----
DIUN_NOTIF_WEBHOOK_URL               | (Home Assistant)                          | HA → Settings → Automations → New → Webhook trigger
TS_AUTHKEY                           | https://login.tailscale.com/admin/settings/keys | Generate a reusable auth key
CLOUDFLARE_TUNNEL_TOKEN              | https://one.dash.cloudflare.com           | Zero Trust → Networks → Tunnels → your tunnel → token
EOF
)
set -u

# -----------------------------------------------------------------------------
update_env() {
  # update_env KEY VALUE  — replaces the first KEY=… line in .env in-place
  local key="$1" value="$2"
  python3 - "$key" "$value" <<'PY'
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

current_value() {
  grep -E "^${1}=" .env | head -n1 | cut -d= -f2-
}

# -----------------------------------------------------------------------------
# Auto-detect *arr API keys from the config.xml each app generates on first
# boot. We only READ the file — never write app config — so this can't corrupt
# an app. config.xml is identical across Sonarr/Radarr/Lidarr/Whisparr/Prowlarr.
# Detected keys are written to .env, so the manual loop below then shows them as
# already set.
detect_arr() {
  local dir="$1" envvar="$2"
  local cfg="${CONFIG_PATH:-/opt/docker/data}/$dir/config.xml"
  [[ -f "$cfg" ]] || { printf '  %s·%s %-18s no config.xml yet (start the app first)\n' "$c_d" "$c_r" "$dir"; return 0; }
  local key
  key="$(grep -oE '<ApiKey>[^<]+</ApiKey>' "$cfg" | sed -E 's#</?ApiKey>##g' | head -n1)"
  [[ -n "$key" ]] || { printf '  %s·%s %-18s config.xml has no ApiKey yet\n' "$c_d" "$c_r" "$dir"; return 0; }
  if [[ "$(current_value "$envvar")" == "$key" ]]; then
    [[ $SYNC -eq 0 ]] && printf '  %s✓%s %-18s already in .env\n' "$c_g" "$c_r" "$envvar"
  else
    update_env "$envvar" "$key"
    CHANGED=1
    printf '  %s+%s %-18s detected from %s/config.xml\n' "$c_g" "$c_r" "$envvar" "$dir"
  fi
}

CHANGED=0
printf '%s\n' "${c_b}Auto-detecting *arr API keys from config.xml${c_r}"
detect_arr sonarr   SONARR_API_KEY
detect_arr radarr   RADARR_API_KEY
detect_arr lidarr   LIDARR_API_KEY
detect_arr whisparr WHISPARR_API_KEY
detect_arr prowlarr PROWLARR_API_KEY
echo

# --sync: non-interactive. If a key changed, recreate only the consumer services
# so they pick up the new value, then exit. Used by cron / a scheduler.
if [[ $SYNC -eq 1 ]]; then
  if [[ $CHANGED -eq 1 ]]; then
    printf '%s==>%s Key(s) changed — recreating consumers (unpackerr, recyclarr, homepage)\n' "$c_b$c_g" "$c_r"
    ( cd "$REPO_DIR/mediastack" && docker compose up -d unpackerr recyclarr ) || true
    ( cd "$REPO_DIR/dashboard"  && docker compose up -d homepage )           || true
  else
    printf '%s==>%s No key changes.\n' "$c_b$c_g" "$c_r"
  fi
  exit 0
fi

printf '%s\n' "${c_b}Homestack key harvester${c_r}"
printf '%s\n\n' "${c_d}Press Enter to keep current value, type new value to replace, '-' to clear.${c_r}"

while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  IFS='|' read -r key url where <<<"$line"
  key="$(echo "$key" | xargs)"
  url="$(echo "$url" | xargs)"
  where="$(echo "$where" | xargs)"

  cur="$(current_value "$key" || true)"

  if [[ -n "$cur" && $FORCE -eq 0 ]]; then
    printf '  %s✓%s %-40s %s(set)%s\n' "$c_g" "$c_r" "$key" "$c_d" "$c_r"
    continue
  fi

  printf '\n%s%s%s\n' "$c_b" "$key" "$c_r"
  printf '  %sOpen:%s   %s\n'   "$c_y" "$c_r" "$url"
  printf '  %sLook:%s   %s\n'   "$c_y" "$c_r" "$where"
  if [[ -n "$cur" ]]; then
    printf '  %sCurrent:%s %s\n' "$c_d" "$c_r" "$cur"
  fi
  read -r -p "  > " new || true

  case "$new" in
    "")  ;;                                   # keep
    "-") update_env "$key" "" ;;               # clear
    *)   update_env "$key" "$new" ;;           # replace
  esac
done <<<"$KEYS"

echo
printf '%sDone.%s Re-run with %s--force%s to revisit keys that already have a value.\n' \
  "$c_g" "$c_r" "$c_b" "$c_r"
