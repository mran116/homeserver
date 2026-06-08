#!/usr/bin/env bash
#
# Backs up the IRREPLACEABLE homelab data onto the media array (/mnt/media,
# physical disk sdb1) which is separate from the OS/Docker disk (sda1). This
# protects against the OS disk failing or app data corruption.
#
#   - Databases are dumped logically (pg_dump / mysqldump) for consistent,
#     restorable backups. A raw copy of a live DB data dir is NOT restorable.
#   - App configs, Immich photos and Paperless documents are mirrored with rsync.
#   - The stack .env (secrets needed to bring the stack back) is copied too.
#
# Replaceable media (movies / TV / music / torrents / usenet) is intentionally
# NOT backed up — it can be re-downloaded and dwarfs everything else.
#
# Restore instructions are written to $BACKUP_ROOT/RECOVERY.md on every run.
#
# Run as root (needs to read root-owned /opt/docker/data and /mnt/photos).
set -uo pipefail

# Paths are configurable via .env; the defaults preserve the original hardcoded
# layout, so an unset var (or absent .env) keeps the previous behavior exactly.
# Find .env relative to this script (repo/scripts/backup.sh -> repo/.env) so a
# relocated repo's paths are honored instead of silently falling back to defaults.
# ENV_SRC can still be overridden in the environment for an unusual layout.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_SRC="${ENV_SRC:-$SCRIPT_DIR/../.env}"
if [ -f "$ENV_SRC" ]; then
  set -a                       # export each KEY=value while sourcing
  # shellcheck source=/dev/null
  . "$ENV_SRC"
  set +a
fi

TS="$(date +%Y%m%d-%H%M%S)"
log(){ echo "[backup $TS] $*"; }
running(){ docker ps --format '{{.Names}}' | grep -qx "$1"; }

# Wait for an NFS path to become ready, mounting it on demand. After a reboot the
# backup timer's catch-up run can fire before remote-fs settles; without this the
# old systemd RequiresMountsFor turned "not mounted yet" into a hard dependency
# failure that abandoned the whole night's run. Returns 0 once mounted, else 1.
MNT_WAIT="${BACKUP_MOUNT_WAIT:-120}"
wait_mount(){  # path
  local p="$1" waited=0
  while :; do
    mountpoint -q "$p" 2>/dev/null && return 0
    # Already populated (a normal local dir, or an NFS mount) — usable, no wait.
    [ -d "$p" ] && [ -n "$(ls -A "$p" 2>/dev/null)" ] && return 0
    [ "$waited" -ge "$MNT_WAIT" ] && return 1
    mount "$p" 2>/dev/null || true   # try to bring up an fstab-known mount
    sleep 5; waited=$((waited+5))
  done
}

DATA_SRC="${CONFIG_PATH:-/opt/docker/data}"
PHOTOS_SRC="${PHOTOS_PATH:-/mnt/photos}"
DOCS_SRC="${DOCS_PATH:-/mnt/documents}"
KEEP_DAYS="${BACKUP_KEEP_DAYS:-7}"

# Ownership preservation for the mirrors. A user-squashing NFS export (e.g. the
# Synology backup share) maps every owner to one uid, so rsync's chown always
# fails — thousands of "Operation not permitted" errors, a non-zero exit, and
# nothing actually preserved. Default to NOT syncing owner/group, which is
# lossless there. When the backup target can preserve ownership (a non-squashed
# mount), set BACKUP_PRESERVE_OWNER=1 to restore full `rsync -a` behavior.
if [ "${BACKUP_PRESERVE_OWNER:-0}" = 1 ]; then
  RSYNC_OWN=()
else
  RSYNC_OWN=(--no-owner --no-group)
fi

# Backup destination. Default is a LOCAL path so a fresh clone backs up safely
# out of the box with no assumptions about anyone's mounts. A deployment points
# BACKUP_PATH (.env) at its real target — e.g. an NFS share. The script appends
# this machine's short hostname, so several hosts can share one backup share
# without colliding: self-naming, the SAME .env line on every host, no per-host
# config.
BACKUP_BASE="${BACKUP_PATH:-/var/backups/homestack}"
BACKUP_ROOT="$BACKUP_BASE/$(hostname -s)"

# Fail-safe for the override case: if BACKUP_PATH was set it's meant to be a real
# mount (e.g. the NFS backup share). Wait for it, then refuse to run if it's
# actually on the OS disk — i.e. the mount is missing — so the rsync --delete
# mirror can't silently fill / instead of landing on the share. st_dev differs
# across mount boundaries; matching / means not mounted. The local default is
# exempt (writing locally is the intended fallback there).
if [ -n "${BACKUP_PATH:-}" ]; then
  wait_mount "$BACKUP_BASE" || log "WARN: $BACKUP_BASE did not mount within ${MNT_WAIT}s"
  mkdir -p "$BACKUP_BASE" 2>/dev/null || true
  if [ "$(stat -c %d "$BACKUP_BASE" 2>/dev/null)" = "$(stat -c %d / 2>/dev/null)" ]; then
    log "FATAL: configured backup target $BACKUP_BASE is on the root filesystem (mount missing?) — aborting."
    exit 1
  fi
fi

# Source mounts: give them the same grace so a late NFS mount doesn't cause the
# config/photo/document steps below to skip (or, guarded, treat them as empty).
wait_mount "$DATA_SRC"   >/dev/null 2>&1 || true
wait_mount "$PHOTOS_SRC" >/dev/null 2>&1 || true
wait_mount "$DOCS_SRC"   >/dev/null 2>&1 || true

DB_DIR="$BACKUP_ROOT/db"
DATA_DIR="$BACKUP_ROOT/data"
PHOTOS_DIR="$BACKUP_ROOT/photos"
DOCS_DIR="$BACKUP_ROOT/documents"

mkdir -p "$DB_DIR" "$DATA_DIR" "$PHOTOS_DIR" "$DOCS_DIR"
chmod 700 "$BACKUP_ROOT"   # contains secrets (DB dumps, .env)

# --- 1. Database dumps (secrets are read INSIDE each container) -------------
dump_pg(){
  local c="$1" out="$DB_DIR/${1}-${TS}.sql.gz" tmp
  running "$c" || { log "WARN: $c not running, skipping dump"; return; }
  tmp="$(mktemp "$DB_DIR/.${c}.XXXXXX")"
  if docker exec "$c" sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists' \
        | gzip > "$tmp"; then
    mv "$tmp" "$out"; log "dumped $c -> $(basename "$out")"
  else
    rm -f "$tmp"; log "ERROR: pg_dump $c failed"
  fi
}
dump_mysql(){
  local c="$1" out="$DB_DIR/${1}-${TS}.sql.gz" tmp
  running "$c" || { log "WARN: $c not running, skipping dump"; return; }
  tmp="$(mktemp "$DB_DIR/.${c}.XXXXXX")"
  if docker exec "$c" sh -c 'D=$(command -v mariadb-dump || command -v mysqldump); "$D" -u root -p"$MYSQL_ROOT_PASSWORD" --single-transaction --routines --databases "$MYSQL_DATABASE"' \
        | gzip > "$tmp"; then
    mv "$tmp" "$out"; log "dumped $c -> $(basename "$out")"
  else
    rm -f "$tmp"; log "ERROR: mysqldump $c failed"
  fi
}

dump_pg immich-db
dump_pg paperless-db
dump_pg wger-db

# Vaultwarden (SQLite): take a consistent online .backup — this is the whole
# password DB, so a torn live-file copy is not acceptable. Prefer the HOST's
# sqlite3 against the DB file (the vaultwarden image ships no sqlite3); fall
# back to an in-container .backup, then to the plain live-file copy. The
# resulting db.sqlite3.bak rides along in the config mirror below, and the
# restore in RECOVERY.md prefers it over the live file.
if running vaultwarden; then
  vw_db="$DATA_SRC/vaultwarden/db.sqlite3"
  if command -v sqlite3 >/dev/null 2>&1 && [ -f "$vw_db" ]; then
    if sqlite3 "$vw_db" ".backup '${vw_db}.bak'"; then
      log "vaultwarden: wrote consistent db.sqlite3.bak (host sqlite3)"
    else
      log "WARN: host sqlite3 .backup failed — relying on live-file copy"
    fi
  elif docker exec vaultwarden sh -c 'command -v sqlite3 >/dev/null 2>&1'; then
    docker exec vaultwarden sh -c 'sqlite3 /data/db.sqlite3 ".backup /data/db.sqlite3.bak"' \
      && log "vaultwarden: wrote consistent db.sqlite3.bak (in-container sqlite3)" \
      || log "WARN: vaultwarden sqlite .backup failed"
  else
    log "NOTE: no sqlite3 on host or in image; relying on live-file copy"
  fi
fi

# --- 2. Config mirror (exclude live DB dirs — we have dumps — and caches) ---
if [ -d "$DATA_SRC" ] && [ -n "$(ls -A "$DATA_SRC" 2>/dev/null)" ]; then
  log "mirroring configs from $DATA_SRC"
  rsync -a "${RSYNC_OWN[@]}" --delete \
    --exclude 'immich/db/'         --exclude 'paperless/db/' \
    --exclude 'wger/db/' \
    --exclude 'immich/model-cache/' \
    --exclude 'jellyfin/transcodes/' --exclude 'jellyfin/cache/' \
    --exclude '*/redis/' \
    "$DATA_SRC/" "$DATA_DIR/"
else
  log "ERROR: $DATA_SRC missing/empty — skipping config mirror (NOT deleting backup)"
fi

# --- 3. Irreplaceable originals --------------------------------------------
mirror(){  # src dst label
  if [ ! -d "$1" ]; then
    log "WARN: $1 missing — skipping $3"; return
  fi
  # Guard against rsync --delete wiping a good backup: an unmounted NFS source is
  # an empty mountpoint dir, which would otherwise mirror "nothing" over the
  # backup and delete it. Treat an empty source as "not ready" and keep the
  # existing backup untouched. (Set BACKUP_ALLOW_EMPTY=1 if a source is
  # legitimately empty and you want the deletion to propagate.)
  if [ "${BACKUP_ALLOW_EMPTY:-0}" != 1 ] && [ -z "$(ls -A "$1" 2>/dev/null)" ]; then
    log "WARN: $1 is empty (mount not ready?) — skipping $3 to protect existing backup"; return
  fi
  log "mirroring $3"
  rsync -a "${RSYNC_OWN[@]}" --delete "$1/" "$2/"
}
mirror "$PHOTOS_SRC" "$PHOTOS_DIR" "Immich photos"
mirror "$DOCS_SRC"   "$DOCS_DIR"   "Paperless documents"

# --- 4. Stack secrets (needed to redeploy) ---------------------------------
if [ -f "$ENV_SRC" ]; then
  install -m 600 "$ENV_SRC" "$BACKUP_ROOT/stack.env" && log "copied stack .env"
fi

# --- 5. Rotate DB dumps -----------------------------------------------------
find "$DB_DIR" -name '*.sql.gz' -type f -mtime +"$KEEP_DAYS" -delete
log "rotated DB dumps older than ${KEEP_DAYS}d"

# --- 6. (Re)write recovery instructions into the backup folder -------------
cat > "$BACKUP_ROOT/RECOVERY.md" <<'RECOVERY'
# Homelab recovery guide

This folder is an automated backup of the **irreplaceable** data from the
Docker host, written to the configured backup target (`@@BACKUP_ROOT@@`) — a
storage location **separate from the host's OS/Docker disk** (in this deployment
the NAS `backups` share over NFS). It is produced by
`/opt/docker/stacks/scripts/backup.sh`.

## What's here
```
db/                 logical database dumps  (*.sql.gz, last 7 days kept)
data/               mirror of /opt/docker/data  (app configs + Vaultwarden + SQLite)
photos/             mirror of /mnt/photos       (Immich originals)
documents/          mirror of /mnt/documents    (Paperless originals/consume)
stack.env           copy of /opt/docker/stacks/.env (DB passwords, API keys — KEEP SECRET)
RECOVERY.md         this file
```

## What is NOT backed up (by design)
Movies, TV, music, torrents, usenet under `/mnt/media/*` — these are
re-downloadable and far too large. Regenerable caches (Jellyfin transcodes,
Immich model-cache, redis) are also skipped.

## What this protects against / what it does NOT
- PROTECTS: host OS/Docker disk failure, accidental deletion, app/DB corruption.
- Does NOT protect against: loss of the backup target itself (NAS failure),
  fire/theft, or whole-site loss. For that you still want an **off-site** copy
  (Backblaze B2 / borgbase) — see `infrastructure/borgmatic/config.yaml`.

---

## Full restore (new/rebuilt machine)

1. Install Docker + clone the stacks repo to `/opt/docker/stacks`.
2. Restore secrets:    `cp @@BACKUP_ROOT@@/stack.env /opt/docker/stacks/.env`
3. Restore configs:    `rsync -a @@BACKUP_ROOT@@/data/ /opt/docker/data/`
4. Restore photos:     `rsync -a @@BACKUP_ROOT@@/photos/ /mnt/photos/`
5. Restore documents:  `rsync -a @@BACKUP_ROOT@@/documents/ /mnt/documents/`
6. Start the database containers first (so they create empty DBs), then load
   the dumps (below), then start the rest of the stack.

## Restore a single database

Pick the newest dump in `db/` (filenames end in a timestamp).

### Postgres (immich-db, paperless-db, wger-db)
```bash
C=immich-db                                   # or paperless-db / wger-db
DUMP=@@BACKUP_ROOT@@/db/${C}-YYYYMMDD-HHMMSS.sql.gz
# The dump was made with --clean --if-exists, so it drops & recreates objects.
gunzip -c "$DUMP" | docker exec -i "$C" sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
docker restart "$C"
```

## Restore Vaultwarden (passwords)
Vaultwarden is SQLite. Its whole data dir is mirrored under `data/vaultwarden/`.
```bash
docker stop vaultwarden
rsync -a @@BACKUP_ROOT@@/data/vaultwarden/ /opt/docker/data/vaultwarden/
# If a consistent snapshot exists, prefer it:
[ -f /opt/docker/data/vaultwarden/db.sqlite3.bak ] && \
  mv /opt/docker/data/vaultwarden/db.sqlite3.bak /opt/docker/data/vaultwarden/db.sqlite3
docker start vaultwarden
```

## Restore an *arr app / other config-only service
These keep everything in their config dir; no separate DB.
```bash
docker stop sonarr           # example
rsync -a @@BACKUP_ROOT@@/data/sonarr/ /opt/docker/data/sonarr/
docker start sonarr
```

## Verifying a backup is good
```bash
gunzip -t @@BACKUP_ROOT@@/db/*.sql.gz     # dumps not truncated
ls -la @@BACKUP_ROOT@@/                   # recent timestamps
```
RECOVERY

# Resolve the @@BACKUP_ROOT@@ placeholder to the actual destination so the
# restore commands in RECOVERY.md point at wherever this host's backups landed
# (kept as a token in the quoted heredoc above to avoid expanding the literal
# $C/$DUMP/$POSTGRES_USER examples meant for the reader).
sed -i "s#@@BACKUP_ROOT@@#${BACKUP_ROOT}#g" "$BACKUP_ROOT/RECOVERY.md"

chmod 600 "$BACKUP_ROOT/RECOVERY.md" "$BACKUP_ROOT"/stack.env 2>/dev/null || true
log "wrote RECOVERY.md"
log "done — total backup size: $(du -sh "$BACKUP_ROOT" 2>/dev/null | cut -f1)"
