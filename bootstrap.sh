#!/usr/bin/env bash
# =============================================================================
# Homeserver bootstrap — FIRST-RUN host setup (orchestrator).
#
# Run this ONCE when first setting up this repo on a host. It runs each step in
# scripts/ in dependency order; every step PREVIEWS what it will do, then asks
# to apply. Safe to re-run (idempotent), but on a LIVE stack you usually don't
# need it — see "When to run what" in scripts/README.md. In short:
#   ./scripts/update.sh   pull latest + redeploy (routine updates)
#   ./scripts/doctor.sh   read-only health check (tells you which step to run)
#   ./scripts/<step>.sh   a single targeted step (env-sync, link-env, ...)
#
# Flags:
#   --dry-run   preview every step, change nothing
#   --yes       apply every step without prompting (non-interactive)
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"
# shellcheck source=scripts/lib/common.sh
source "$REPO_DIR/scripts/lib/common.sh"

usage() { sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
parse_common_flags "$@"

# Flags to forward to each step.
PASS=()
[[ $DRY_RUN -eq 1 ]]    && PASS+=(--dry-run)
[[ $ASSUME_YES -eq 1 ]] && PASS+=(--yes)

say "Checking prerequisites"
require_docker

run() {
  echo
  say "── ${1%.sh}"
  "$REPO_DIR/scripts/$1" "${PASS[@]}"
}

run env-init.sh
run env-sync.sh
run gen-secrets.sh
run make-dirs.sh
run link-env.sh
run create-network.sh
run schedule-maintenance.sh

say "Reminder: VPN keys + third-party tokens (Diun/Tailscale/Cloudflare) and"
say "Homepage widget keys still need filling — run ./scripts/harvest-keys.sh later."

# ---- optional: start Arcane (final hand-off) --------------------------------
echo
if [[ $DRY_RUN -eq 1 ]]; then
  say "Would optionally start Arcane (skipped in --dry-run)."
else
  load_env
  if [[ $ASSUME_YES -eq 1 ]] || ask_yn "Start Arcane now? (deploy every other stack from its UI afterwards)" Y; then
    say "Starting Arcane"
    ( cd arcane && docker compose --env-file ../.env up -d )
    say "Arcane running at http://${SERVER_IP}:${ARCANE_PORT:-3552}"
  fi
fi

echo
say "Bootstrap complete."
[[ $DRY_RUN -eq 1 ]] && exit 0
cat <<EOF

Next steps:
  1. Open http://${SERVER_IP:-<server-ip>}:${ARCANE_PORT:-3552} and create the Arcane
     admin (first-run login: arcane / arcane-admin — change it immediately).
  2. UPGRADING an existing host? AdGuard and ntfy moved INTO the infrastructure
     and monitoring stacks. Remove the old standalone containers first, or the
     redeploy fails on a name conflict (data is kept in ${CONFIG_PATH:-\$CONFIG_PATH}/adguard
     and .../ntfy):
       docker rm -f adguard ntfy
     and delete the old "adguard" / "ntfy" stacks in Arcane. (Fresh installs: skip.)
  3. Deploy stacks in this order from the Arcane UI:
       vaultwarden → infrastructure → monitoring → dashboard → mediastack
       → household → records → knowledge → syncthing → cloud
  4. After the apps are up, run the key harvester:
       ./scripts/harvest-keys.sh
  5. Install the ntfy app and subscribe to "diun-updates" for image-update alerts.
EOF
