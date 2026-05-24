#!/usr/bin/env bash
# =============================================================================
# stacks.sh — choose which stacks this host deploys (a local profile).
#
# Three states per stack:
#   approved — deploys with bulk `hs up` (you've decided to keep it)
#   denied   — EXCLUDED from bulk deploy (still deployable by name: hs up <name>)
#   pending  — new since you last decided; you'll be asked about it ONCE
#
# Deploy rule: everything deploys EXCEPT denied stacks. "pending" still deploys,
# but `hs update` asks about each new one first (before the redeploy) so you can
# deny it before it ever starts. Decided stacks are never re-asked.
#
# State lives in .stacks.local (gitignored). No profile yet = everything deploys.
#
#   hs stacks                  show each stack's state
#   hs stacks disable <s..>    exclude stack(s) from bulk deploy
#   hs stacks enable  <s..>    re-include stack(s)
#   hs stacks reconcile        decide each pending (new) stack  (--yes: skip)
#
# Flags: --dry-run, --yes.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
cd "$REPO_DIR"

usage() { sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
parse_common_flags "$@"
# Drop flags so what's left is the subcommand + stack names.
args=(); for a in "$@"; do [[ "$a" == -* ]] || args+=("$a"); done
set -- "${args[@]+"${args[@]}"}"

PROFILE="$REPO_DIR/.stacks.local"
# Deploy order (brought up first→last). Profile membership is filtered from this.
ORDER=(arcane vaultwarden infrastructure monitoring dashboard mediastack household fitness records knowledge syncthing cloud)

SEEN=""; DENIED=""
# shellcheck disable=SC1090
[[ -f "$PROFILE" ]] && source "$PROFILE"

in_list()  { case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
add_to()   { local v; for v in $2; do in_list "$v" "${!1}" || printf -v "$1" '%s' "${!1:+${!1} }$v"; done; }
rm_from()  { local out="" v; for v in ${!1}; do in_list "$v" "$2" || out+="${out:+ }$v"; done; printf -v "$1" '%s' "$out"; }

all_stacks() {  # every stack dir on disk, ORDER first then any extras
  local s d
  for s in "${ORDER[@]}"; do [[ -f "$s/docker-compose.yml" ]] && echo "$s"; done
  for d in */docker-compose.yml; do s="${d%/*}"; in_list "$s" "${ORDER[*]}" || echo "$s"; done
}
state_of() {  # approved | denied | pending
  in_list "$1" "$DENIED" && { echo denied;   return; }
  in_list "$1" "$SEEN"   && { echo approved; return; }
  echo pending
}
save() { printf '# hs stack profile (local, gitignored). SEEN = decided about; DENIED = excluded.\nSEEN="%s"\nDENIED="%s"\n' "$SEEN" "$DENIED" > "$PROFILE"; }

cmd="${1:-status}"; [[ $# -gt 0 ]] && shift
case "$cmd" in
  deploy-list)  # machine-readable: stacks to bulk-deploy (all on disk minus denied), in ORDER
    while read -r s; do in_list "$s" "$DENIED" || echo "$s"; done < <(all_stacks) ;;

  denied-list)  # machine-readable: excluded stacks
    printf '%s\n' $DENIED ;;

  pending-list)  # machine-readable: new/undecided stacks
    while read -r s; do [[ "$(state_of "$s")" == pending ]] && echo "$s"; done < <(all_stacks) ;;

  status)
    say "Stack profile${PROFILE:+ ($([[ -f "$PROFILE" ]] && echo "$PROFILE" || echo 'none yet — everything deploys'))}"
    while read -r s; do
      case "$(state_of "$s")" in
        approved) printf '  %s✓%s %-15s deploys\n'                         "$c_green"  "$c_reset" "$s" ;;
        denied)   printf '  %s✗%s %-15s excluded (hs stacks enable %s)\n'  "$c_red"    "$c_reset" "$s" "$s" ;;
        pending)  printf '  %s?%s %-15s new — deploys; decide via hs update / hs stacks reconcile\n' "$c_yellow" "$c_reset" "$s" ;;
      esac
    done < <(all_stacks) ;;

  enable)
    [[ $# -gt 0 ]] || die "usage: hs stacks enable <stack...>"
    for s in "$@"; do [[ -f "$s/docker-compose.yml" ]] || die "No such stack: '$s'"; done
    [[ $DRY_RUN -eq 1 ]] && { say "[dry-run] would enable: $*"; exit 0; }
    rm_from DENIED "$*"; add_to SEEN "$*"; save; say "Enabled: $*" ;;

  disable)
    [[ $# -gt 0 ]] || die "usage: hs stacks disable <stack...>"
    for s in "$@"; do [[ -f "$s/docker-compose.yml" ]] || die "No such stack: '$s'"; done
    [[ $DRY_RUN -eq 1 ]] && { say "[dry-run] would disable: $*"; exit 0; }
    add_to SEEN "$*"; add_to DENIED "$*"; save
    say "Disabled (excluded from bulk deploy): $*"
    say "Already-running ones aren't stopped — 'hs down $*' to stop them." ;;

  reconcile)
    pending=(); while read -r s; do [[ "$(state_of "$s")" == pending ]] && pending+=("$s"); done < <(all_stacks)
    [[ ${#pending[@]} -eq 0 ]] && { say "No new stacks to decide."; exit 0; }
    if [[ $DRY_RUN -eq 1 ]]; then say "[dry-run] pending: ${pending[*]}"; exit 0; fi
    if [[ $ASSUME_YES -eq 1 ]]; then say "New stack(s) left undecided (--yes): ${pending[*]} — run 'hs stacks' to choose"; exit 0; fi
    # First time (no profile): don't fire a prompt per stack — offer once.
    if [[ ! -f "$PROFILE" ]] && ! ask_yn "Choose which stacks to deploy now? (No = enable all; exclude later with 'hs stacks disable')" N; then
      for s in "${pending[@]}"; do add_to SEEN "$s"; done; save
      say "All stacks enabled. Exclude any later with 'hs stacks disable <name>'."; exit 0
    fi
    say "New stack(s) since you last looked:"
    for s in "${pending[@]}"; do
      add_to SEEN "$s"
      if ask_yn "Deploy '$s'?" Y; then say "  keep $s"; else add_to DENIED "$s"; say "  exclude $s"; fi
    done
    save; say "Stack profile updated." ;;

  *) die "unknown: hs stacks {status|enable|disable|reconcile}" ;;
esac
