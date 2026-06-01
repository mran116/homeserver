# Porting to your own machine & layout

A practical overview for deploying this stack on a **different box** — different
media paths, different folder names, different disk layout. It covers what the
setup does **for you automatically** and what you **do by hand**, then the
specifics of adapting it to a storage layout that isn't the default.

For the full step-by-step install and per-app post-deploy notes, see
[INSTALL.md](INSTALL.md). This doc is the high-level map + the layout gotchas.

---

## The one rule that governs everything

**All of your media _and_ the stack's download folders must live on a single
filesystem (one disk or one pooled mount).** That's because the *arr apps
**hardlink** completed downloads into your library — instant, no extra disk
used, and torrents keep seeding. Hardlinks **cannot cross filesystems**.

Everything else — folder names, how deeply they're nested, where on the disk
they sit — is flexible. Only "same filesystem" is non-negotiable.

- ✅ One drive (or a mergerfs/ZFS pool) holding library + downloads → perfect.
- ⚠️ Library on disk A, downloads on disk B → imports become slow full **copies**
  that double your disk usage. Fix by pooling the disks (e.g. mergerfs) and
  pointing `MEDIA_PATH` at the pool.

---

## What an install looks like, end to end

```
┌─ 1. HOST PREP ──────────────── you (or setup-fresh.sh on Debian/Ubuntu)
│     mount disks, install Docker
│
├─ 2. BOOTSTRAP ──────────────── automatic  (./bootstrap.sh  /  hs setup)
│     .env, secrets, directories, network, symlinks, cron, installs `hs`
│
├─ 3. DEPLOY STACKS ──────────── you (Arcane UI or `hs up <stack>`)
│
├─ 4. APP SETUP ──────────────── you, inside each app's web UI
│     root folders, logins, indexers, download client
│
└─ 5. WIRE THE DASHBOARD ─────── automatic-assisted (hs keys) + a little by hand
      harvest API keys, paste a few tokens
```

---

## What's automatic vs manual

### Step 1 — Host prep · **mostly manual**

| Task | Who |
|---|---|
| Install the OS | You |
| **Mount your media/data disks** (fstab, NAS, mergerfs pool) | **You** — the stack never touches your disk mounts |
| Install Docker + compose | `setup-fresh.sh` (Debian/Ubuntu) — or you, on other distros |
| Docker log rotation, qemu-guest-agent, add user to `docker` group | `setup-fresh.sh` |
| Host firewall | You (do it at your router) |

> `setup-fresh.sh` is the friend-friendly path: `git clone`, `cd`, `./scripts/setup-fresh.sh`. It installs Docker then hands off to `bootstrap.sh`. It explicitly does **not** mount disks or deploy stacks.

> **Mounting an SMB/CIFS NAS?** Two gotchas:
> 1. **Install the CIFS client first** — it's *not* in a base Debian/Ubuntu:
>    `sudo apt install cifs-utils` (provides `mount.cifs`). Without it the mount
>    fails with `mount: unknown filesystem type 'cifs'`.
> 2. **Manga / anime (or any non-Latin filenames)?** Add **`iocharset=utf8`** to
>    the mount options, e.g.
>    `//nas/media /mnt/media cifs credentials=/etc/smb-cred,uid=1000,gid=1000,iocharset=utf8,nofail 0 0`.
>    Without it, Japanese (CJK) filenames arrive mangled (`?????`) and Sonarr/
>    Jellyfin can't see or import them.
>
> Local ext4/mergerfs and NFS need neither. If an app still mis-displays CJK on a
> working mount, set `LANG=C.UTF-8` on that container.

### Step 2 — Bootstrap · **automatic** (`./bootstrap.sh`, re-runnable)

Each step previews, then asks to apply (Enter = sensible default). In order:

| Step | What it does | Your input |
|---|---|---|
| `env-init` | Creates `.env` from the template | Prompts for `TZ`, `CONFIG_PATH`, **`MEDIA_PATH`**, `PHOTOS_PATH`, `DOCS_PATH`, `SAB_INCOMPLETE_PATH` (Enter for defaults) |
| `env-sync` | Appends any new template vars to an existing `.env` | none |
| `gen-secrets` | Generates **all** DB passwords, JWT/secret keys, admin tokens (random, strong) | none — and it skips DBs that already exist so it can't orphan data |
| `make-dirs` | Creates the config dirs + `MEDIA_PATH`/`PHOTOS_PATH`/`DOCS_PATH` + SAB/Tdarr scratch, with correct ownership | none |
| `link-env` | Symlinks the one root `.env` into every stack | none |
| `create-network` | Creates the shared `home` Docker network | none |
| `patch-qbit-auth` | Whitelists the Docker subnet in qBittorrent | none |
| `seed-arr-quality` | Applies sane *arr quality profiles | none |
| `schedule-maintenance` | Installs the maintenance cron jobs | none |
| `hs install` | Puts `hs` on your PATH with tab-completion | none |

After this you have a fully configured `.env` (secrets filled), all directories,
the network, and the `hs` command — **but no stacks are running yet** (bootstrap
optionally starts only Arcane, the Docker UI).

### Step 3 — Deploy the stacks · **manual** (one-time)

From the Arcane UI (or `hs up <stack>`), deploy in dependency order:

```
vaultwarden → infrastructure → monitoring → dashboard → mediastack
→ household → records → knowledge → syncthing → cloud
```

Which stacks/optional services run is controlled by `COMPOSE_PROFILES` in `.env`
(media server choice, VPN, backups, tunnel, etc.) — see the README.

### Step 4 — App setup · **manual, inside each app**

This is where your specific layout and personal logins get configured. None of
it lives in the repo — it's stored in each app's own database.

| App | What you set by hand |
|---|---|
| **Sonarr / Radarr / Lidarr / Whisparr** | **Root folders** → point at your actual library paths under `/data` (see below) |
| **qBittorrent** | WebUI password (then match `APP_PASSWORD` in `.env`) |
| **SABnzbd** | Set the incomplete folder to `/data/incomplete`; grab the API key |
| **Prowlarr** | Add your indexers; connect it to the *arr |
| **Jellyfin/Plex** | Add libraries pointing at your `/data` subfolders |
| **wger / Vaultwarden / Paperless / etc.** | Create your account (Paperless admin is pre-seeded from `.env`) |

### Logins & secrets — what's generated vs what you create

**`gen-secrets` (during bootstrap) auto-generates** every machine secret and
writes it into `.env` — you never invent these:

- Vaultwarden `/admin` panel token
- **Paperless** DB password, secret key, **and the admin login** (`admin` +
  generated password — you log in with the value in `.env`, no manual creation)
- Immich DB password · Donetick JWT · Arcane encryption + JWT keys
- wger DB password + Django secret/signing keys

**You create these accounts by hand, in the app's web UI on first run:**

| App | First-run login | Notes |
|---|---|---|
| Arcane | default `arcane` / `arcane-admin` | **change immediately** |
| qBittorrent | default `admin` / `adminadmin` | change it, then set `APP_PASSWORD` in `.env` to match |
| Vaultwarden | self-signup | temporarily set `VAULTWARDEN_SIGNUPS_ALLOWED=true`, register, set back to `false` |
| Jellyfin / Plex | setup wizard | create the admin user |
| Immich | web UI | first account becomes admin |
| Navidrome · Audiobookshelf | web UI | first account becomes admin |
| Mealie · Actual Budget · Memos · Donetick · **wger** | self-signup | your personal account (DB/secrets already set for you) |
| AdGuard Home | setup wizard | create admin (and it must own port 53) |
| SABnzbd · Prowlarr | setup wizard | SAB: set incomplete folder + grab API key; Prowlarr: add indexers |
| Paperless | **none — auto-created** | log in with `PAPERLESS_ADMIN_*` from `.env` |
| Homepage · Dozzle · Diun | **none** | no login |

**API keys for the Homepage widgets** — `hs keys` does most of this for you:

- **Auto-detected** from each app's config after first boot: Sonarr, Radarr,
  Lidarr, Whisparr, Prowlarr (and it computes the Navidrome token).
- **Manual paste** into `.env`: Bazarr (config.yaml-based), Jellyfin, Seerr,
  Mealie, Immich, Audiobookshelf — generate in each app, paste, redeploy dashboard.

### Step 5 — Wire the dashboard · **assisted + a little manual**

| Task | Who |
|---|---|
| Harvest *arr/app API keys into `.env` for Homepage widgets | `hs keys` (automatic detection) — then redeploy dashboard |
| VPN keys (`WIREGUARD_*`), Tailscale/Cloudflare tokens, HA/Proxmox tokens | **You** — paste into `.env` |
| Subscribe the ntfy app to `diun-updates` for update alerts | You |

---

## Adapting to YOUR media layout

The *arr containers mount your **whole** media root at `/data`:

```yaml
- ${MEDIA_PATH}:/data        # the entire media root — layout-agnostic
```

So the repo hardcodes **no library folder names**. `tv`, `movies`, etc. are not
assumed anywhere — each app's **root folder** is a setting inside that app.

### Different names / nesting — no problem

Say your library lives at `/tank/stuff/mytv`, `/tank/stuff/mymovies`, all on one
drive mounted at `/tank`:

1. During bootstrap (or later in `.env`), set **`MEDIA_PATH=/tank`**.
2. Bring up the mediastack.
3. In Sonarr → *Settings → Media Management → Root Folders*, add **`/data/stuff/mytv`**.
   In Radarr, add `/data/stuff/mymovies`. (Inside the container, `/tank` = `/data`.)

That's it. Depth and names are irrelevant — hardlinks work anywhere on the same
filesystem, so it doesn't matter that the stack's downloads sit at the mount root
(`/data/torrents`, `/data/usenet`) while your library is nested deeper.

### Folders the stack manages (don't rename these)

Created under `MEDIA_PATH`, mounted by fixed name — leave them as-is:

- `MEDIA_PATH/torrents` → `/data/torrents`  (qBittorrent completed)
- `MEDIA_PATH/usenet`   → `/data/usenet`    (SABnzbd completed)
- `MEDIA_PATH/audiobooks`, `MEDIA_PATH/books` (only if you use Audiobookshelf)

Your *library* names are free; these *download/app* mount names are fixed.

### Media spread across multiple disks — use one of these

If your media genuinely can't sit under a single mount:

1. **Pool the disks** (mergerfs / ZFS) into one logical root, point `MEDIA_PATH`
   at the pool. Recommended — keeps hardlinks working across everything.
2. **Per-folder override** — create `mediastack/docker-compose.override.yml`
   (gitignored; the tooling auto-includes it) and add your own mounts:
   ```yaml
   services:
     sonarr:      { volumes: ["/diskA/mytv:/data/tv"] }
     radarr:      { volumes: ["/diskB/movies:/data/movies"] }
     qbittorrent: { volumes: ["/diskA/downloads:/data/torrents"] }
   ```
   Hardlinks still only work where a library and its download source share a
   filesystem — so keep each library on the same disk as the downloads that feed
   it, or accept copies.

### Other path knobs in `.env`

- `CONFIG_PATH` — app databases. **Keep on local disk**, never a NAS (DBs corrupt).
- `SAB_INCOMPLETE_PATH` — usenet scratch; **fast local disk** (heavy random I/O).
- `PHOTOS_PATH`, `DOCS_PATH`, `SYNC_PATH` — Immich / Paperless / Syncthing roots.
- `MUSIC_PATH` — optional Navidrome override (defaults to `MEDIA_PATH/music`).

---

## TL;DR for a friend

1. Mount your media drive; install Docker (`setup-fresh.sh` does Docker for you).
2. `./bootstrap.sh` → answer a few prompts (set `MEDIA_PATH` to your media drive),
   it generates everything else.
3. Deploy the stacks from Arcane.
4. In each *arr, set the **root folder** to wherever your library lives under `/data`.
5. `hs keys`, paste your VPN/tokens, done.

Keep all media + downloads on one filesystem and you'll never think about paths
again.
