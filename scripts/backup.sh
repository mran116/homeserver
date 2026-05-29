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

BACKUP_ROOT="/mnt/media/backups"
DATA_SRC="/opt/docker/data"
PHOTOS_SRC="/mnt/photos"
DOCS_SRC="/mnt/documents"
ENV_SRC="/opt/docker/stacks/.env"
KEEP_DAYS=7

TS="$(date +%Y%m%d-%H%M%S)"
DB_DIR="$BACKUP_ROOT/db"
DATA_DIR="$BACKUP_ROOT/data"
PHOTOS_DIR="$BACKUP_ROOT/photos"
DOCS_DIR="$BACKUP_ROOT/documents"

log(){ echo "[backup $TS] $*"; }
running(){ docker ps --format '{{.Names}}' | grep -qx "$1"; }

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
dump_mysql npm-db

# Vaultwarden (SQLite): take a consistent online .backup if sqlite3 exists in
# the image; the file then rides along in the config mirror below. If sqlite3
# is absent we fall back to the live-file copy (good enough in WAL mode).
if running vaultwarden; then
  if docker exec vaultwarden sh -c 'command -v sqlite3 >/dev/null 2>&1'; then
    docker exec vaultwarden sh -c 'sqlite3 /data/db.sqlite3 ".backup /data/db.sqlite3.bak"' \
      && log "vaultwarden: wrote consistent db.sqlite3.bak" \
      || log "WARN: vaultwarden sqlite .backup failed"
  else
    log "NOTE: sqlite3 not in vaultwarden image; relying on live-file copy"
  fi
fi

# --- 2. Config mirror (exclude live DB dirs — we have dumps — and caches) ---
if [ -d "$DATA_SRC" ] && [ -n "$(ls -A "$DATA_SRC" 2>/dev/null)" ]; then
  log "mirroring configs from $DATA_SRC"
  rsync -a --delete \
    --exclude 'immich/db/'         --exclude 'paperless/db/' \
    --exclude 'wger/db/'           --exclude 'npm/db/' \
    --exclude 'immich/model-cache/' \
    --exclude 'jellyfin/transcodes/' --exclude 'jellyfin/cache/' \
    --exclude '*/redis/' \
    "$DATA_SRC/" "$DATA_DIR/"
else
  log "ERROR: $DATA_SRC missing/empty — skipping config mirror (NOT deleting backup)"
fi

# --- 3. Irreplaceable originals --------------------------------------------
mirror(){  # src dst label
  if [ -d "$1" ]; then
    log "mirroring $3"
    rsync -a --delete "$1/" "$2/"
  else
    log "WARN: $1 missing — skipping $3"
  fi
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
Docker host, written to the media array (`/mnt/media`, disk `sdb1`) which is a
**different physical disk** from the OS/Docker disk (`sda1`). It is produced by
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
- PROTECTS: OS disk (`sda1`) failure, accidental deletion, app/DB corruption.
- Does NOT protect against: loss of the whole machine, `sdb1` failure, fire/theft.
  For that you still want an **off-site** copy (Backblaze B2 / borgbase) — see
  `infrastructure/borgmatic/config.yaml` in the stacks repo.

---

## Full restore (new/rebuilt machine)

1. Install Docker + clone the stacks repo to `/opt/docker/stacks`.
2. Restore secrets:    `cp /mnt/media/backups/stack.env /opt/docker/stacks/.env`
3. Restore configs:    `rsync -a /mnt/media/backups/data/ /opt/docker/data/`
4. Restore photos:     `rsync -a /mnt/media/backups/photos/ /mnt/photos/`
5. Restore documents:  `rsync -a /mnt/media/backups/documents/ /mnt/documents/`
6. Start the database containers first (so they create empty DBs), then load
   the dumps (below), then start the rest of the stack.

## Restore a single database

Pick the newest dump in `db/` (filenames end in a timestamp).

### Postgres (immich-db, paperless-db, wger-db)
```bash
C=immich-db                                   # or paperless-db / wger-db
DUMP=/mnt/media/backups/db/${C}-YYYYMMDD-HHMMSS.sql.gz
# The dump was made with --clean --if-exists, so it drops & recreates objects.
gunzip -c "$DUMP" | docker exec -i "$C" sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
docker restart "$C"
```

### MariaDB (npm-db)
```bash
DUMP=/mnt/media/backups/db/npm-db-YYYYMMDD-HHMMSS.sql.gz
gunzip -c "$DUMP" | docker exec -i npm-db sh -c 'C=$(command -v mariadb || command -v mysql); "$C" -u root -p"$MYSQL_ROOT_PASSWORD"'
docker restart npm-db
```

## Restore Vaultwarden (passwords)
Vaultwarden is SQLite. Its whole data dir is mirrored under `data/vaultwarden/`.
```bash
docker stop vaultwarden
rsync -a /mnt/media/backups/data/vaultwarden/ /opt/docker/data/vaultwarden/
# If a consistent snapshot exists, prefer it:
[ -f /opt/docker/data/vaultwarden/db.sqlite3.bak ] && \
  mv /opt/docker/data/vaultwarden/db.sqlite3.bak /opt/docker/data/vaultwarden/db.sqlite3
docker start vaultwarden
```

## Restore an *arr app / other config-only service
These keep everything in their config dir; no separate DB.
```bash
docker stop sonarr           # example
rsync -a /mnt/media/backups/data/sonarr/ /opt/docker/data/sonarr/
docker start sonarr
```

## Verifying a backup is good
```bash
gunzip -t /mnt/media/backups/db/*.sql.gz     # dumps not truncated
ls -la /mnt/media/backups/                   # recent timestamps
```
RECOVERY

chmod 600 "$BACKUP_ROOT/RECOVERY.md" "$BACKUP_ROOT"/stack.env 2>/dev/null || true
log "wrote RECOVERY.md"
log "done — total backup size: $(du -sh "$BACKUP_ROOT" 2>/dev/null | cut -f1)"
