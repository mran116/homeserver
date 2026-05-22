#!/usr/bin/env bash
# =============================================================================
# stack.sh — bulk operate on every stack in this repo
#
#   ./scripts/stack.sh up                 # start all stacks (deploy order)
#   ./scripts/stack.sh down               # stop all stacks (reverse order)
#   ./scripts/stack.sh restart            # down then up
#   ./scripts/stack.sh pull               # pull latest images for all stacks
#   ./scripts/stack.sh status             # docker compose ps for each
#   ./scripts/stack.sh up mediastack ...  # target specific stacks
#
# Uses the single root .env. Skips the commented-out devops stack. A failure
# in one stack is reported but doesn't abort the rest.
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"
ENV_FILE="$REPO_DIR/.env"

# Deploy order: brought UP first→last, taken DOWN last→first.
ORDER=(arcane vaultwarden infrastructure monitoring dashboard mediastack household records cloud)

c_b=$'\033[1m'; c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[0m'
say()  { printf '%s==>%s %s\n' "$c_b$c_g" "$c_r" "$*"; }
warn() { printf '%s!!%s %s\n'  "$c_b$c_y" "$c_r" "$*"; }

usage() { echo "Usage: $0 {up|down|restart|pull|status} [stack ...]"; exit 1; }

[[ -f "$ENV_FILE" ]] || { echo "No .env at $ENV_FILE — run ./bootstrap.sh first." >&2; exit 1; }
[[ $# -ge 1 ]] || usage
cmd="$1"; shift

if [[ $# -gt 0 ]]; then targets=("$@"); explicit=1; else targets=("${ORDER[@]}"); explicit=0; fi

dc() { docker compose -f "$1/docker-compose.yml" --env-file "$ENV_FILE" "${@:2}"; }

reversed() { local i; for ((i=${#ORDER[@]}-1; i>=0; i--)); do echo "${ORDER[i]}"; done; }

run_each() {
  local action="$1"; shift
  for s in "$@"; do
    [[ -f "$s/docker-compose.yml" ]] || { warn "skip $s (no docker-compose.yml)"; continue; }
    say "$action: $s"
    case "$action" in
      up)     dc "$s" up -d        || warn "$s failed" ;;
      down)   dc "$s" down         || warn "$s failed" ;;
      pull)   dc "$s" pull         || warn "$s failed" ;;
      status) dc "$s" ps           || true ;;
    esac
  done
}

case "$cmd" in
  up)     run_each up     "${targets[@]}" ;;
  pull)   run_each pull   "${targets[@]}" ;;
  status) run_each status "${targets[@]}" ;;
  down)
    if [[ $explicit -eq 0 ]]; then mapfile -t targets < <(reversed); fi
    run_each down "${targets[@]}"
    ;;
  restart)
    "$0" down "${targets[@]}"
    "$0" up   "${targets[@]}"
    ;;
  *) usage ;;
esac

say "Done."
