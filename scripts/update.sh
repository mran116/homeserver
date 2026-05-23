#!/usr/bin/env bash
# =============================================================================
# update.sh — pull the latest repo and redeploy.
#
# git pull (autostash if the tree is dirty — Arcane edits compose files in
# place) then redeploy ALL stacks via stack.sh up. Plan-then-apply.
# Flags: --dry-run, --yes.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
cd "$REPO_DIR"

usage() { sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
parse_common_flags "$@"
require_cmd git
require_docker
git rev-parse --git-dir >/dev/null 2>&1 || die "Not a git repository: $REPO_DIR"

branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$branch" == "HEAD" ]] && die "Detached HEAD — check out a branch first (e.g. git checkout main)."
dirty=0; [[ -n "$(git status --porcelain)" ]] && dirty=1

plan "git pull origin $branch$([[ $dirty -eq 1 ]] && echo '  (--autostash: local edits stashed + reapplied)')"
plan "redeploy all stacks (./scripts/stack.sh up)"
show_plan || exit 0
gate || exit 0

say "Pulling origin/$branch"
if [[ $dirty -eq 1 ]]; then
  git pull --autostash origin "$branch" \
    || die "git pull hit a conflict. Resolve it (your local edits are in 'git stash list' if reapply failed), then re-run."
else
  git pull origin "$branch" || die "git pull failed."
fi

say "Redeploying all stacks"
"$REPO_DIR/scripts/stack.sh" up
say "Update complete."
