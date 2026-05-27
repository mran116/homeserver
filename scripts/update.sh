#!/usr/bin/env bash
# =============================================================================
# update.sh — pull the latest repo, reconcile, and redeploy.
#
# The one-command routine update. It:
#   1. fetches; if nothing new, exits quietly (safe to run from cron)
#   2. git pull (autostash — survives Arcane's in-place edits)
#   3. env-sync          — append any new .env vars
#   4. gen-secrets       — fill any blank machine secrets (DB-safe; e.g. a new stack)
#   5. link-env          — wire up any new stack / fix symlinks
#   6. make-dirs         — sync repo Homepage config → CONFIG_PATH (repo = truth)
#   7. patch-qbit-auth   — drift-fix the qBit WebUI subnet whitelist (idempotent)
#   8. seed-arr-quality  — move any new Sonarr/Radarr items onto the right profile
#   9. asks about any NEW stacks (deploy or exclude); decided ones aren't re-asked
#  10. re-applies cron + git hooks IF already set up — keeps them matching the
#      repo (fixes drift); won't impose them if you removed them
#  11. if new .env vars were added, offers to tidy .env (interactive only)
#  12. validates every stack's compose (aborts the redeploy if one is broken)
#  13. redeploys the enabled stacks with --remove-orphans (drops removed services)
#  14. runs doctor — surfaces anything still needing you (e.g. a blank var)
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

usage() { sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
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
[[ "$incoming" -eq 0 ]] && say "No new commits — will still reconcile + redeploy (applies .env edits, restarts anything stopped)."

changed_stacks="$(git diff --name-only "HEAD..origin/$branch" 2>/dev/null | cut -d/ -f1 | sort -u | tr '\n' ' ')"
[[ "$incoming" -gt 0 ]] && plan "git pull origin $branch ($incoming new commit(s))"
[[ "$incoming" -gt 0 && -n "$(git status --porcelain)" ]] && plan "autostash local changes (Arcane edits) across the pull"
plan "reconcile: env-sync + gen-secrets + link-env + Homepage config + new-stack check + cron/hooks"
[[ $PULL_IMAGES -eq 1 ]] && plan "docker compose pull (newer images)"
plan "redeploy all stacks with --remove-orphans (applies .env, restarts anything stopped)"
plan "run doctor (report)"
[[ -n "${changed_stacks// /}" ]] && say "Changed paths: $changed_stacks"
show_plan || exit 0
gate || exit 0

# --- pull (only when there are new commits) ----------------------------------
if [[ "$incoming" -gt 0 ]]; then
  say "Pulling origin/$branch"
  if [[ -n "$(git status --porcelain)" ]]; then
    git pull --autostash origin "$branch" \
      || die "git pull hit a conflict. Resolve it (local edits are in 'git stash list' if reapply failed), then re-run."
  else
    git pull origin "$branch" || die "git pull failed."
  fi
fi

# --- reconcile (keep the box matching the repo) ------------------------------
before_vars="$(grep -oE '^[A-Z0-9_]+=' "$ENV_FILE" 2>/dev/null | sort -u || true)"
"$SCRIPT_DIR/env-sync.sh" --yes
"$SCRIPT_DIR/gen-secrets.sh" --yes   # fill blank secrets a new stack added (DB-safe; no-op otherwise)
"$SCRIPT_DIR/link-env.sh" --yes
"$SCRIPT_DIR/make-dirs.sh" --yes
# Drift-protection: re-apply qBit subnet whitelist + re-seed *arr quality
# profiles.  Both soft-skip when their respective containers aren't running,
# so update is safe even on a partially-deployed host.
"$SCRIPT_DIR/patch-qbit-auth.sh" --yes
"$SCRIPT_DIR/seed-arr-quality.sh" --yes
# Ask about any NEW stacks BEFORE redeploy (so you can exclude one before it ever
# starts). Prompts each pending stack; --yes/cron leaves them pending (undecided).
if [[ $ASSUME_YES -eq 1 ]]; then "$SCRIPT_DIR/stacks.sh" reconcile --yes; else "$SCRIPT_DIR/stacks.sh" reconcile; fi
# Re-apply cron / git hooks to match the repo, but ONLY if already set up — fixes
# drift without imposing them on someone who deliberately removed them.
if crontab -l 2>/dev/null | grep -q '# homestack-'; then
  "$SCRIPT_DIR/schedule-maintenance.sh" --yes
fi
if grep -q 'install-hooks.sh' .git/hooks/pre-push 2>/dev/null; then
  "$SCRIPT_DIR/install-hooks.sh" --yes
fi
# If env-sync added new var(s), offer to reformat .env to the template — but only
# interactively (never reformat unattended under --yes / cron).
after_vars="$(grep -oE '^[A-Z0-9_]+=' "$ENV_FILE" 2>/dev/null | sort -u || true)"
new_vars="$(comm -13 <(printf '%s\n' "$before_vars") <(printf '%s\n' "$after_vars") | grep -v '^$' || true)"
if [[ -n "$new_vars" && $ASSUME_YES -eq 0 ]]; then
  say "New var(s) added to .env:"; printf '   %s\n' $new_vars
  if ask_yn "Reformat .env to match the template now? (hs env tidy)"; then
    "$SCRIPT_DIR/env-rebuild.sh" --yes
  fi
fi

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
