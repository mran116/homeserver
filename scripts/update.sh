#!/usr/bin/env bash
# =============================================================================
# update.sh — pull the latest repo, reconcile, and redeploy.
#
# The one-command routine update. It:
#   1. fetches; if nothing new, exits quietly (safe to run from cron)
#   2. git pull (autostash — survives Arcane's in-place edits)
#   3. env-sync   — append any new .env vars
#   4. link-env   — wire up any new stack / fix symlinks
#   5. validates every stack's compose (aborts the redeploy if one is broken)
#   6. redeploys all stacks with --remove-orphans (drops removed services)
#   7. runs doctor — surfaces anything still needing you (e.g. a blank var)
#
# Flags: --dry-run (preview only), --yes (no prompt — for cron), --images
# (also `docker compose pull` newer images before redeploying).
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
cd "$REPO_DIR"

usage() { sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
parse_common_flags "$@"
PULL_IMAGES=0; for a in "$@"; do [[ "$a" == "--images" ]] && PULL_IMAGES=1; done
require_cmd git
require_docker
git rev-parse --git-dir >/dev/null 2>&1 || die "Not a git repository: $REPO_DIR"

branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$branch" == "HEAD" ]] && die "Detached HEAD — check out a branch first (e.g. git checkout main)."

say "Fetching origin/$branch"
for i in 1 2 3 4; do git fetch origin "$branch" 2>/dev/null && break || { warn "fetch failed (try $i)"; sleep $((i*2)); }; done

incoming="$(git rev-list --count "HEAD..origin/$branch" 2>/dev/null || echo 0)"
if [[ "$incoming" -eq 0 ]]; then
  say "Already up to date — nothing to pull."
  exit 0
fi

changed_stacks="$(git diff --name-only "HEAD..origin/$branch" | cut -d/ -f1 | sort -u | tr '\n' ' ')"
plan "git pull origin $branch ($incoming new commit(s))"
[[ -n "$(git status --porcelain)" ]] && plan "autostash local changes (Arcane edits) across the pull"
plan "reconcile: env-sync + link-env"
[[ $PULL_IMAGES -eq 1 ]] && plan "docker compose pull (newer images)"
plan "redeploy all stacks with --remove-orphans"
plan "run doctor (report)"
[[ -n "${changed_stacks// /}" ]] && say "Changed paths: $changed_stacks"
show_plan || exit 0
gate || exit 0

# --- pull --------------------------------------------------------------------
say "Pulling origin/$branch"
if [[ -n "$(git status --porcelain)" ]]; then
  git pull --autostash origin "$branch" \
    || die "git pull hit a conflict. Resolve it (local edits are in 'git stash list' if reapply failed), then re-run."
else
  git pull origin "$branch" || die "git pull failed."
fi

# --- reconcile ---------------------------------------------------------------
"$SCRIPT_DIR/env-sync.sh" --yes
"$SCRIPT_DIR/link-env.sh" --yes

# --- validate before deploying (don't ship a broken pull) --------------------
say "Validating compose files"
bad=0
for compose in */docker-compose.yml; do
  docker compose -f "$compose" --env-file .env config -q >/dev/null 2>&1 && continue
  active=$(awk '/^services:/{i=1;next} /^[^[:space:]#]/{i=0} i&&/^  [A-Za-z0-9_-]+:[[:space:]]*$/{n++} END{print n+0}' "$compose")
  [[ "${active:-0}" -eq 0 ]] && continue   # all-commented placeholder (devops)
  warn "INVALID compose: $compose"; bad=1
done
[[ $bad -eq 1 ]] && die "Aborting redeploy — fix the invalid compose above first. (Repo is pulled; nothing was redeployed.)"

# --- redeploy ----------------------------------------------------------------
if [[ $PULL_IMAGES -eq 1 ]]; then say "Pulling newer images"; "$SCRIPT_DIR/stack.sh" pull || true; fi
say "Redeploying stacks (--remove-orphans)"
STACK_UP_ARGS="--remove-orphans" "$SCRIPT_DIR/stack.sh" up

# --- report ------------------------------------------------------------------
echo
say "Post-update health check:"
"$SCRIPT_DIR/doctor.sh" || true
say "Update complete."
