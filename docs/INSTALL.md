# 🛠️ Install & Setup Guide

> 📖 **Docs:** [README](../README.md) · [Reference](REFERENCE.md) · [Remote-access design](network-and-remote-access.md) · [Home Assistant](HOME-ASSISTANT.md)

The detailed how-to behind the [README](../README.md) quick start: full directory
layout, the manual install flow, per-app post-deploy steps, optional services,
hardware transcoding, troubleshooting, and low-effort maintenance.

> New here? Start with the **Quick Start** in the [README](../README.md#-quick-start) —
> most people never need this file. Come back when you want the manual flow or a
> specific app's setup.

## Contents
- [Directory Structure](#-directory-structure)
- [Environment Variables](#-environment-variables)
- [GitOps Workflow](#-gitops-workflow) · [updating the host](#updating-the-host) · [single stack (sparse-checkout)](#running-only-one-stack-sparse-checkout)
- [How Stacks Connect](#-how-stacks-connect)
- [Detailed walkthrough (manual install)](#-detailed-walkthrough-manual-install-or-what-the-easy-path-automates)
- [Post-Deploy Setup](#-post-deploy-setup) (per-app)
- [Hardware transcoding, Tdarr & the override file](#-hardware-transcoding-tdarr--the-override-file)
- [Enabling Commented Services](#-enabling-commented-services)
- [Common Gotchas / Troubleshooting](#-common-gotchas--troubleshooting)
- [Maintenance](#-maintenance-set-it-and-forget-it)

---

## 🗂️ Directory Structure

Each top-level folder with a `docker-compose.yml` is **one Arcane stack** (Arcane
discovers stacks one level deep, so the layout is intentionally flat). Related
services are grouped into a single stack rather than scattered across folders.

```
/opt/docker/
├── stacks/                  ← this repo — all compose files
│   ├── arcane/                  Docker management UI (deploy first)
│   ├── vaultwarden/             password manager
│   ├── infrastructure/          Nginx Proxy Manager + AdGuard Home DNS (+ borgmatic/tailscale/cloudflare, commented)
│   ├── monitoring/              Uptime Kuma + Dozzle + Diun + ntfy
│   ├── dashboard/               Homepage (compose + homepage/ configs)
│   ├── mediastack/              Jellyfin + *arr + downloaders + Navidrome + Audiobookshelf + Decluttarr
│   ├── household/               Mealie, KitchenOwl, Donetick, Actual Budget
│   ├── fitness/                 wger — workout & fitness tracker
│   ├── records/                 Paperless-ngx + Stirling PDF
│   ├── knowledge/               Memos (quick notes)
│   ├── syncthing/               private file sync
│   ├── cloud/                   Immich (+ Matrix, commented)
│   └── devops/                  Gitea + CI (commented, Phase 3)
├── hs                       ← single entrypoint for all tooling (run: hs help)
├── reference/               ← NOT stacks — config you copy elsewhere
│   └── home-assistant/          HA packages for the HA VM (/config/packages)
├── scripts/                 ← internals behind `hs` (rarely run directly)
└── data/                    ← all app config + data (bind mounts: jellyfin/, sonarr/, …)

/mnt/media/                  ← Movies, TV, music, anime, books
/mnt/photos/                 ← Immich photo and video library
/mnt/documents/              ← Paperless document storage
/mnt/sync/                   ← Syncthing synced folders
```

All app data lives under `/opt/docker/data/` as bind mounts — easy to back up, easy to find, easy to move.

---

## ⚙️ Environment Variables

All vars are loaded from a single `.env` at the repo root, consumed by every stack's `docker-compose.yml`.

1. `cp .env.example .env`
2. Fill in values (ports + secrets); store actual secrets in **Vaultwarden** for backup
3. Reload affected stacks from Arcane (or `docker compose up -d` per stack)

Never commit `.env` to Git — it is blocked by `.gitignore`.

---

## 🔄 GitOps Workflow

This repo is the single source of truth for every stack:

```
Edit compose file locally in VS Code
  → git commit and push
    → on the host:  git pull
      → in Arcane:  click "Update" on the affected stack
        → new config is live
```

Arcane edits the same files on disk, so anything changed in the UI shows up in `git status` and can be reviewed and committed back. No drift.

### Updating the host
The server runs a plain git clone of this repo at `/opt/docker/stacks`. To pull in changes:

```bash
cd /opt/docker/stacks
git pull
# then reload only the stacks that changed, e.g.:
docker compose -f monitoring/docker-compose.yml --env-file .env up -d
```

Or do both in one shot with `hs update` — it `git pull`s (autostashing
any in-place Arcane edits) and redeploys all stacks. Previews first; `--yes` to
skip the prompt, `--dry-run` to only preview.

`.env` is gitignored, so `git pull` never touches your secrets. Never hand-copy these files between machines — always `git pull` so they can't land in the wrong place.

For bulk operations across all stacks:
```bash
hs pull && hs up            # update all images + redeploy
hs down                     # stop everything (reverse order)
hs status                   # ps for every stack
hs restart mediastack       # target a specific stack
hs logs mediastack -f       # follow a stack's logs
```

### Running only one stack (sparse-checkout)
Want just one stack (e.g. handing a friend the media stack, or running a subset on a second host)? Use git **sparse-checkout** — one clone, but only the folder(s) you pick appear on disk, and `git pull` only updates those. No need to split the repo.

```bash
git clone --no-checkout https://github.com/mran116/homeserver.git
cd homeserver
git sparse-checkout init --cone
git sparse-checkout set mediastack          # pick the stack(s) you want
git checkout main
```

Now the working tree has only `mediastack/` plus the repo's root files (incl. `.env.example`). Then the usual setup:
```bash
cp .env.example .env && nano .env           # fill in the media vars
docker network create home
docker compose -f mediastack/docker-compose.yml --env-file .env up -d
```

- `git pull` updates only the checked-out folders.
- Add more later: `git sparse-checkout set mediastack monitoring`
- Back to everything: `git sparse-checkout disable`
- It's still one repo (the full history is cloned) — sparse-checkout only controls which files appear in the working tree.

> Note: as-is, `mediastack` routes downloads through Gluetun (VPN), so qBittorrent needs valid `WIREGUARD_*` creds in `.env` or it won't connect.

---

## 🔗 How Stacks Connect

All stacks share a single Docker network called `home`. This allows containers in different stacks to communicate by container name:

```
Unpackerr → calls http://sonarr:8989 (different stack, same network)
Homepage  → calls http://jellyfin:8096 (different stack, same network)
Home Assistant (separate VM) → calls http://mealie:9000 over LAN
```

Create the network once before deploying anything:
```bash
docker network create home
```

### Shared `.env` variables (and splitting stacks across hosts)

Everything reads from the single root `.env`. If you ever break the monolith up onto separate machines, here's what each piece needs:

- **Global** — needed by (nearly) every stack: `SERVER_IP`, `TZ`, `PUID`, `PGID`, `CONFIG_PATH` (plus that stack's own path var: `MEDIA_PATH`, `PHOTOS_PATH`, `DOCS_PATH`, `SYNC_PATH`, `SAB_INCOMPLETE_PATH`).
- **The dashboard (Homepage) couples to everything.** It re-reads *every* `*_PORT` and most app keys/logins (forwarded as `HOMEPAGE_VAR_*`) to build its tiles and widgets. So a split-out dashboard still needs all of those, and any app stack you move keeps its port/keys read by wherever the dashboard runs.
- **Shared between two real app stacks:** `APP_USERNAME`, `APP_PASSWORD`, `SABNZBD_API_KEY`, `SONARR_API_KEY`, `RADARR_API_KEY`, `LIDARR_API_KEY` are used by **both** the dashboard widgets **and** the mediastack itself (qBittorrent + decluttarr/unpackerr/recyclarr) — so a standalone mediastack needs them too. The remaining widget keys are dashboard-only.
- **Single-stack** (only the owning stack uses it): DB passwords, JWT/secret keys, VPN/WireGuard keys, Arcane keys, and remote-access tokens (Tailscale/Cloudflare).

---

## 🧭 Detailed walkthrough (manual install, or what the easy path automates)

*The numbered steps below are the same flow as the beginner Quick Start, broken
down — handy for a manual install or to understand what `setup-fresh` did for you.
If the beginner walkthrough worked, skip ahead to **Post-Deploy Setup**.*

### 1 — Install Docker

```bash
curl -fsSL https://get.docker.com | bash
sudo systemctl enable docker
sudo usermod -aG docker $USER
```

> **Brand-new machine?** After cloning (step 2), `hs setup --fresh` (a.k.a. `./scripts/setup-fresh.sh`) does the whole host setup for a fresh Ubuntu/Debian box: apt update/upgrade + base tools, Docker + compose, Docker log rotation, `qemu-guest-agent` if it's a VM, the docker group, then runs `bootstrap.sh`. You still mount your own media/data disks first, and do the firewall at your router.

### 2 — Clone the repo and run bootstrap

```bash
sudo mkdir -p /opt/docker/stacks && sudo chown -R $USER:$USER /opt/docker
git clone https://github.com/mran116/homeserver.git /opt/docker/stacks
cd /opt/docker/stacks
./bootstrap.sh
```

`bootstrap.sh` is interactive and idempotent — safe on a brand-new box, a **partial** setup (e.g. mediastack already configured but the other stacks not), or a fully configured one. It never overwrites anything you've already set. It will:

- check Docker prereqs
- **create `.env`** from `.env.example` if one doesn't exist yet (prompts for SERVER_IP, timezone, PUID/PGID, storage paths — defaults autodetected). If a `.env` already exists it's kept as-is.
- **fill only the blank machine secrets** (DB passwords, Vaultwarden/Paperless tokens, Immich DB password) with random values — a yes/no prompt that tells you how many are blank. Anything you've already set is left untouched, so on a partial setup only the not-yet-used stacks get secrets. If your real secrets live outside this `.env` (e.g. still in Portainer), it warns you to paste them first so new random values don't clash with existing databases.
- **never generates or pre-seeds app API keys.** Each *arr creates its own key on first boot — bootstrap doesn't touch app config at all. You collect the keys *after* the apps are up (next step), which is safer: the script only ever reads app config, never writes it
- **symlink the root `.env` into every stack folder** so Arcane and CLI both find it with no `--env-file` flag on reload
- create the directory layout and the `home` docker network
- sync `dashboard/homepage/*.yaml` into your config dir (re-synced on every `hs update` — the repo is the source of truth)
- **install the `hs` command** onto your PATH (+ tab-completion) so everything afterward is just `hs <command>`
- optionally start Arcane

After the apps are up, run `hs keys`. It **auto-detects** the *arr API keys (Sonarr/Radarr/Lidarr/Whisparr/Prowlarr) straight from each app's generated `config.xml` and writes them to `.env`, then prompts you for the keys that can only come from a UI (Jellyfin, Immich, Mealie, SABnzbd, NPM login, etc.). External tokens (VPN, Tailscale, Cloudflare) are pasted in by hand. Then **redeploy** the consumers (Recyclarr, Unpackerr, Homepage) so they pick up the new keys.

<details>
<summary>Prefer to do it manually?</summary>

```bash
docker network create home
sudo mkdir -p /opt/docker/{stacks,data,data/homepage} && sudo chown -R $USER:$USER /opt/docker
git clone https://github.com/mran116/homeserver.git /opt/docker/stacks
cd /opt/docker/stacks
cp .env.example .env && $EDITOR .env
cp -r dashboard/homepage/* /opt/docker/data/homepage/
# Link the root .env into every stack folder so Arcane/CLI find it without --env-file
for d in */docker-compose.yml; do ln -sf ../.env "$(dirname "$d")/.env"; done
cd arcane && docker compose up -d
```
</details>

### 3 — Configure Arcane

Open `http://YOUR_SERVER_IP:3552`

1. Log in with the first-run credentials **`arcane` / `arcane-admin`** and change the password immediately
2. Arcane auto-discovers every stack under `/opt/docker/stacks` (bind-mounted to the **same** path inside the container, with `PROJECTS_DIRECTORY` set to it — Arcane requires identical paths in/out)

### 4 — Deploy stacks via Arcane

> **Upgrading an existing host?** AdGuard and ntfy used to be their own stacks and
> are now part of `infrastructure` and `monitoring`. The new services reuse the
> same container names (`adguard`, `ntfy`), so the old standalone containers must
> be removed first or the redeploy fails on a name conflict. Your data is safe —
> it lives in `${CONFIG_PATH}/adguard` and `${CONFIG_PATH}/ntfy` and is reused.
> In Arcane, delete the old **`adguard`** and **`ntfy`** stacks (or run
> `docker rm -f adguard ntfy`), then deploy `infrastructure` / `monitoring`.
> Fresh installs can ignore this.

In the Arcane UI, start each stack in this order (click → Start). The order matters:

1. `vaultwarden` — your password vault; stand it up first so you have somewhere to store the secrets bootstrap generated
2. `infrastructure` — reverse proxy + networking + **AdGuard Home** DNS (free host port 53 first — see the AdGuard notes in `infrastructure/docker-compose.yml`); other services sit behind it
3. `monitoring` — Uptime Kuma / Dozzle / Diun + **ntfy** start watching everything else
4. `dashboard` — Homepage; depends on the rest existing, so it comes after
5. `mediastack`
6. `household`
7. `records`
8. `knowledge` — Memos (quick notes)
9. `syncthing`
10. `cloud`

After the first one or two, the rest can be started back-to-back — the order only strictly matters for the first four.

### 5 — Verify it worked

```bash
# Every container should show "running" (and healthy where a healthcheck exists)
docker ps --format 'table {{.Names}}\t{{.Status}}'
```

Then in the browser:
- **Homepage** (`http://YOUR_SERVER_IP:3000`) — tiles load; widgets show live data once you've added API keys (step 7)
- **Uptime Kuma** (`http://YOUR_SERVER_IP:3001`) — import `monitoring/uptime-kuma/seed.json` (Settings → Backup → Import) and watch the monitors go green
- If a container is restarting, check its logs in **Dozzle** (`http://YOUR_SERVER_IP:3002`) — usually a missing secret in `.env`

---

## 📋 Post-Deploy Setup

### Vaultwarden
- Create your account at `http://YOUR_SERVER_IP:9930`
- Enable 2FA immediately
- Set `VAULTWARDEN_SIGNUPS_ALLOWED=false` in .env
- Install the official **Bitwarden** app on all devices
- Point server URL to your Vaultwarden instance
- Store all secrets here going forward

### Nginx Proxy Manager
- Default login: `admin@example.com` / `changeme` — change immediately
- Set up SSL proxy hosts for all your services

### Immich
- Create admin account then accounts for each family member
- Install the **Immich** app on all phones — enable auto backup on WiFi
- Create a shared family album for everyone
- Create private shared albums with restricted member access

### Mealie
- Default login: `changeme@example.com` / `MyPassword` — change immediately
- Import recipes by pasting any URL

### Actual Budget
- Connect your bank via **SimpleFIN** at `beta-bridge.simplefin.org` (~$15/year)

### Uptime Kuma
- Import the pre-built monitor list: **Settings → Backup → Import** → select `monitoring/uptime-kuma/seed.json`
- All ~25 service monitors appear instantly (using container DNS names on the `home` network)
- Add a notification target (Discord, Gotify, ntfy, or your HA webhook) under **Settings → Notifications**, then **Apply on all existing monitors**

### Recyclarr
- A 1080p TRaSH-Guides config ships in `mediastack/recyclarr/recyclarr.yml` (HD Bluray + WEB for movies, WEB-1080p for TV)
- Set `SONARR_API_KEY` and `RADARR_API_KEY` in `.env` (find them in each app under Settings → General)
- First sync runs at the next `@daily` cron tick; force one now with `docker exec recyclarr recyclarr sync`
- To switch to 4K later: edit the `include:` templates and `until_quality` in the yaml

### Diun
- Set `DIUN_NOTIF_WEBHOOK_URL` in `.env` to a Home Assistant webhook
- Create webhook in HA: Settings → Automations → New → Webhook trigger
- HA then fans out the update notification to phone/email/Discord as you prefer
- Diun runs daily at 06:00; opt a container out by labeling it `diun.enable=false`

### Homepage widget API keys (the harvest script)
Filling in API keys for ~15 services by hand is the worst part of any first run. Instead:

```bash
hs keys
```

It first **auto-detects** the *arr keys from each app's generated `config.xml`, then walks the rest (showing the exact URL + click path), prompts once, and writes straight to `.env`. Re-runnable; existing values are skipped unless you pass `--force`.

#### Keeping keys in sync automatically
The *arr keys rarely change, but if you ever regenerate one, you don't want to remember to re-run the script. `--sync` is a non-interactive mode that **detects the *arr keys and, only if one changed, recreates the consumers** (Unpackerr, Recyclarr, Homepage) so they pick up the new value — then exits silently:

```bash
hs keys --sync
```

**`bootstrap.sh` offers to install this for you** — it prompts "Install a nightly cron job to auto-sync *arr API keys?" and, if you accept, adds the entry to your crontab (idempotently, keyed off a `# homestack-key-sync` marker so re-running won't duplicate it). So you don't have to touch cron by hand.

If you'd rather add it yourself, the entry is just:

```cron
# nightly at 4am; no-op unless an *arr key actually changed
0 4 * * * cd /opt/docker/stacks && ./scripts/harvest-keys.sh --sync >> /opt/docker/stacks/key-sync.log 2>&1
```

It only needs `CONFIG_PATH` and Docker access — no ports, no prompts. On a normal night it detects no change and does nothing. The log **self-caps at ~1 MB** (truncated in place, so it never grows unbounded). Remove the job anytime with `crontab -e` (delete the `homestack-key-sync` line).

Both scripts are **location-independent** — they resolve the repo root from their own path and `cd` there, so you can run them from any directory.

### Homepage
- Config source of truth lives in `dashboard/homepage/` (this repo) — edit it here, not on the box
- `make-dirs` (run by `bootstrap.sh` and every `hs update`) mirrors `*.yaml` into the runtime dir `/opt/docker/data/homepage/` (bind-mounted into the container); Homepage hot-reloads
- All ports/IPs/keys come from `.env` via `HOMEPAGE_VAR_*` — never hard-code them in `services.yaml`
- `docker.yaml` enables the Docker integration: each tile shows a **live up/down dot + CPU/RAM** (the tile stays visible, in red, when a container is down). Aggregate up/down + history is the Uptime Kuma widget
- Edit `widgets.yaml` to add your coordinates for the weather widget
- To add a service: add its tile to `services.yaml` (with `server: my-docker` + `container: <name>`), then run `hs update`

---

## 🎞️ Hardware transcoding, Tdarr & the override file

GPU passthrough and per-host media mounts are **host-specific**, so they live in a
**gitignored** `mediastack/docker-compose.override.yml` (not the tracked compose) —
that keeps `git pull` clean on every machine and avoids vendor lock-in. `hs up` and
`hs update` auto-include the override when present.

### Jellyfin / Plex hardware transcoding (playback)
GPU passthrough can't be a plain env var (Compose can't conditionally attach a
device, and a missing GPU would *fail* the deploy), so it's off by default:
```bash
cp mediastack/docker-compose.override.yml.example mediastack/docker-compose.override.yml
# uncomment the block for your media server + GPU (Intel /dev/dri or NVIDIA)
hs up mediastack
```
- **Intel Quick Sync:** uncomment the Intel block, set `RENDER_GID` in `.env`
  (`getent group render | cut -d: -f3`), pick QSV in Jellyfin.
- **NVIDIA NVENC:** uncomment the NVIDIA block (needs the NVIDIA Container Toolkit
  on the host), pick NVENC in Jellyfin.
- **No GPU:** leave it commented — software transcoding still works, nothing fails.

(Jellyfin also mounts the whole media root at `/data`, so any folder layout works —
add libraries in the UI.)

### Tdarr — shrink your library to HEVC/x265
A library transcoder that re-encodes to HEVC (and AV1) to reclaim disk space.
**Off by default.** To turn it on:
1. Add `tdarr` to `COMPOSE_PROFILES` in `.env` (e.g. `jellyfin,tunnel,tdarr`).
2. Set **`TDARR_CACHE`** to a disk **with free space** — Tdarr writes the
   re-encoded file there before swapping in the original (critical if your library
   disk is nearly full).
3. `hs up mediastack`, then open `http://SERVER_IP:8265`.
4. **HW encode:** uncomment the `tdarr` block in the override file (above).
5. **Avoid audio-sync drift** (the classic Tdarr gotcha, usually variable-frame-
   rate sources): use a **HandBrake** flow with framerate **"same as source"
   (variable)**, **audio = passthrough**, **MKV** output. Test on a few files
   first, and don't auto-delete originals until you've confirmed they look/sound right.

It's CPU/GPU-heavy — ideal on a capable box (e.g. with an Intel Arc), rough on a weak one.

### Media that lives outside `MEDIA_PATH`
The base compose mounts your whole library once (`${MEDIA_PATH}:/data`), so the
apps only see folders under `MEDIA_PATH`. If some media lives elsewhere (a second
drive, a NAS share), add an extra mount in the **same** gitignored override.
Compose *appends* to the base volumes, so you list only the new mount — not the
base ones:
```yaml
services:
  audiobookshelf:
    volumes:
      - /mnt/storage/audiobooks:/data/audiobooks   # nests inside /data
```
The longer path wins for that subtree, so `/data/audiobooks` shows the external
folder while the rest of `/data` still comes from `MEDIA_PATH`; point the app's
library at `/data/audiobooks`. Confirm the merged result with
`cd mediastack && docker compose config` before deploying.

---

## 🔓 Enabling Commented Services

### Tailscale — private VPN access
```
1. Get a reusable auth key at: login.tailscale.com/admin/settings/keys
2. Add TS_AUTHKEY to .env
3. Uncomment tailscale in infrastructure/docker-compose.yml
4. Push, `git pull` on host, redeploy in Arcane
5. Approve the advertised subnet route in Tailscale admin panel
```

### Cloudflare Tunnel — secure public access, zero open ports
```
1. Buy a domain at cloudflare.com (~$10/year)
2. Zero Trust → Networks → Tunnels → Create tunnel → copy the token
3. Add CLOUDFLARE_TUNNEL_TOKEN (+ DOMAIN, CLOUDFLARE_DNS_API_TOKEN) to .env
4. Uncomment cloudflared in infrastructure/docker-compose.yml
5. Add public-hostname routes in the Cloudflare dashboard:
   requests.yourdomain.com   → http://seerr:5055
   photos.yourdomain.com     → http://immich-server:3001
   audiobooks.yourdomain.com → http://audiobookshelf:80
   music.yourdomain.com      → http://navidrome:4533
   vault.yourdomain.com      → http://vaultwarden:80   (Access on /admin ONLY)
6. Push, `git pull` on host, redeploy in Arcane

NOTE: Jellyfin is NOT tunneled — streaming video over Cloudflare breaks their
ToS. Serve it direct (DNS-only A record + 443 → NPM, with the ddns-updater for a
dynamic IP) or over Tailscale. Full design: network-and-remote-access.md
```

### Matrix — private encrypted messaging
```
1. Requires a domain and Cloudflare Tunnel first
2. Set MATRIX_SERVER_NAME=yourdomain.com in .env
3. Uncomment synapse in cloud/docker-compose.yml
4. Push, `git pull` on host, redeploy in Arcane
5. Add matrix.yourdomain.com to Cloudflare tunnel routes
6. Install the Element app on devices
```

### DocuSeal — legally binding document signing
```
1. Requires a domain and SMTP setup first
2. Set up Cloudflare Email Routing for your domain (free)
3. Add Gmail SMTP credentials to .env
4. Uncomment docuseal in records/docker-compose.yml
5. Push, `git pull` on host, redeploy in Arcane
```

### Borgmatic — automated offsite backups
```
1. Create a Backblaze B2 account at backblaze.com (free 10GB, then $6/TB/month)
2. Update infrastructure/borgmatic/config.yaml with your B2 bucket and credentials
3. Add BORG_PASSPHRASE to .env
4. Uncomment borgmatic in infrastructure/docker-compose.yml
5. Push, `git pull` on host, redeploy in Arcane
```

### Gitea + Actions runner — self-hosted devops (Phase 3)
```
1. Uncomment gitea, gitea-db, gitea-runner in devops/docker-compose.yml
2. Set GITEA_HTTP_PORT, GITEA_SSH_PORT, GITEA_DB_PASSWORD in .env
3. Start the stack from Arcane; create admin account at http://SERVER_IP:GITEA_HTTP_PORT
4. In Gitea: Site Administration → Actions → Runners → New runner → copy token
5. Set GITEA_RUNNER_TOKEN in .env and restart the runner container
6. (Optional) Mirror this repo from GitHub for local-first GitOps
```

---

## ⚠️ Common Gotchas / Troubleshooting

**Create the home network first**
All stacks use an external Docker network called `home`. Create it once before deploying anything — stacks will fail to deploy without it:
```bash
docker network create home
```

**qBittorrent routes through Gluetun**
qBittorrent uses `network_mode: service:gluetun` — it shares Gluetun's network and has no direct network access of its own. If qBittorrent is unreachable always check Gluetun logs first.

**Homepage requires a hard refresh after config changes**
After editing config files press `Ctrl+Shift+R` (or `Cmd+Shift+R` on Mac) to clear the browser cache and pick up changes.

**Vaultwarden admin panel**
Access the admin panel at `http://YOUR_SERVER_IP:9930/admin` — requires `VAULTWARDEN_ADMIN_TOKEN`. Generate one with:
```bash
openssl rand -base64 48
```

**Immich database image**
Immich requires a specific PostgreSQL image (`tensorchord/pgvecto-rs`) not the standard postgres image. Do not swap this out or Immich will not start.

**Recyclarr needs API keys before it can run**
Recyclarr requires Sonarr and Radarr API keys in its config. It will fail on first deploy until you add API keys from both apps. This is expected — configure it after Sonarr and Radarr are running.

**Nginx Proxy Manager owns host ports 80 and 443**
Unlike every other service (whose host ports come from `.env`), NPM binds host `80` and `443` directly — it has to, to serve HTTP/HTTPS. If anything else on the host already uses those ports (another web server, a second reverse proxy), NPM won't start. Free them first.

**SABnzbd scratch belongs on a fast local disk**
par2 verify/repair and unpack are very IO-intensive (heavy random reads/writes), so performance suffers badly — slow, freezing, even corrupt repairs — on a network mount. Keep SAB's scratch off the NAS: point its **Temporary (incomplete) folder** at a local SSD/NVMe (`SAB_INCOMPLETE_PATH`, mounted as `/incomplete`), and leave the **Completed folder on `/data/usenet`** (the NAS) so the *arr still hardlink-import.

**Browsing Homepage by a name other than its IP**
`HOMEPAGE_ALLOWED_HOSTS` defaults to `SERVER_IP:HOMEPAGE_PORT`. If you reach Homepage via a hostname, Tailscale name, or reverse-proxy domain, set `HOMEPAGE_ALLOWED_HOSTS` in `.env` to a comma-separated list of those names — otherwise Homepage shows a blank "host validation failed" page.

**Immich machine learning is vision, not an LLM**
The `immich-machine-learning` container runs CLIP (smart search) + face recognition models — not a language model. It's idle-light but loads ~2-4 GB into RAM while indexing/face jobs run. On a low-RAM box, set `IMMICH_MACHINE_LEARNING_ENABLED=false` on `immich-server` and comment out the ML container; photo upload/backup still work fully.

---

## 🧹 Maintenance (set it and forget it)

Low-effort guards so the box keeps itself healthy without babysitting.

**1. Cap container logs (one-time, prevents disk-fill).** Runaway logs are a top
cause of "everything broke." Apply the included daemon config:

```
sudo cp reference/docker-daemon.json /etc/docker/daemon.json   # or merge if you already have one
sudo systemctl restart docker
```

**2. Weekly image cleanup.** `bootstrap.sh` offers to install a cron that runs
`docker image prune -af` weekly (removes only unused images — never containers,
volumes, or your bind-mounted data). Logs to `image-prune.log`.

**3. Update alerts → ntfy.** Diun pushes new-image alerts to the ntfy topic
`diun-updates` (already wired in `monitoring/`). Install the **ntfy app**, point
it at `http://<server-ip>:9933`, and subscribe to `diun-updates`. Then apply
updates at your leisure from Arcane — no manual checking.

**4. Outage alerts → ntfy.** Wire Uptime Kuma to ntfy so you hear about
downtime instead of stumbling on it:
- Uptime Kuma → **Settings → Notifications → Setup Notification**
- Type **ntfy**, server `http://ntfy`, topic e.g. `uptime`, priority high → Save
- Edit your monitors (or "Apply on all existing") to use it
- Subscribe to the `uptime` topic in the ntfy app

**5. Backups.** The one piece still to do (parked for your new PC): Proxmox
`vzdump`/PBS for the whole VMs **+** a per-app backup (Kopia/Borgmatic) for
config under `CONFIG_PATH`. Until then, a manual `vzdump` snapshot before big
changes is cheap insurance.
