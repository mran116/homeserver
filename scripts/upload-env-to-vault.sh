#!/usr/bin/env bash
# =============================================================================
# upload-env-to-vault.sh
#
# Push every KEY=value from .env into Vaultwarden as secure notes, filed under
# a "homestack" folder. Re-runnable: existing notes with the same name in the
# folder are updated in place; new keys are created. Comments and blank lines
# are skipped. Pass --dry-run to preview without writing.
#
# One-time setup (on the machine you run this from):
#   npm install -g @bitwarden/cli       # or: snap install bw
#   bw config server https://vault.<your-domain>
#   bw login                            # email + master password (+ 2FA)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

ENV_FILE="${ENV_FILE:-$REPO_DIR/.env}"
FOLDER_NAME="${FOLDER_NAME:-homestack}"
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

command -v bw >/dev/null || { echo "bw (Bitwarden CLI) not found. See header for install steps." >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required." >&2; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo "No env file at $ENV_FILE" >&2; exit 1; }

# Unlock — reuse BW_SESSION if it's already valid, otherwise prompt.
if [[ -n "${BW_SESSION:-}" ]] && bw status --session "$BW_SESSION" 2>/dev/null | grep -q '"unlocked"'; then
  :
else
  status="$(bw status | jq -r .status)"
  case "$status" in
    unauthenticated) echo "Run 'bw login' first." >&2; exit 1 ;;
    locked|unlocked) BW_SESSION="$(bw unlock --raw)" ;;
    *)               echo "Unexpected bw status: $status" >&2; exit 1 ;;
  esac
fi
export BW_SESSION

bw sync --session "$BW_SESSION" >/dev/null

# Find or create the folder.
folder_id="$(bw list folders --session "$BW_SESSION" \
  | jq -r --arg n "$FOLDER_NAME" '.[] | select(.name==$n) | .id' | head -n1)"
if [[ -z "$folder_id" ]]; then
  if (( DRY_RUN )); then
    echo "[dry-run] would create folder: $FOLDER_NAME"
    folder_id="DRYRUN"
  else
    folder_id="$(bw get template folder \
      | jq --arg n "$FOLDER_NAME" '.name=$n' \
      | bw encode | bw create folder --session "$BW_SESSION" | jq -r .id)"
    echo "created folder: $FOLDER_NAME ($folder_id)"
  fi
else
  echo "folder exists: $FOLDER_NAME ($folder_id)"
fi

# Index existing items in that folder by name so we can update in place.
declare -A existing
while IFS=$'\t' read -r id name; do
  [[ -n "$id" ]] && existing["$name"]="$id"
done < <(bw list items --folderid "$folder_id" --session "$BW_SESSION" 2>/dev/null \
         | jq -r '.[] | [.id, .name] | @tsv')

created=0; updated=0; skipped=0
while IFS= read -r line || [[ -n "$line" ]]; do
  # strip CR, skip blanks/comments, require KEY=VALUE
  line="${line%$'\r'}"
  [[ -z "${line// }" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
  key="${BASH_REMATCH[1]}"
  val="${BASH_REMATCH[2]}"
  # strip a single layer of surrounding quotes
  if [[ "$val" =~ ^\"(.*)\"$ ]] || [[ "$val" =~ ^\'(.*)\'$ ]]; then
    val="${BASH_REMATCH[1]}"
  fi
  # skip empties — no point uploading unset placeholders
  if [[ -z "$val" ]]; then
    ((skipped++)); continue
  fi

  payload="$(bw get template item \
    | jq --arg n "$key" --arg v "$val" --arg f "$folder_id" \
        '.folderId=$f | .name=$n | .notes=$v | .type=2 | .secureNote={type:0} | del(.login,.card,.identity)')"

  if [[ -n "${existing[$key]:-}" ]]; then
    if (( DRY_RUN )); then
      echo "[dry-run] update $key"
    else
      echo "$payload" | bw encode | bw edit item "${existing[$key]}" --session "$BW_SESSION" >/dev/null
      echo "updated  $key"
    fi
    ((updated++))
  else
    if (( DRY_RUN )); then
      echo "[dry-run] create $key"
    else
      echo "$payload" | bw encode | bw create item --session "$BW_SESSION" >/dev/null
      echo "created  $key"
    fi
    ((created++))
  fi
done < "$ENV_FILE"

echo
echo "done. created=$created updated=$updated skipped_empty=$skipped"
echo "folder: $FOLDER_NAME"
(( DRY_RUN )) && echo "(dry-run — nothing was written)"
