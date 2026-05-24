# 🏠 Homeserver Docker Stack

A complete self-hosted homeserver stack built with Docker Compose and managed via Arcane. Designed for families who want to own their data, reduce reliance on cloud subscriptions, and run a capable home server with minimal ongoing maintenance.

Covers media streaming, household management, photo backup, document storage, password management, budget tracking, private messaging, monitoring, and automation — all self-hosted, all free (or nearly free).

---

## 📋 Prerequisites

Before you start you will need:

- A server or VM running **Ubuntu 22.04+** or **Debian 12+**
- **Docker 24+** and **Docker Compose v2** installed
- **8GB RAM minimum** (16GB+ recommended)
- **Arcane** for stack management
- A **GitHub account** for GitOps deployment
- A **private IP address** for your server (e.g. `192.168.1.100`)
- Optional: a domain name for external access via Cloudflare Tunnel (~$10/year)

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

## 📦 Stacks

### Arcane — Stack Manager
Compose-native stack manager. Deploy this first via SSH — every other stack is then managed through Arcane's UI, which reads and writes the compose files in this repo directly (no drift between UI and git).

| Service | Purpose |
|---|---|
| Arcane | Web UI for managing Docker compose stacks. Edits the same files you commit to git. |

---

### Vaultwarden — Password Manager
Deploy this second. Stores all secrets and API keys used across the rest of the stack. Uses the official Bitwarden app ecosystem.

| Service | Purpose |
|---|---|
| Vaultwarden | Self-hosted Bitwarden-compatible password manager. Client-side encrypted — server never sees your passwords. Use the official Bitwarden app on all devices. |

---

### Infrastructure — Networking and Access

| Service | Purpose |
|---|---|
| Nginx Proxy Manager | Reverse proxy with SSL certificate management. Gives all services clean local URLs and HTTPS. |
| AdGuard Home | Network-wide DNS ad/tracker blocking for every device, plus local DNS rewrites for clean hostnames. Point your router's DNS here. |
| Syncthing | Private peer-to-peer file sync across your PCs and phones — your Dropbox replacement, no cloud, no database. |
| ntfy | Self-hosted push-notification hub — POST from Proxmox, cron, scripts or the *arr stack and get a push on your phone. |
| Tailscale* | Zero-config VPN built on WireGuard. Gives secure remote access to your entire home network from anywhere. |
| Cloudflare Tunnel* | Exposes selected services publicly with zero open ports on your router. Works with a custom domain. |
| Borgmatic* | Automated encrypted offsite backups to Backblaze B2 or any remote storage. |

*Commented out — enable when ready.

---

### Monitoring — Observability

| Service | Purpose |
|---|---|
| Uptime Kuma | Heartbeat monitor for every service. Home Assistant reads this via the Uptime Kuma integration so "is X up?" surfaces on the family HA dashboard. |
| Dozzle | Real-time Docker log viewer. Debugging tool — opened only when something is already known broken. |
| Diun | Docker Image Update Notifier. Watches every running container and notifies (via Home Assistant webhook) when a new image is published. Does not auto-apply — pair with Arcane for one-click updates. |

---

### Dashboard

| Service | Purpose |
|---|---|
| Homepage | Service launcher with live stats widgets. Single bookmark to reach everything. Health alerting lives in Home Assistant — Homepage is a launcher, not an alert console. |

---

### DevOps
Empty placeholder for self-hosted developer tooling (Gitea + Actions runner) — populated in Phase 3.

---

### Mediastack — Media Server

| Service | Purpose |
|---|---|
| Jellyfin | Media server — stream movies, TV, music, and books to any device. |
| Sonarr | TV show manager — monitors RSS feeds, grabs new episodes automatically. |
| Radarr | Movie manager — monitors and automatically downloads movies. |
| Lidarr | Music manager — monitors and automatically downloads music. |
| Whisparr | Adult content manager. |
| Prowlarr | Indexer manager — connects Sonarr/Radarr/Lidarr to torrent and usenet indexers. |
| Bazarr | Subtitle automation — automatically downloads subtitles for all your media. |
| SABnzbd | Usenet download client. |
| qBittorrent | Torrent download client — routes through Gluetun VPN. |
| Gluetun | VPN container — all torrent traffic routes through this for privacy. |
| Navidrome | Dedicated music server — compatible with all Subsonic/Airsonic apps. |
| Audiobookshelf | Audiobook, podcast and ebook server — with native iOS and Android apps. |
| Seerr | Family media requests — family members search and request movies and shows without needing access to Radarr or Sonarr. You get notified, Radarr/Sonarr grabs it automatically, and it appears in Jellyfin. Essential for families. |
| Recyclarr | Automatically syncs TRaSH Guides quality profiles to Sonarr and Radarr. |
| Unpackerr | Automatically extracts completed downloads for Sonarr/Radarr/Lidarr. |
| Decluttarr | Headless queue cleaner — removes stalled, failed, slow, or orphaned downloads (torrents **and** usenet) and has the *arr grab an alternative. No babysitting the queue. |
| Flaresolverr | Cloudflare bypass for Prowlarr indexers that require it. |

---

### Household — Family Management

| Service | Purpose |
|---|---|
| Mealie | Recipe manager and meal planner — paste any URL to import recipes, plan weekly meals, auto-generate shopping lists. |
| KitchenOwl | Shopping list manager with real-time family sync and a great mobile app. Receives shopping lists from Mealie. |
| Donetick | Chore and task manager with recurring schedules, family member assignment, and points/rewards for kids. |
| Actual Budget | Local-first budget and finance tracker. Connect your bank via SimpleFIN ($15/yr) for automatic transaction sync. |

---

### Fitness — Workout Tracking

| Service | Purpose |
|---|---|
| wger | Self-hosted workout & fitness tracker — routines, set/rep/weight logging, body-weight and progress charts, a filterable exercise database, optional nutrition. Dumbbells are first-class (filter the exercise DB by "Dumbbell"); for resistance bands, add custom exercises and log reps (band level in notes), since wger has no native "band tension" metric. Runs as web + nginx + Postgres + Redis + Celery. |

After deploy, register the first account, then (optionally) populate the exercise database immediately instead of waiting for the periodic sync: `docker exec wger python3 manage.py sync-exercises`.

---

### Records — Document Management

| Service | Purpose |
|---|---|
| Paperless-ngx | Scan, store, and search all your important documents. OCR makes everything full-text searchable. Use the mobile app to scan with your phone. |
| Stirling PDF | PDF toolkit — merge, split, compress, convert, and manipulate PDFs directly in the browser. |
| Memos | Frictionless quick-capture notes — markdown + tags for "remember this" without ceremony. |
| DocuSeal* | Legally binding document signing (ESIGN/UETA/eIDAS compliant). Self-hosted DocuSign alternative. Requires SMTP. |

*Commented out — enable when ready.

---

### Cloud — Private Cloud Storage

| Service | Purpose |
|---|---|
| Immich | Self-hosted Google Photos replacement. Backs up photos and videos from all family phones automatically. Face recognition, shared albums, timeline view, and a great mobile app. |
| Matrix/Synapse* | Private end-to-end encrypted messaging server. Use the Element app. Perfect for private family communication. |

*Commented out — enable when ready.

---

### Automation
Workflow automation lives in **Home Assistant** (separate VM), not in this Docker host. HA integrates natively with Sonarr/Radarr/Jellyfin/Mealie/KitchenOwl/Donetick/Immich/Uptime Kuma, so cross-service automations (and notifications) are built there.

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

> **`hs` is the single entrypoint** for every script. It runs from any directory
> (no `cd`); run `hs install` once to put it on your PATH, then `hs help` lists
> everything. The `./scripts/*.sh` files still work directly, but `hs <command>`
> is the intended way.

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

- **Global** — needed by (nearly) every stack: `SERVER_IP`, `TZ`, `PUID`, `PGID`, `CONFIG_PATH` (plus that stack's own path var: `MEDIA_PATH`, `PHOTOS_PATH`, `DOCS_PATH`, `SYNC_PATH`, `INCOMPLETE_PATH`).
- **The dashboard (Homepage) couples to everything.** It re-reads *every* `*_PORT` and most app keys/logins (forwarded as `HOMEPAGE_VAR_*`) to build its tiles and widgets. So a split-out dashboard still needs all of those, and any app stack you move keeps its port/keys read by wherever the dashboard runs.
- **Shared between two real app stacks:** `APP_USERNAME`, `APP_PASSWORD`, `SABNZBD_API_KEY`, `SONARR_API_KEY`, `RADARR_API_KEY`, `LIDARR_API_KEY` are used by **both** the dashboard widgets **and** the mediastack itself (qBittorrent + decluttarr/unpackerr/recyclarr) — so a standalone mediastack needs them too. The remaining widget keys are dashboard-only.
- **Single-stack** (only the owning stack uses it): DB passwords, JWT/secret keys, VPN/WireGuard keys, Arcane keys, and remote-access tokens (Tailscale/Cloudflare).

---

## 🚀 Quick Start

### At a glance

The whole journey, start to finish, so you know where you're headed:

```
1. Install Docker                         (one command)
2. Clone the repo to /opt/docker/stacks
3. Run ./bootstrap.sh                      → generates .env, secrets, *arr keys,
                                             dirs, network, symlinks, installs `hs`,
                                             starts Arcane
4. Open Arcane → create admin
5. Start the stacks in order from Arcane   → vaultwarden first, cloud last
                                             (or pick which to run: hs stacks)
6. Create your accounts in each app's UI   (Vaultwarden, Immich, Mealie, NPM…)
7. Run hs keys                             → auto-detects *arr keys + collects
                                             UI-only keys, then redeploy consumers
8. Verify on Homepage + Uptime Kuma        → everything green
```

Most people are running in **under an hour**, most of it waiting for containers to pull.

### 🟢 Step-by-step deploy (no Linux or Docker experience needed)

This assumes your server already has **Ubuntu or Debian installed**. You'll
copy-paste a few commands and click a few buttons — that's it. At any question,
**press Enter to accept the suggested answer**.

**1. Get to a terminal on the server.** Either use the machine directly, or from
your own PC open a terminal and connect over SSH (use your server's address):
```bash
ssh youruser@192.168.1.100
```
> Don't know the address? On the server run `hostname -I` — it's the first one.

**2. Download the project and run the one-time setup.** Copy-paste this whole block:
```bash
sudo apt update && sudo apt install -y git
sudo mkdir -p /opt/docker && sudo chown -R $USER /opt/docker
git clone https://github.com/mran116/homeserver.git /opt/docker/stacks
cd /opt/docker/stacks
./scripts/setup-fresh.sh
```
`setup-fresh` installs Docker and everything it needs, asks a handful of simple
questions (timezone, where to keep data — just press Enter for the defaults),
**generates strong passwords for you**, installs the `hs` command, and starts the
control panel. This takes a few minutes.

**3. Open the control panel (Arcane).** In a web browser go to
`http://YOUR_SERVER_IP:3552` (e.g. `http://192.168.1.100:3552`). Log in with
**`arcane` / `arcane-admin`** and change the password when prompted.

**4. Turn on the apps.** Arcane shows each "stack" (a group of related apps).
Click each and press **Start**, in this order (let the first few finish first):
`vaultwarden` → `infrastructure` → `monitoring` → `dashboard` → then the rest
(`mediastack`, `household`, `records`, `knowledge`, `syncthing`, `cloud`).
> Don't want some of them? Run `hs stacks` first to choose which to deploy.

**5. Create your logins.** Your dashboard at `http://YOUR_SERVER_IP:3000` links to
every app. Open each and create your account — **start with Vaultwarden** (your
password manager) and turn on 2-factor.

**6. Fill in the dashboard's live data.** Back in the terminal, run:
```bash
hs keys
```
It grabs most keys automatically and shows you exactly where to copy the few that
must come from an app's web page. Done.

**7. Updating later (do this anytime).** To get the newest version, just run —
from any directory, no `git` commands needed:
```bash
hs update
```
It pulls the latest code, applies any new settings, and redeploys for you. The
only other commands you'll need day-to-day: `hs doctor` (checks health and tells
you exactly what to fix) and `hs help` (lists everything).

### The `hs` command — one entrypoint for everything

After setup you don't call the individual scripts — **`hs` wraps them all**, runs
from **any directory**, and has consistent flags everywhere: `-n/--dry-run`
(preview), `-y/--yes` (no prompt), `-h/--help`. `bootstrap.sh` installs it
(`hs install` symlinks it onto your PATH and adds tab-completion).

```bash
hs help                          # list every command
hs update                        # pull latest + redeploy (reconciles .env, dirs, cron, hooks)
hs doctor                        # read-only health check — tells you exactly what to fix
hs up | down | restart [stack]   # start / stop / restart all stacks (or one)
hs status [stack]                # docker compose ps
hs logs <stack|container> [-f]   # tail logs
hs stacks                        # choose which stacks deploy (exclude apps you don't run)
hs env init | sync | tidy        # create / top-up / reformat .env
hs secrets                       # fill blank machine secrets (DB-safe)
hs keys                          # pull app API keys for the dashboard widgets
```

`hs update` keeps the box matching the repo on every run — it tops up new `.env`
vars, fills blank secrets, re-applies cron/hooks if you've set them up, and asks
about any **new** stacks before redeploying. `hs doctor` is read-only and, for
each problem, prints the exact `hs` command to fix it.

### Detailed walkthrough (manual install, or what the easy path automates)

*The numbered steps below are the same flow, broken down — handy for a manual
install or to understand what `setup-fresh` did for you. If you used the
beginner walkthrough above and it worked, skip ahead to **Post-Deploy Setup**.*

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

## 🎚️ Choosing what runs

All choices live in your **gitignored** files (`.env`, `.stacks.local`), so they
**survive every `git pull`** — you never edit the tracked compose files.

### Optional services + your media server → `COMPOSE_PROFILES` in `.env`
Profile-gated services are **off until you list their profile**. Set a comma-list:
```
COMPOSE_PROFILES=jellyfin,tunnel
```
| Profile | Turns on |
|---|---|
| `jellyfin` | Jellyfin media server *(pick this **or** `plex`)* |
| `plex` | Plex media server |
| `tunnel` | cloudflared (Cloudflare Tunnel) |
| `backup` | borgmatic offsite backups |
| `vpn` | tailscale |
| `ddns` | cloudflare-ddns (direct Jellyfin A record) |
| `matrix` | Synapse (Matrix) |

It's read **natively by Docker Compose**, so **Arcane, `hs`, and plain `docker
compose` all honor it** — set it once and it persists. ⚠️ **Include a media
server** (`jellyfin` or `plex`) or you'll have none.

### Whole stacks → just deploy the ones you want
A stack is a folder — not deploying it means it's off. No tags needed:
- **Arcane:** deploy only the stacks you want.
- **CLI:** `hs stacks disable <stack>` (remembered in gitignored `.stacks.local`), or `hs up <stack>`.

(`arcane`, `vaultwarden`, and `infrastructure` aren't profile-gated, so they always
come up when deployed — your way back in is never accidentally switched off.)

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
dynamic IP) or over Tailscale. Full design: docs/network-and-remote-access.md
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

## ⚠️ Common Gotchas

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

**SABnzbd scratch belongs on a fast local disk (especially with a NAS)**
SAB's incomplete folder is where par2 verify/repair and unpack happen — heavy random I/O that **stalls and corrupts over a network mount**. So `MEDIA_PATH` on a NAS will give you slow, freezing, or wedged repairs. Point SAB's scratch at `INCOMPLETE_PATH` (a local SSD/NVMe, default `/opt/docker/incomplete`, mounted into SAB as `/incomplete`) and set **SAB → Config → Folders → "Temporary (incomplete) folder" = `/incomplete`**. Leave the **Completed folder on `/data/usenet`** (the NAS) so the *arr still hardlink imports into the library — they need no access to the scratch disk. A backup usenet provider on a different backbone also cuts repairs (fills missing articles instead of reconstructing).

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

---

## 🎛️ Day-to-Day Management

You already have the tools (Arcane, Homepage, Uptime Kuma, Dozzle, Diun→ntfy,
`scripts/stack.sh`). A few config-only wins make running it lower-effort:

**Manage it from anywhere (Tailscale).** Enable the commented Tailscale block in
`infrastructure/docker-compose.yml`, set `TS_AUTHKEY` in `.env`
(login.tailscale.com → Settings → Keys), redeploy, and approve the subnet route
in the Tailscale admin. Now Arcane / Homepage / SSH are reachable from your phone
anywhere — no ports opened. (FOSS alternative: Headscale.)

**Clean local URLs instead of `IP:port`.** Two steps:
1. AdGuard → **Filters → DNS rewrites**: add `*.home` → your server IP.
2. NPM → **Hosts → Proxy Hosts → Add**: e.g. `jellyfin.home` → `http://jellyfin:8096`.
Repeat per service. Now it's `jellyfin.home`, `paperless.home`, etc.

**Family "is it up?" page.** Uptime Kuma → **Status Pages → New** → add your
monitors → publish. Share the link so the household can self-check instead of
asking you.

**Bulk operations.** `hs up|down|restart|pull|status` runs across
all stacks in the right order — handy after a Diun update alert (`pull` then
`up`) or for clean host-maintenance stop/start.

**Targeted setup steps (live stack).** `hs setup` is the first-run orchestrator,
but each phase is also runnable on its own without triggering the rest. Every one
**previews then asks to apply** (`--dry-run` to only preview, `--yes` for
automation):

```bash
hs doctor          # read-only health check — what's wrong before you deploy
hs env sync        # append vars added to .env.example in a new version
hs env tidy        # rewrite .env into .env.example's clean structure
hs secrets         # fill any newly-blank machine secret (DB-safe)
hs network         # (re)create the `home` docker network
hs cron            # (re)install the maintenance cron jobs
hs hooks           # (re)install the git pre-push validation hook
```

(`link-env` and `make-dirs` aren't separate commands — they run automatically
inside `hs update`.)

`env-rebuild.sh` reflows `.env` to mirror `.env.example`'s sections/order while
keeping your values; vars you added that aren't in the template are preserved in
a trailing `LOCAL EXTRAS` block. It shows a diff and backs up first.

> **Note on UI edits:** Arcane edits compose files directly in the git tree on
> the host. If you also develop via PRs, do significant changes in a branch/PR
> rather than editing live on the host, to avoid `main` diverging from origin.

---

## 🔒 Security Checklist

- [ ] Strong master password on Vaultwarden
- [ ] 2FA enabled on Vaultwarden
- [ ] 2FA enabled on Arcane
- [ ] 2FA enabled on Immich admin
- [ ] `VAULTWARDEN_SIGNUPS_ALLOWED=false` after creating your account
- [ ] NPM SSL certificates configured for local services
- [ ] Tailscale enabled for remote access
- [ ] Cloudflare Tunnel configured for public services only
- [ ] Arcane, Paperless, Actual Budget never exposed publicly
- [ ] Diun notifying on image updates (manual review before applying)
- [ ] Uptime Kuma monitoring all services with notifications configured

---

## 🛠️ Requirements

- Docker 24+
- Docker Compose v2
- 8GB RAM minimum (16GB+ recommended for Immich ML)
- Ubuntu 22.04+ or Debian 12+
- Arcane

---

## 🤝 Contributing

Issues and PRs welcome. If you find this useful, give it a ⭐

---

## 📄 License

MIT

---

## 🏡 Home Assistant Integration

Home Assistant runs separately on **Home Assistant OS** (not in this Docker stack) and acts as the smart home brain and family wall dashboard. It connects to many services in this stack to display everything in one place.

### What HA connects to from this stack

| Service | HA Integration | What you get |
|---|---|---|
| Jellyfin | HACS — Jellyfin integration | Media player card, now playing, playback control |
| Navidrome | HACS — Navidrome integration | Music player card, currently playing |
| Mealie | HACS — Mealie integration | Meal plan card, recipe count |
| KitchenOwl | HACS — KitchenOwl integration | Shopping list on dashboard |
| Donetick | HACS — Donetick integration | Chore list, tasks due today |
| Google Calendar | Built-in | Family and shared calendars on dashboard |

### Recommended HACS frontend cards for wall tablet

| Card | Purpose |
|---|---|
| Atomic Calendar Revive | Beautiful calendar card — color-coded calendars, agenda view |
| Mushroom Cards | Modern, clean card designs for all your dashboard widgets |
| Kiosk Mode | Hides HA header and sidebar for a clean full-screen tablet display |

### Wall tablet setup

For a wall-mounted family dashboard running Home Assistant:

1. Install HACS — see [hacs.xyz](https://hacs.xyz) for instructions
2. Install Atomic Calendar Revive, Mushroom Cards, and Kiosk Mode via HACS
3. Connect Google Calendar integration — Settings → Devices & Services → Add Integration → Google Calendar
4. Connect Mealie, KitchenOwl, and Donetick via HACS integrations
5. Build your dashboard — Settings → Dashboards
6. Enable Kiosk Mode for full-screen display
7. Use **Fully Kiosk Browser** (Android) or **Guided Access** (iOS) to lock the tablet to the dashboard

### Recommended HA add-ons

| Add-on | Purpose |
|---|---|
| Terminal & SSH | Required for HACS installation |
| Music Assistant | Connects Navidrome and other music sources to HA media players |
| Studio Code Server | Edit HA config files from the browser |

### Household automations (proactive nudges + alerts)

Ready-made HA packages live in [`reference/home-assistant/`](reference/home-assistant/) — copy them
to your HA VM's `/config/packages/` to turn Donetick / Mealie / KitchenOwl /
Calendar into morning briefings, chore digests, bin/meal/shopping reminders, and
to route Diun + Uptime Kuma into a single alert stream. See
[`reference/home-assistant/README.md`](reference/home-assistant/README.md) for setup.

---

## 📱 Mobile Apps

One app per service — install these on family devices:

| App | Service | iOS | Android |
|---|---|---|---|
| Bitwarden | Vaultwarden | ✅ | ✅ |
| Immich | Immich | ✅ | ✅ |
| KitchenOwl | KitchenOwl | ✅ | ✅ |
| Jellyseerr | Seerr | ✅ | ✅ |
| Jellyfin | Jellyfin | ✅ | ✅ |
| Element | Matrix | ✅ | ✅ |
| Paperless-ngx | Paperless | ✅ | ✅ |
| Home Assistant | Home Assistant | ✅ | ✅ |
| Navidrome (Substreamer) | Navidrome | ✅ | ✅ |
| Audiobookshelf | Audiobookshelf | ✅ | ✅ |

> **Family media workflow:** Kid wants a movie → opens Jellyseerr app → searches and requests it → Radarr grabs it automatically → appears in Jellyfin. Nobody needs access to Radarr or Sonarr except you.

> **Tip:** For Bitwarden, Immich, and Jellyfin — point the server URL to your Cloudflare Tunnel domain for access outside your home network.

---

## 🌐 Network Architecture

```
Internet
  │
  ├── Cloudflare Tunnel (zero open ports)
  │     ├── jellyfin.yourdomain.com    → Jellyfin
  │     ├── vaultwarden.yourdomain.com → Vaultwarden
  │     └── navidrome.yourdomain.com   → Navidrome
  │
  └── Tailscale VPN (private access)
        └── Full access to 192.168.1.0/24
              ├── All Docker services
              ├── Home Assistant
              ├── NAS/storage
              └── Any other local device

Local Network (192.168.1.0/24)
  │
  ├── Server (192.168.1.x)
  │     └── Docker home network
  │           ├── arcane
  │           ├── vaultwarden
  │           ├── infrastructure (NPM, Tailscale, Cloudflare, Borgmatic)
  │           ├── monitoring (Uptime Kuma, Dozzle, Diun)
  │           ├── dashboard (Homepage)
  │           ├── mediastack (Jellyfin, Sonarr, Radarr...)
  │           ├── household (Mealie, KitchenOwl, Donetick...)
  │           ├── records (Paperless, Stirling PDF...)
  │           ├── cloud (Immich, Matrix...)
  │           └── devops (Gitea + Actions — Phase 3)
  │
  ├── Home Assistant OS (separate device or VM)
  │     └── Wall tablet dashboard
  │
  └── NAS (optional)
        ├── /photos  → Immich library
        ├── /docs    → Paperless storage
        └── /media   → Jellyfin library
```

---

## 💻 Hardware Recommendations

### Minimum (basic media + household)
- CPU: 4 core (Intel/AMD)
- RAM: 8GB
- Storage: 500GB SSD for OS + app data
- Media: External drive or NAS

### Recommended (full stack including Immich ML)
- CPU: 8 core with AES-NI support
- RAM: 16GB+
- Storage: 500GB SSD for OS + app data
- Media: NAS with RAID for redundancy

### For Jellyfin hardware transcoding
GPU config is **host-specific**, so it lives in a gitignored
`mediastack/docker-compose.override.yml` (not the tracked compose) — that keeps
`git pull` clean on every machine. Enable it once per host:
```bash
cp mediastack/docker-compose.override.yml.example mediastack/docker-compose.override.yml
# edit it: uncomment your GPU block (Intel QSV or NVIDIA NVENC)
```
- **Intel Quick Sync:** uncomment the Intel block, set `RENDER_GID` in `.env`
  (`getent group render | cut -d: -f3`), pick QSV in Jellyfin.
- **NVIDIA NVENC:** uncomment the NVIDIA block (needs the NVIDIA Container
  Toolkit on the host), pick NVENC in Jellyfin.
- **No GPU:** leave it commented — Jellyfin uses software transcoding.

`hs up` and `hs update` auto-include the override when present, so no
tracked file changes and no vendor lock-in. (Jellyfin also mounts the whole media
root at `/data`, so any folder layout works — add libraries in the UI.)

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

### Wall tablet
- Any Android tablet with Fully Kiosk Browser (~$7)
- Or iPad with Guided Access (built-in, free)
- Minimum 10" screen recommended for readability