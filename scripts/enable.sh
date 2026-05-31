#!/usr/bin/env bash
# =============================================================================
# enable.sh — guided enable/disable of an optional feature.
#
# Collapses the multi-step "edit COMPOSE_PROFILES + set .env vars + gen-secrets +
# redeploy + post-step + figure out how to verify" dance into one command:
#   hs enable  <feature>
#   hs disable <feature>
#   hs enable            (no arg → list the features)
#
# It adds/removes the feature's compose profile, prompts for the host-specific
# values it needs (skipping any you've already set), fills machine secrets via
# gen-secrets, redeploys the affected stack, runs any post-step, and prints the
# verify command. Flags: --dry-run, --yes.
#
# Features: caddy, crowdsec, metrics, karakeep, vpn, tunnel, ddns, tdarr,
#           backup, proxy   (run `hs enable` with no arg for descriptions)
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
cd "$REPO_DIR" || exit 1
parse_common_flags "$@"

# positional args (flags already consumed by parse_common_flags)
args=(); for a in "$@"; do [[ "$a" == -* ]] || args+=("$a"); done
action="${args[0]:-}"; feature="${args[1]:-}"

list_features() {
  cat <<'EOF'
Optional features (hs enable <name> / hs disable <name>):

  adguard    AdGuard Home DNS server (only if your router can't run DNS)
  caddy      Caddy reverse proxy + automatic HTTPS
  crowdsec   CrowdSec intrusion detection/prevention (+ host firewall bouncer)
  metrics    Beszel host/container metrics dashboard
  karakeep   Bookmarks / read-later with full-text search
  vpn        Tailscale private mesh VPN (remote access, subnet router)
  tunnel     Cloudflare Tunnel (public access, no open ports)
  ddns       Dynamic-DNS updater (keeps a domain's A record on your WAN IP)
  tdarr      Tdarr library transcoder (HEVC/x265 to save space)
  backup     Borgmatic encrypted offsite backups
  proxy      Gluetun HTTP proxy through the VPN (for a private browser)
EOF
}

[[ -z "$action" || "$action" == "list" ]] && { list_features; exit 0; }
[[ "$action" == "enable" || "$action" == "disable" ]] || die "usage: hs {enable|disable} <feature>  (hs enable lists them)"
[[ -n "$feature" ]] || { list_features; die "pick a feature"; }
require_env || exit 0
require_docker

# ---- per-feature metadata ---------------------------------------------------
# Sets: PROFILE (compose profile, empty for env-toggle features), STACK (to
# redeploy), and defines prompt_vars()/post_step()/verify() for this feature.
PROFILE=""; STACK=""
prompt_vars() { :; }   # default: nothing to prompt
post_step()   { :; }   # default: no post-step
verify()      { :; }   # default: no verify hint

# prompt for a host-specific value only if it's currently blank
need() {  # need KEY "Prompt" ["default"]
  local key="$1" prompt="$2" default="${3:-}" cur val
  cur="$(current_value "$key")"
  [[ -n "$cur" ]] && { say "$key already set — keeping current value."; return 0; }
  [[ $DRY_RUN -eq 1 ]] && { plan "prompt for $key"; return 0; }
  ask "$prompt" "$default" val
  if [[ -n "$val" ]]; then update_env "$key" "$val"; else warn "$key left blank — set it later with: hs config $key <value>"; fi
}

case "$feature" in
  adguard)
    PROFILE=adguard; STACK=infrastructure
    post_step()   { warn "If systemd-resolved holds :53, free it: sudo systemctl disable --now systemd-resolved (then set /etc/resolv.conf to a static nameserver)."; }
    verify()      { say "Open AdGuard on :\${ADGUARD_PORT} → run the wizard (admin UI :3000, DNS on 0.0.0.0:53) → point your router/devices' DNS at \$SERVER_IP."; }
    ;;
  caddy)
    PROFILE=caddy; STACK=infrastructure
    prompt_vars() { need DOMAIN "Your domain (services at *.DOMAIN)" "example.com"; need CLOUDFLARE_DNS_API_TOKEN "Cloudflare DNS API token (Zone→DNS→Edit)"; need ACME_EMAIL "Email for Let's Encrypt notices"; }
    verify()      { say "Add the two caddy: labels to a service, then check https://<service>.\$DOMAIN. Guide: docs/caddy.md"; }
    ;;
  crowdsec)
    PROFILE=crowdsec; STACK=infrastructure
    prompt_vars() { need CROWDSEC_ENROLL_KEY "Optional CrowdSec console enroll key (blank = local-only)"; }
    post_step()   { if [[ $ASSUME_YES -eq 1 ]] || ask_yn "Install the host firewall bouncer now (enforces bans)?" Y; then "$SCRIPT_DIR/install-crowdsec-bouncer.sh" ${ASSUME_YES:+--yes}; else warn "Run 'hs crowdsec-bouncer' later to enable enforcement."; fi; }
    verify()      { say "Verify: docker exec crowdsec cscli bouncers list   (and: cscli metrics). Guide: docs/crowdsec.md"; }
    ;;
  metrics)
    PROFILE=metrics; STACK=monitoring
    verify()      { say "Open the Beszel hub on :\${BESZEL_PORT:-8090} → Add System (host.docker.internal:45876) → paste its key into BESZEL_KEY (hs config BESZEL_KEY <key>) → re-run 'hs up monitoring'."; }
    ;;
  karakeep)
    PROFILE=karakeep; STACK=knowledge
    verify()      { say "Open Karakeep on :\${KARAKEEP_PORT:-9934}, create your account, save a link — it should archive + index it."; }
    ;;
  vpn)
    PROFILE=vpn; STACK=infrastructure
    prompt_vars() { need TS_AUTHKEY "Tailscale auth key (reusable, login.tailscale.com)"; need TAILSCALE_SUBNET "Your LAN subnet to advertise (e.g. 172.25.1.0/24)"; }
    post_step()   { warn "In the Tailscale admin console: APPROVE the subnet route + disable key expiry + enable MagicDNS."; }
    verify()      { say "From an off-LAN device, reach the server's LAN IP over Tailscale. Guide: docs/tailscale.md"; }
    ;;
  tunnel)
    PROFILE=tunnel; STACK=infrastructure
    prompt_vars() { need CLOUDFLARE_TUNNEL_TOKEN "Cloudflare Tunnel token (Zero Trust→Networks→Tunnels)"; }
    post_step()   { warn "Add public-hostname routes in the Cloudflare dashboard (see infrastructure/docker-compose.yml)."; }
    ;;
  ddns)
    PROFILE=ddns; STACK=infrastructure
    prompt_vars() { need CLOUDFLARE_DNS_API_TOKEN "Cloudflare DNS API token"; need DDNS_DOMAINS "Domain(s) to keep on your WAN IP (e.g. jellyfin.example.com)"; }
    ;;
  tdarr)
    PROFILE=tdarr; STACK=mediastack
    post_step()   { warn "HW transcode: set RENDER_GID + enable the tdarr block in mediastack/docker-compose.override.yml."; }
    verify()      { say "Open Tdarr on :\${TDARR_PORT:-8265}, add a library + the HandBrake flow. ⚠ It REPLACES originals — see docs/tdarr.md"; }
    ;;
  backup)
    PROFILE=backup; STACK=infrastructure
    prompt_vars() { need BORG_PASSPHRASE "Borg passphrase (DO NOT lose it — needed to restore)"; }
    post_step()   { warn "Fill your B2/repo creds in infrastructure/borgmatic/config (see the compose comment)."; }
    ;;
  proxy)
    # env-toggle feature (not a compose profile)
    PROFILE=""; STACK=mediastack
    prompt_vars() {
      need GLUETUN_HTTPPROXY_USER "Proxy username (so the LAN proxy isn't open)" "proxy"
      need GLUETUN_HTTPPROXY_PASSWORD "Proxy password"
    }
    verify()      { say "Point a browser at \$SERVER_IP:\${GLUETUN_HTTPPROXY_PORT:-8888} (user/pass above) — its traffic exits via the VPN."; }
    ;;
  *) die "unknown feature '$feature' — run 'hs enable' to list them." ;;
esac

# ---- compose-profile helpers ------------------------------------------------
has_profile() { case ",$(current_value COMPOSE_PROFILES),"  in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
add_profile() {
  local cur; cur="$(current_value COMPOSE_PROFILES)"
  [[ -z "$cur" ]] && update_env COMPOSE_PROFILES "$1" || update_env COMPOSE_PROFILES "$cur,$1"
}
remove_profile() {
  local new; new="$(current_value COMPOSE_PROFILES | tr ',' '\n' | grep -vxF "$1" | paste -sd, -)"
  update_env COMPOSE_PROFILES "$new"
}

# ---- plan -------------------------------------------------------------------
if [[ "$action" == "enable" ]]; then
  if [[ -n "$PROFILE" ]]; then
    has_profile "$PROFILE" && say "Profile '$PROFILE' already enabled — will reconcile vars + redeploy." || plan "add '$PROFILE' to COMPOSE_PROFILES"
  else
    [[ "$feature" == proxy ]] && plan "set GLUETUN_HTTPPROXY=on"
  fi
  plan "prompt for any unset values this feature needs"
  plan "fill machine secrets (gen-secrets, DB-safe)"
  plan "redeploy the '$STACK' stack"
else  # disable
  [[ -n "$PROFILE" ]] && plan "remove '$PROFILE' from COMPOSE_PROFILES" || plan "set GLUETUN_HTTPPROXY=off"
  plan "redeploy the '$STACK' stack (the feature's containers stop)"
fi
show_plan || exit 0
gate || exit 0

backup_env

# ---- apply ------------------------------------------------------------------
if [[ "$action" == "enable" ]]; then
  [[ -n "$PROFILE" ]] && { has_profile "$PROFILE" || add_profile "$PROFILE"; }
  [[ "$feature" == proxy ]] && update_env GLUETUN_HTTPPROXY on
  prompt_vars
  "$SCRIPT_DIR/gen-secrets.sh" --yes >/dev/null 2>&1 || true   # fill any new machine secrets
  say "Redeploying $STACK…"
  "$SCRIPT_DIR/stack.sh" up "$STACK"
  post_step
  verify
  say "Done — '$feature' enabled."
else
  [[ -n "$PROFILE" ]] && remove_profile "$PROFILE"
  [[ "$feature" == proxy ]] && update_env GLUETUN_HTTPPROXY off
  say "Redeploying $STACK (--remove-orphans drops the now-disabled containers)…"
  STACK_UP_ARGS=--remove-orphans "$SCRIPT_DIR/stack.sh" up "$STACK"
  say "Done — '$feature' disabled."
fi
