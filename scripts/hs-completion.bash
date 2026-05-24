# Bash tab-completion for the `hs` command.
# Installed by `hs install` into ~/.local/share/bash-completion/completions/hs
# (auto-loaded by bash-completion). For zsh, run once before sourcing:
#   autoload -U +X bashcompinit && bashcompinit

# Resolve the repo root from wherever `hs` is on PATH (it lives at the root).
_hs_root() {
  local p; p="$(command -v hs 2>/dev/null)" || return 1
  p="$(readlink -f "$p" 2>/dev/null || echo "$p")"
  dirname "$p"
}

_hs() {
  local cur cmds first root stacks
  cur="${COMP_WORDS[COMP_CWORD]}"
  cmds="update doctor up down restart pull status logs stacks env secrets keys cron hooks network setup install help"

  if (( COMP_CWORD == 1 )); then
    COMPREPLY=( $(compgen -W "$cmds" -- "$cur") )
    return
  fi

  first="${COMP_WORDS[1]}"
  case "$first" in
    env)    (( COMP_CWORD == 2 )) && COMPREPLY=( $(compgen -W "init sync tidy" -- "$cur") ) ;;
    setup)  COMPREPLY=( $(compgen -W "--fresh" -- "$cur") ) ;;
    update) COMPREPLY=( $(compgen -W "--images --dry-run --yes" -- "$cur") ) ;;
    up|down|restart|pull|status|logs)
      root="$(_hs_root)" || return
      stacks="$(cd "$root" 2>/dev/null && for d in */docker-compose.yml; do [ -e "$d" ] && echo "${d%/*}"; done)"
      COMPREPLY=( $(compgen -W "$stacks" -- "$cur") )
      ;;
    stacks)
      if (( COMP_CWORD == 2 )); then
        COMPREPLY=( $(compgen -W "status enable disable reconcile" -- "$cur") )
      else
        root="$(_hs_root)" || return
        stacks="$(cd "$root" 2>/dev/null && for d in */docker-compose.yml; do [ -e "$d" ] && echo "${d%/*}"; done)"
        COMPREPLY=( $(compgen -W "$stacks" -- "$cur") )
      fi
      ;;
  esac
}
complete -F _hs hs
