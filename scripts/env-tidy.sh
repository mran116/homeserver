#!/usr/bin/env bash
# =============================================================================
# env-tidy.sh — reformat .env to match the .env.example template layout.
#
# Over time your .env drifts: new vars land at the bottom (env-sync appends
# them), old inline comments linger, and it stops looking like the clean
# .env.example. This rewrites .env using .env.example as the LAYOUT (its section
# order + the comment above each var) while keeping YOUR values.
#
# Nothing is lost:
#   - any var you have that ISN'T in the template is kept under a CUSTOM section
#   - the original is backed up to .env.bak.<timestamp> BEFORE anything changes
#
# It also FLAGS values that look off so you can fix them while you're here:
#   - a trailing inline comment it had to strip (template style is bare values)
#   - a '|' in a value (usually leftover harvest-keys pipe-corruption)
#   - a duplicate active definition (keeps the first)
#
# Flags: --dry-run (preview only, never writes), --yes (skip the confirm prompt).
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
cd "$REPO_DIR"

usage() { sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
parse_common_flags "$@"
require_cmd python3
require_env || exit 0

TEMPLATE="$REPO_DIR/.env.example"
[[ -f "$TEMPLATE" ]] || die "No template at $TEMPLATE — can't reformat without it."

# env_tidy MODE(report|apply) — single source of truth for the transform.
#   report: prints CARRIED/CUSTOM/FLAG/CHANGED lines (used to build the plan)
#   apply:  atomically rewrites $ENV_FILE with the reformatted content
env_tidy() {
  python3 - "$1" "$TEMPLATE" "$ENV_FILE" <<'PY'
import sys, re, os, pathlib, tempfile, shutil
mode, tmpl_path, env_path = sys.argv[1], sys.argv[2], sys.argv[3]
tmpl = pathlib.Path(tmpl_path).read_text().splitlines()
cur_text = pathlib.Path(env_path).read_text()
envl = cur_text.splitlines()

# A var line: optional "#" prefix, an UPPERCASE-led key, "=", then the value.
# Leading "[A-Z]" avoids matching numbered comments like "# 1a. SYSTEM".
var_re = re.compile(r'^(#?\s*)([A-Z][A-Z0-9_]*)=(.*)$')
def is_commented(prefix): return prefix.strip().startswith('#')

def parse_value(raw):
    flags, v = [], raw
    if v[:1] in ('"', "'"):
        return v, flags                      # quoted — leave exactly as-is
    m = re.search(r'\s#', v)                  # strip a trailing inline comment
    if m:
        v = v[:m.start()]; flags.append('stripped an inline comment')
    v = v.rstrip()
    if '|' in v:
        flags.append("contains '|' (possible old pipe-corruption)")
    return v, flags

# --- parse current .env: active values (first wins), flags, duplicates -------
active, active_flags, order, dups = {}, {}, [], []
for line in envl:
    m = var_re.match(line)
    if not m or is_commented(m.group(1)):
        continue
    key = m.group(2)
    if key in active:
        dups.append(key); continue
    val, fl = parse_value(m.group(3))
    active[key] = val
    if fl: active_flags[key] = fl
    order.append(key)

template_keys = {m.group(2) for line in tmpl if (m := var_re.match(line))}

# --- rebuild from the template, slotting in current values -------------------
out, carried = [], 0
for line in tmpl:
    m = var_re.match(line)
    if m and m.group(2) in active:
        out.append(f"{m.group(2)}={active[m.group(2)]}"); carried += 1
    else:
        out.append(line)

# --- preserve customs (in .env, not in template), keeping their order --------
customs = [k for k in order if k not in template_keys]
commented_customs, seen = [], set(customs)
for line in envl:
    m = var_re.match(line)
    if m and is_commented(m.group(1)):
        k = m.group(2)
        if k not in template_keys and k not in seen:
            seen.add(k); commented_customs.append((k, line.strip()))

if customs or commented_customs:
    out += ["",
            "# " + "=" * 77,
            "# CUSTOM — vars from your previous .env not in the template (preserved)",
            "# " + "=" * 77]
    out += [f"{k}={active[k]}" for k in customs]
    out += [raw for _, raw in commented_customs]

new_text = "\n".join(out).rstrip() + "\n"

if mode == "apply":
    d = os.path.dirname(os.path.abspath(env_path)) or "."
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".env.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as fh: fh.write(new_text)
        try: shutil.copymode(env_path, tmp)
        except OSError: pass
        os.replace(tmp, env_path)
    except BaseException:
        try: os.unlink(tmp)
        except OSError: pass
        raise
else:
    print(f"CARRIED {carried}")
    for k in customs: print(f"CUSTOM {k}")
    for k, _ in commented_customs: print(f"CUSTOM {k}")
    for k, fls in active_flags.items():
        for f in fls: print(f"FLAG {k} {f}")
    for k in dups: print(f"FLAG {k} duplicate active definition (kept the first)")
    print(f"CHANGED {0 if new_text == cur_text else 1}")
PY
}

report="$(env_tidy report)"
changed="$(awk '/^CHANGED /{print $2}' <<<"$report")"
carried="$(awk '/^CARRIED /{print $2}' <<<"$report")"
mapfile -t customs < <(awk '/^CUSTOM /{print $2}' <<<"$report")

if [[ "${changed:-0}" -eq 1 ]]; then
  plan "reformat .env to match .env.example layout (carry over ${carried:-0} value(s))"
  [[ ${#customs[@]} -gt 0 ]] && plan "preserve ${#customs[@]} custom var(s): ${customs[*]}"
  while read -r tag key rest; do
    [[ "$tag" == FLAG ]] && plan "review $key — $rest"
  done <<<"$report"
fi

show_plan || exit 0
gate || exit 0

backup_env
env_tidy apply
say "Reformatted .env to match the template — custom vars preserved."
# Re-surface anything worth a manual look after the rewrite.
while read -r tag key rest; do
  [[ "$tag" == FLAG ]] && warn "$key: $rest"
done <<<"$report"
