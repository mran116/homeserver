#!/bin/sh
# =============================================================================
# update-port.sh — push gluetun's forwarded VPN port into qBittorrent.
#
# Run by gluetun as VPN_PORT_FORWARDING_UP_COMMAND whenever ProtonVPN hands out
# a (new, random) forwarded port. qBittorrent shares gluetun's network namespace
# (network_mode: service:gluetun), so its WebUI is reachable on 127.0.0.1.
#
# Needs (provided by gluetun's environment in docker-compose.yml):
#   QB_PORT, QB_USERNAME, QB_PASSWORD
#
# Notes learned the hard way:
#   - qBittorrent's API requires a matching Referer header (CSRF protection),
#     even on localhost — without it the request is silently rejected.
#   - localhost is NOT in qBittorrent's auth subnet whitelist, so we must log in
#     for a session cookie. Modern qBittorrent names it QBT_SID_<port>, not SID.
#   - gluetun's image has busybox wget (no curl), so we use wget -S and parse the
#     Set-Cookie header off stderr.
# =============================================================================
set -u

PORT="$(cat /tmp/gluetun/forwarded_port 2>/dev/null)" || true
case "${PORT:-}" in
  '' | *[!0-9]*) echo "[update-port] no valid forwarded port yet ('${PORT:-}') — skipping"; exit 0 ;;
esac

QB="http://127.0.0.1:${QB_PORT:-8080}"

# 1) Log in; capture the QBT_SID_* session cookie from the response headers.
login_hdrs="$(wget -S -O /dev/null \
  --header="Referer: ${QB}" \
  --post-data="username=${QB_USERNAME:-}&password=${QB_PASSWORD:-}" \
  "${QB}/api/v2/auth/login" 2>&1)"
cookie="$(printf '%s\n' "$login_hdrs" \
  | sed -n 's/.*[Ss]et-[Cc]ookie: *\(QBT_SID_[0-9]*=[^;]*\).*/\1/p' | head -n1)"

if [ -z "$cookie" ]; then
  echo "[update-port] WARN: qBittorrent login failed (no session cookie) — check QB_USERNAME/QB_PASSWORD"
  exit 1
fi

# 2) Set the listen port (Referer + cookie both required).
if wget -q -O /dev/null \
  --header="Referer: ${QB}" \
  --header="Cookie: ${cookie}" \
  --post-data="json={\"listen_port\":${PORT}}" \
  "${QB}/api/v2/app/setPreferences"; then
  echo "[update-port] qBittorrent listen_port set to ${PORT}"
else
  echo "[update-port] WARN: setPreferences failed for port ${PORT}"
  exit 1
fi
