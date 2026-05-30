#!/usr/bin/env bash
# =============================================================================
# install-crowdsec-bouncer.sh — install + wire the HOST firewall bouncer that
# ENFORCES CrowdSec decisions by blocking IPs in iptables.
#
# The CrowdSec engine runs as a container (COMPOSE_PROFILES=crowdsec); the
# firewall bouncer is an OS package (CrowdSec ships no official container for it),
# so it lives on the host. This script: adds the CrowdSec apt repo, installs
# crowdsec-firewall-bouncer-iptables, and points it at the local engine
# (127.0.0.1:8080) with the shared key, blocking in the INPUT + DOCKER-USER
# chains (DOCKER-USER is what actually filters traffic to your containers).
#
# Run as root / with sudo, AFTER the crowdsec engine container is up.
# Debian/Ubuntu only (apt). Flags: --dry-run, --yes.
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
cd "$REPO_DIR" || exit 1
parse_common_flags "$@"
require_env || exit 0
load_env

command -v apt-get >/dev/null || die "Debian/Ubuntu (apt) only. On other distros install crowdsec-firewall-bouncer-iptables from CrowdSec's repo, then set api_url/api_key/iptables_chains yourself (see docs/crowdsec.md)."
KEY="${CROWDSEC_BOUNCER_KEY:-}"
[[ -n "$KEY" ]] || die "CROWDSEC_BOUNCER_KEY is blank — run 'hs secrets', then redeploy the crowdsec engine so it registers the key, then re-run this."

# Engine reachable on the local API? Probe the CONNECTION, not the HTTP status —
# the LAPI may answer /health with 401/404 depending on version, so `curl -f`
# (fail on non-2xx) would wrongly report a healthy engine as down. Without -f,
# curl exits 0 if it got ANY response (i.e. the port is listening).
if ! curl -s -m 5 -o /dev/null "http://127.0.0.1:8080/" 2>/dev/null; then
  warn "CrowdSec engine not answering on 127.0.0.1:8080 — start it first:"
  warn "  add 'crowdsec' to COMPOSE_PROFILES, then: hs up infrastructure"
  die "engine not reachable"
fi

CONF=/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml
plan "add CrowdSec apt repo + install crowdsec-firewall-bouncer-iptables"
plan "write $CONF (api_url=127.0.0.1:8080, mode=iptables, chains: INPUT + DOCKER-USER)"
plan "restart + enable the crowdsec-firewall-bouncer service"
show_plan || exit 0
gate || exit 0

# 1. Repo (idempotent — packagecloud script is safe to re-run).
if ! apt-cache policy crowdsec-firewall-bouncer-iptables 2>/dev/null | grep -q Candidate; then
  say "Adding CrowdSec package repo"
  curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | sudo bash
fi

# 2. Install.
say "Installing crowdsec-firewall-bouncer-iptables"
sudo apt-get install -y crowdsec-firewall-bouncer-iptables

# 3. Configure → point at the containerized engine, block in DOCKER-USER too.
say "Writing $CONF"
sudo tee "$CONF" >/dev/null <<EOF
mode: iptables
update_frequency: 10s
log_mode: file
log_dir: /var/log/
log_level: info
api_url: http://127.0.0.1:8080
api_key: ${KEY}
# DOCKER-USER is the chain Docker filters container traffic through — without it,
# bans wouldn't apply to your published container ports.
iptables_chains:
  - INPUT
  - DOCKER-USER
EOF
sudo chmod 600 "$CONF"   # contains the API key

# 4. Start.
sudo systemctl enable --now crowdsec-firewall-bouncer 2>/dev/null || true
sudo systemctl restart crowdsec-firewall-bouncer
say "Done. Verify with:  sudo cscli bouncers list   (run inside the engine: docker exec crowdsec cscli bouncers list)"
say "Active bans:        docker exec crowdsec cscli decisions list"
