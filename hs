#!/usr/bin/env bash
# =============================================================================
# hs — the homeserver command. One entrypoint for everything in this repo.
#
# Works from ANY directory (it resolves its own location), so you never cd into
# the repo. Put it on your PATH once with `hs install`, then just type `hs ...`.
#
# Every subcommand forwards your flags to the underlying script, which share one
# flag set:  -n/--dry-run (preview)   -y/--yes (no prompt)   -h/--help (usage).
# So `hs update -n` previews, `hs env tidy -h` shows that command's help, etc.
# =============================================================================
set -euo pipefail

# Resolve this script's REAL directory, following symlinks, so `hs` works both
# from the repo and when symlinked onto PATH by `hs install`.
src="${BASH_SOURCE[0]}"
while [ -L "$src" ]; do
  dir="$(cd -P "$(dirname "$src")" && pwd)"; src="$(readlink "$src")"
  [[ "$src" != /* ]] && src="$dir/$src"
done
ROOT="$(cd -P "$(dirname "$src")" && pwd)"
S="$ROOT/scripts"

run() { local f="$1"; shift; exec "$S/$f" "$@"; }

help() {
  cat <<'EOF'
hs — homeserver command. Run from anywhere.

EVERYDAY
  hs update [-n|-y|--images]   pull latest + redeploy (reconciles .env, dirs, …)
  hs doctor                    read-only health check — what's wrong / what to run
  hs diagnose [area]           deep root-cause for one subsystem (decluttarr|sonarr|radarr|recyclarr|qbit|all)
  hs up|down|restart [stack]   start / stop / restart all stacks (or one)
  hs status [stack]            docker compose ps for each stack
  hs pull [stack]              pull newer images
  hs logs <stack|container>    tail logs (-f to follow); stack = compose, else docker
  hs stacks [enable|disable|reconcile]  choose which stacks deploy

SETUP (first time)
  hs setup [--fresh]           run bootstrap (--fresh: full host setup on a new box)
  hs install                   symlink `hs` onto your PATH so it works anywhere

.ENV
  hs env init                  create .env from the template
  hs env sync                  append vars added to .env.example
  hs env tidy                  reformat .env back into the template layout
  hs secrets                   fill any blank machine secrets (DB-safe)
  hs keys                      pull app API keys into .env (dashboard widgets)

MAINTENANCE
  hs cron                      (re)install the maintenance cron jobs
  hs hooks                     (re)install the git pre-push validation hook
  hs network                   (re)create the shared `home` docker network

  hs help                      this list      hs <cmd> -h   help for one command

Flags everywhere:  -n/--dry-run   -y/--yes   -h/--help
EOF
}

install() {
  local link=""
  # Prefer /usr/local/bin — always on PATH (every dir, every user, even cron), so
  # `hs` just works with no .bashrc/PATH fuss. Try without sudo (root), then with.
  if ln -sf "$ROOT/hs" /usr/local/bin/hs 2>/dev/null \
     || { command -v sudo >/dev/null && sudo ln -sf "$ROOT/hs" /usr/local/bin/hs 2>/dev/null; }; then
    link=/usr/local/bin/hs
  else
    # No sudo — fall back to the user bin dir, and wire up PATH so it still works.
    local target="$HOME/.local/bin"
    mkdir -p "$target"
    ln -sf "$ROOT/hs" "$target/hs"
    link="$target/hs"
    case ":$PATH:" in
      *":$target:"*) ;;
      *) local rc="$HOME/.bashrc"; [[ "${SHELL:-}" == *zsh* ]] && rc="$HOME/.zshrc"
         local line="export PATH=\"$target:\$PATH\""
         grep -qsF "$line" "$rc" 2>/dev/null || printf '%s\n' "$line" >> "$rc"
         echo "Added $target to PATH in $rc — open a new shell or: source $rc" ;;
    esac
  fi
  echo "Linked: $link -> $ROOT/hs   (run: hs help)"
  # Tab-completion (bash-completion auto-loads a file named after the command).
  local comp="$HOME/.local/share/bash-completion/completions"
  mkdir -p "$comp"
  ln -sf "$ROOT/scripts/hs-completion.bash" "$comp/hs"
  echo "Tab-completion linked (loads in a new shell). zsh: 'autoload -U +X bashcompinit && bashcompinit' first."
}

cmd="${1:-help}"; shift || true
case "$cmd" in
  update)                run update.sh "$@" ;;
  doctor)                run doctor.sh "$@" ;;
  diagnose)              run diagnose.sh "$@" ;;
  up|down|restart|pull|status) exec "$S/stack.sh" "$cmd" "$@" ;;
  logs)
    name="${1:-}"; shift 2>/dev/null || true
    [[ -z "$name" ]] && { echo "usage: hs logs <stack|container> [-f] [service]" >&2; exit 1; }
    cd "$ROOT"
    if [[ -f "$name/docker-compose.yml" ]]; then
      exec docker compose -f "$name/docker-compose.yml" --env-file .env logs --tail=200 "$@"
    else
      exec docker logs --tail=200 "$@" "$name"
    fi ;;
  secrets)               run gen-secrets.sh "$@" ;;
  keys)                  run harvest-keys.sh "$@" ;;
  stacks)                run stacks.sh "$@" ;;
  network)               run create-network.sh "$@" ;;
  cron)                  run schedule-maintenance.sh "$@" ;;
  hooks)                 run install-hooks.sh "$@" ;;
  setup)
    if [[ "${1:-}" == "--fresh" ]]; then shift; exec "$S/setup-fresh.sh" "$@"; fi
    exec "$ROOT/bootstrap.sh" "$@" ;;
  env)
    sub="${1:-}"; shift 2>/dev/null || true
    case "$sub" in
      init) run env-init.sh "$@" ;;
      sync) run env-sync.sh "$@" ;;
      tidy) run env-rebuild.sh "$@" ;;
      *) echo "hs env {init|sync|tidy}" >&2; exit 1 ;;
    esac ;;
  install)               install ;;
  help|-h|--help|"")     help ;;
  *) echo "hs: unknown command '$cmd' — try 'hs help'" >&2; exit 1 ;;
esac
