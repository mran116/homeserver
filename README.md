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

```
/opt/docker/
├── stacks/              ← this repo — all compose files
│   ├── arcane/
│   ├── vaultwarden/
│   ├── infrastructure/     (includes borgmatic/ configs)
│   ├── monitoring/
│   ├── dashboard/          (homepage compose + homepage/ configs)
│   ├── mediastack/
│   ├── household/
│   ├── records/
│   ├── cloud/
│   └── devops/
└── data/                ← all app config and data (bind mounts)
    ├── jellyfin/
    ├── sonarr/
    ├── radarr/
    └── etc...

/mnt/media/              ← Movies, TV, music, anime, books
/mnt/photos/             ← Immich photo and video library
/mnt/documents/          ← Paperless document storage
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
| Recommendarr | AI-powered media recommendations based on your Jellyfin watch history. |
| Recyclarr | Automatically syncs TRaSH Guides quality profiles to Sonarr and Radarr. |
| Unpackerr | Automatically extracts completed downloads for Sonarr/Radarr/Lidarr. |
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

### Records — Document Management

| Service | Purpose |
|---|---|
| Paperless-ngx | Scan, store, and search all your important documents. OCR makes everything full-text searchable. Use the mobile app to scan with your phone. |
| Stirling PDF | PDF toolkit — merge, split, compress, convert, and manipulate PDFs directly in the browser. |
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

`.env` is gitignored, so `git pull` never touches your secrets. Never hand-copy these files between machines — always `git pull` so they can't land in the wrong place.

For bulk operations across all stacks, use `scripts/stack.sh`:
```bash
./scripts/stack.sh pull && ./scripts/stack.sh up   # update all images + redeploy
./scripts/stack.sh down                            # stop everything (reverse order)
./scripts/stack.sh status                          # ps for every stack
./scripts/stack.sh restart mediastack              # target a specific stack
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

---

## 🚀 Quick Start

### At a glance

The whole journey, start to finish, so you know where you're headed:

```
1. Install Docker                         (one command)
2. Clone the repo to /opt/docker/stacks
3. Run ./bootstrap.sh                      → generates .env, secrets, *arr keys,
                                             dirs, network, symlinks, starts Arcane
4. Open Arcane → create admin
5. Start the stacks in order from Arcane   → vaultwarden first, cloud last
6. Create your accounts in each app's UI   (Vaultwarden, Immich, Mealie, NPM…)
7. Run ./scripts/harvest-keys.sh           → auto-detects *arr keys + collects UI-only keys, then redeploy consumers
8. Verify on Homepage + Uptime Kuma        → everything green
```

Most people are running in **under an hour**, most of it waiting for containers to pull.

### 1 — Install Docker

```bash
curl -fsSL https://get.docker.com | bash
sudo systemctl enable docker
sudo usermod -aG docker $USER
```

> **Brand-new machine?** After cloning (step 2), `./scripts/setup-fresh.sh` does the whole host setup for a fresh Ubuntu/Debian box: apt update/upgrade + base tools, Docker + compose, Docker log rotation, `qemu-guest-agent` if it's a VM, the docker group, then runs `bootstrap.sh`. You still mount your own media/data disks first, and do the firewall at your router.

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
- seed `dashboard/homepage/*.yaml` into your config dir
- optionally start Arcane

After the apps are up, run `./scripts/harvest-keys.sh`. It **auto-detects** the *arr API keys (Sonarr/Radarr/Lidarr/Whisparr/Prowlarr) straight from each app's generated `config.xml` and writes them to `.env`, then prompts you for the keys that can only come from a UI (Jellyfin, Immich, Mealie, SABnzbd, NPM login, etc.). External tokens (VPN, Tailscale, Cloudflare) are pasted in by hand. Then **redeploy** the consumers (Recyclarr, Unpackerr, Homepage) so they pick up the new keys.

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
2. Arcane auto-discovers every stack under `/opt/docker/stacks` (mapped to `/opt/stacks` inside the container)

### 4 — Deploy stacks via Arcane

In the Arcane UI, start each stack in this order (click → Start). The order matters:

1. `vaultwarden` — your password vault; stand it up first so you have somewhere to store the secrets bootstrap generated
2. `infrastructure` — reverse proxy + networking; other services sit behind it
3. `monitoring` — Uptime Kuma / Dozzle / Diun start watching everything else
4. `dashboard` — Homepage; depends on the rest existing, so it comes after
5. `mediastack`
6. `household`
7. `records`
8. `cloud`

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
./scripts/harvest-keys.sh
```

It first **auto-detects** the *arr keys from each app's generated `config.xml`, then walks the rest (showing the exact URL + click path), prompts once, and writes straight to `.env`. Re-runnable; existing values are skipped unless you pass `--force`.

#### Keeping keys in sync automatically
The *arr keys rarely change, but if you ever regenerate one, you don't want to remember to re-run the script. `--sync` is a non-interactive mode that **detects the *arr keys and, only if one changed, recreates the consumers** (Unpackerr, Recyclarr, Homepage) so they pick up the new value — then exits silently:

```bash
./scripts/harvest-keys.sh --sync
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
- Config source lives in `dashboard/homepage/` (this repo)
- Runtime copy: `/opt/docker/data/homepage/` (bind-mounted into the container)
- Edit `services.yaml` to add API keys for live widget stats
- Edit `widgets.yaml` to add your coordinates for the weather widget
- Changes take effect immediately — no restart needed

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
3. Add CLOUDFLARE_TUNNEL_TOKEN to .env
4. Uncomment cloudflared in infrastructure/docker-compose.yml
5. Add hostname routes in the Cloudflare dashboard:
   jellyfin.yourdomain.com    → http://jellyfin:8096
   vaultwarden.yourdomain.com → http://vaultwarden:80
   navidrome.yourdomain.com   → http://navidrome:4533
6. Push, `git pull` on host, redeploy in Arcane
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
- Intel CPU with Quick Sync (most efficient)
- Or NVIDIA GPU with NVENC support
- Uncomment the hardware transcoding section in `mediastack/docker-compose.yml`

### Wall tablet
- Any Android tablet with Fully Kiosk Browser (~$7)
- Or iPad with Guided Access (built-in, free)
- Minimum 10" screen recommended for readability