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
# shellcheck source=scripts/lib/common.sh
source "$REPO_DIR/scripts/lib/common.sh"

# Deploy order: brought UP first→last, taken DOWN last→first.
ORDER=(arcane vaultwarden infrastructure monitoring dashboard mediastack household records knowledge syncthing cloud)

usage() { echo "Usage: $0 {up|down|restart|pull|status} [stack ...]"; exit 1; }

# Interactive menu when run with no arguments.
menu() {
  # Display goes to stderr so only the chosen keyword is captured via $(menu).
  {
    echo "${c_bold}stack.sh — pick an action:${c_reset}"
    echo "  1) up       start all stacks"
    echo "  2) down     stop all stacks"
    echo "  3) restart  down then up"
    echo "  4) pull     update images"
    echo "  5) status   ps for each"
    echo "  q) quit"
  } >&2
  local choice
  read -r -p "Choice [5]: " choice   # read's prompt already goes to stderr
  case "${choice:-5}" in
    1) echo up ;; 2) echo down ;; 3) echo restart ;; 4) echo pull ;; 5) echo status ;;
    q|Q) echo "" ;;
    *) echo "INVALID" ;;
  esac
}

[[ -f "$ENV_FILE" ]] || { echo "No .env at $ENV_FILE — run ./bootstrap.sh first." >&2; exit 1; }

if [[ $# -ge 1 ]]; then
  cmd="$1"; shift
  if [[ $# -gt 0 ]]; then targets=("$@"); explicit=1; else targets=("${ORDER[@]}"); explicit=0; fi
else
  cmd="$(menu)"
  [[ -z "$cmd" ]] && { echo "Cancelled."; exit 0; }
  [[ "$cmd" == "INVALID" ]] && { echo "Invalid choice."; exit 1; }
  targets=("${ORDER[@]}"); explicit=0
fi

dc() { docker compose -f "$1/docker-compose.yml" --env-file "$ENV_FILE" "${@:2}"; }

reversed() { local i; for ((i=${#ORDER[@]}-1; i>=0; i--)); do echo "${ORDER[i]}"; done; }

run_each() {
  local action="$1"; shift
  for s in "$@"; do
    [[ -f "$s/docker-compose.yml" ]] || { warn "skip $s (no docker-compose.yml)"; continue; }
    say "$action: $s"
    case "$action" in
      up)     dc "$s" up -d ${STACK_UP_ARGS:-} || warn "$s failed" ;;
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
