#!/usr/bin/env bash
# =============================================================================
# install-hooks.sh — install a git pre-push hook that validates compose locally.
#
# The hook runs `docker compose config` on every stack before each push, so a
# broken YAML / interpolation error is caught on your machine BEFORE it ever
# reaches GitHub (same check the CI runs, just earlier). Bypass once with
# `git push --no-verify`. Flags: --dry-run, --yes.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
cd "$REPO_DIR"

usage() { sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
parse_common_flags "$@"
[[ -d "$REPO_DIR/.git" ]] || die "Not a git repository (no .git dir): $REPO_DIR"
hook="$REPO_DIR/.git/hooks/pre-push"

plan "install git pre-push hook → $hook (validates every stack's compose before a push)"
[[ -f "$hook" ]] && plan "overwrite the existing pre-push hook"
show_plan || exit 0
gate || exit 0

cat > "$hook" <<'HOOK'
#!/usr/bin/env bash
# Installed by scripts/install-hooks.sh — validates compose before pushing.
# Bypass once with:  git push --no-verify
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
env="$([[ -f .env ]] && echo .env || echo .env.example)"
command -v docker >/dev/null || exit 0   # no docker -> skip (CI still checks)
fail=0
for f in */docker-compose.yml; do
  docker compose -f "$f" --env-file "$env" config -q 2>/dev/null && continue
  active=$(awk '/^services:/{i=1;next} /^[^[:space:]#]/{i=0} i&&/^  [A-Za-z0-9_-]+:[[:space:]]*$/{n++} END{print n+0}' "$f")
  [[ "${active:-0}" -eq 0 ]] && continue   # all-commented placeholder
  echo "pre-push: INVALID compose: $f  (fix it, or 'git push --no-verify' to bypass)" >&2
  fail=1
done
exit $fail
HOOK
chmod +x "$hook"
say "pre-push hook installed. It runs on every 'git push'; bypass once with 'git push --no-verify'."
