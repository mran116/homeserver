# 🏠 Homeserver Docker Stack

A complete self-hosted homeserver stack built with Docker Compose and managed via Arcane. Designed for families who want to own their data, reduce reliance on cloud subscriptions, and run a capable home server with minimal ongoing maintenance.

Covers media streaming, household management, photo backup, document storage, password management, budget tracking, private messaging, monitoring, and automation — all self-hosted, all free (or nearly free).

> 🧭 **New to this? Which guide should I read?**
> - **Never run a server before?** → [**The Super Simple Setup Guide**](docs/beginner-guide.md) — plain English, mostly copy-paste, no Linux/Docker knowledge needed.
> - **Comfortable in a terminal, want the fast path?** → the [Quick Start](#-quick-start) below.
> - **Want the manual flow, per-app setup, or troubleshooting?** → [Install & Setup](docs/INSTALL.md).

> 📖 **More docs:** [Beginner guide](docs/beginner-guide.md) · [Install & Setup](docs/INSTALL.md) · [Reference (mobile apps · network · hardware)](docs/REFERENCE.md) · [Remote-access design](docs/network-and-remote-access.md) · [Tailscale](docs/tailscale.md) · [Theming](docs/theming.md) · [Home Assistant (future goal)](docs/HOME-ASSISTANT.md)

---

## 📋 Prerequisites

- A server or VM running **Ubuntu 22.04+** or **Debian 12+**
- **Docker 24+** and **Docker Compose v2**
- **8GB RAM minimum** (16GB+ recommended)
- **Arcane** for stack management
- A **GitHub account** for GitOps deployment
- A **private IP** for your server (e.g. `192.168.1.100`)
- Optional: a domain for external access via Cloudflare Tunnel (~$10/year)

---

## 📦 Stacks

Each top-level folder with a `docker-compose.yml` is **one Arcane stack** (discovered one level deep — intentionally flat). Deploy order is top-to-bottom. Full per-service descriptions: [docs/REFERENCE.md](docs/REFERENCE.md#-stacks-in-detail); directory layout: [docs/INSTALL.md](docs/INSTALL.md#-directory-structure).

| Stack | Services | What it does |
|---|---|---|
| **arcane** | Arcane | Web UI to manage every stack — **deploy first** |
| **vaultwarden** | Vaultwarden | Bitwarden-compatible password manager — **deploy second** |
| **infrastructure** | Caddy\*, AdGuard Home\*, CrowdSec\*, Tailscale\*, Cloudflare Tunnel\*, DDNS\*, Borgmatic\* | The plumbing (all opt-in): clean HTTPS URLs, network-wide ad-blocking, intrusion prevention, secure remote access, dynamic DNS, offsite backups |
| **monitoring** | Uptime Kuma, Dozzle, Diun, ntfy, Pulse\*, Vector\*, Loki/Grafana/Alloy\* | Know the moment something breaks — uptime checks, live logs (Dozzle), image-update alerts (Diun), phone-push hub (ntfy), Proxmox+Docker metrics & alerts (Pulse), optional log retention for lnav (Vector) or full-text search (Loki+Grafana) |
| **dashboard** | Homepage | One launcher with live status widgets |
| **mediastack** | Jellyfin\*/Plex\*, Sonarr/Radarr/Lidarr/Whisparr, Prowlarr, Bazarr, SABnzbd, qBittorrent+Gluetun, Navidrome, Audiobookshelf, Seerr, Recyclarr, Unpackerr, Decluttarr, Flaresolverr, Tdarr\* | Media server + fully automated acquisition, music & audiobooks, family requests |
| **household** | Mealie, Donetick, Actual Budget | Recipes, meal planning & shopping lists, chores, budgeting |
| **fitness** | wger | Workout & fitness tracker (routines, logging, progress charts) |
| **records** | Paperless-ngx, Stirling PDF, DocuSeal\* | Document OCR/search, PDF tools, e-signing |
| **knowledge** | Memos, Karakeep\* | Quick-capture notes; bookmarks/read-later with full-text search |
| **syncthing** | Syncthing | Private peer-to-peer file sync across your devices — your Dropbox replacement |
| **cloud** | Immich | Photo/video backup (Google Photos replacement) |
| **devops** | Gitea + Actions runner | Self-hosted git/CI — *Phase 3 (future)* |

\*Optional / profile-gated — see [Choosing what runs](#-choosing-what-runs).

> Workflow automation is planned for **Home Assistant** (separate VM, a future goal) — see [docs/HOME-ASSISTANT.md](docs/HOME-ASSISTANT.md).

---

## 🚀 Quick Start

### At a glance

```
1. Install Docker                         (one command)
2. Clone the repo to /opt/docker/stacks
3. Run ./bootstrap.sh                      → generates .env, secrets, *arr keys,
                                             dirs, network, symlinks, installs `hs`,
                                             starts Arcane
4. Open Arcane → create admin
5. Start the stacks in order from Arcane   → vaultwarden first, cloud last
                                             (or pick which to run: hs stacks)
6. Create your accounts in each app's UI   (Vaultwarden, Immich, Mealie…)
7. Run hs keys                             → auto-detects *arr keys + collects
                                             UI-only keys, then redeploy consumers
8. Verify on Homepage + Uptime Kuma        → everything green
```

Most people are running in **under an hour**, most of it waiting for containers to pull.

### 🟢 Step-by-step deploy (no Linux or Docker experience needed)

Assumes your server already has **Ubuntu or Debian installed**. Copy-paste a few commands, click a few buttons. At any question, **press Enter for the suggested answer**.

> 📖 Want the gentle, fully-explained version (what each step does, choosing what to install, first logins, troubleshooting)? → [docs/beginner-guide.md](docs/beginner-guide.md).

**1. Get to a terminal on the server** — directly, or over SSH:
```bash
ssh youruser@192.168.1.100
```
> Don't know the address? On the server run `hostname -I` — it's the first one.

**2. Download the project and run the one-time setup:**
```bash
sudo apt update && sudo apt install -y git
sudo mkdir -p /opt/docker && sudo chown -R $USER /opt/docker
git clone https://github.com/mran116/homeserver.git /opt/docker/stacks
cd /opt/docker/stacks
./scripts/setup-fresh.sh
```
`setup-fresh` installs Docker, asks a handful of simple questions (timezone, where to keep data — Enter for defaults), **generates strong passwords**, installs the `hs` command, and starts the control panel.

**3. Open the control panel (Arcane)** at `http://YOUR_SERVER_IP:3552` (e.g. `http://192.168.1.100:3552`). Log in with **`arcane` / `arcane-admin`** and change the password.

**4. Turn on the apps.** In Arcane, click each stack → **Start**, in this order (let the first few finish): `vaultwarden` → `infrastructure` → `monitoring` → `dashboard` → then the rest.
> Don't want some? Run `hs stacks` first to choose which to deploy.

**5. Create your logins.** Your dashboard at `http://YOUR_SERVER_IP:3000` links to every app. **Start with Vaultwarden** and turn on 2FA.

**6. Fill in the dashboard's live data:**
```bash
hs keys
```
It grabs most keys automatically and shows you where to copy the few that must come from an app's web page.

**7. Updating later (anytime, from any directory):**
```bash
hs update
```
Pulls the latest code, applies new settings, and redeploys. Day-to-day you'll also use `hs doctor` (health check) and `hs help`.

### The `hs` command — one entrypoint for everything

After setup, **`hs` wraps every script**, runs from **any directory**, and has consistent flags: `-n/--dry-run`, `-y/--yes`, `-h/--help`. `bootstrap.sh` installs it onto your PATH with tab-completion.

```bash
hs help                          # list every command
hs update                        # pull latest + redeploy (reconciles .env, dirs, cron, hooks)
hs doctor                        # read-only health check — tells you exactly what to fix
hs up | down | restart [stack]   # start / stop / restart all stacks (or one)
hs status [stack]                # docker compose ps
hs logs <stack|container> [-f]   # tail logs
hs stacks                        # choose which stacks deploy
hs env init | sync | tidy        # create / top-up / reformat .env
hs secrets                       # fill blank machine secrets (DB-safe)
hs keys                          # pull app API keys for the dashboard widgets
```

> Full manual walkthrough, per-app post-deploy setup, optional services, and troubleshooting → [docs/INSTALL.md](docs/INSTALL.md).
>
> Deploying on a different box / a media layout that isn't the default (different paths, folder names, or disks)? → [docs/porting-to-your-own-layout.md](docs/porting-to-your-own-layout.md).

---

## 🌐 Two ways to run: with or without a domain

The networking layer (HTTPS, pretty hostnames, public sharing) is **fully optional** — the stack runs great without a domain. Pick your path; you can start with A and add B anytime.

### Path A — No domain (simplest; ideal for a first server)
Nothing to buy or register. Leave `COMPOSE_PROFILES` at its default (no `caddy`).
- **At home:** reach everything at `http://<server-ip>:<port>` — your dashboard (Homepage, `:3000`) links to every app.
- **Away from home:** install **Tailscale** (on your router or any box) for secure remote access to everything by IP — **no domain needed**. Tailscale can even issue valid HTTPS for its own `*.ts.net` names.
- **Worth doing regardless:** `hs enable backup` (offsite backups of irreplaceable data) + Tailscale.
- Want pretty HTTPS URLs later without buying a domain? A **free DuckDNS subdomain** works with Path B's Caddy setup.

### Path B — With a domain (clean HTTPS URLs + public sharing)
Own a domain on **Cloudflare** (~$10/yr), then:
1. Create a scoped **DNS API token** (Zone → DNS → Edit + Zone → Read).
2. Set `DOMAIN`, `CLOUDFLARE_DNS_API_TOKEN`, `ACME_EMAIL` in `.env`.
3. `hs enable caddy` → **one wildcard cert** (`*.yourdomain`) via DNS-01; every service gets `service.yourdomain` over HTTPS automatically.
4. Point internal DNS at the box — a router DNS rewrite/hosts entry, or a public wildcard A record. Full guide: [docs/network-and-remote-access.md](docs/network-and-remote-access.md).
5. Optional: `hs enable tunnel` (public access, zero open ports) · `hs enable ddns` (track a dynamic WAN IP).

**Both paths share the same core stack** — the only difference is the HTTPS/hostname polish.

---

## 🎚️ Choosing what runs

All choices live in your **gitignored** files (`.env`, `.stacks.local`), so they **survive every `git pull`** — you never edit the tracked compose files.

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
| `tdarr` | Tdarr library transcoder |
| `crowdsec` | CrowdSec IDS/IPS |
| `caddy` | Caddy reverse proxy (the only proxy) |
| `adguard` | AdGuard Home DNS (network-wide ad-blocking; only if your router can't run DNS) |
| `metrics` | Pulse — Proxmox + Docker metrics & alerts → ntfy (no cloud/cap) |
| `logs` | Vector → ndjson log files for lnav (featherweight central retention) |
| `logging` | Loki + Grafana + Alloy — heavy indexed full-text log search |
| `karakeep` | Karakeep bookmarks/read-later |

Read **natively by Docker Compose**, so **Arcane, `hs`, and plain `docker compose` all honor it** — set once and it persists. ⚠️ **Include a media server** (`jellyfin` or `plex`) or you'll have none.

### Whole stacks → just deploy the ones you want
A stack is a folder — not deploying it means it's off. No tags needed:
- **Arcane:** deploy only the stacks you want.
- **CLI:** `hs stacks disable <stack>` (remembered in gitignored `.stacks.local`), or `hs up <stack>`.

(`arcane`, `vaultwarden`, and `infrastructure` aren't profile-gated, so they always come up when deployed — your way back in is never accidentally switched off.)

---

## 🎛️ Day-to-Day Management

You already have the tools (Arcane, Homepage, Uptime Kuma, Dozzle, Diun→ntfy, `hs`). A few config-only wins make it lower-effort:

- **Manage from anywhere (Tailscale).** Enable the `vpn` profile, set `TS_AUTHKEY` in `.env`, redeploy, approve the subnet route — Arcane / Homepage / SSH reachable from your phone, no ports opened. (FOSS alternative: Headscale.)
- **Clean local URLs instead of `IP:port`.** AdGuard → DNS rewrites: `*.home` → server IP (where Caddy listens); Caddy then routes each name from container labels, e.g. `jellyfin.home` → `http://jellyfin:8096`.
- **Family "is it up?" page.** Uptime Kuma → Status Pages → publish, and share the link.
- **Bulk operations.** `hs up|down|restart|pull|status` runs across all stacks in the right order.

Each first-run phase is also runnable on its own (all preview-then-apply; `--dry-run`/`--yes`):
```bash
hs doctor          # read-only health check
hs env sync        # append vars added to .env.example in a new version
hs env tidy        # rewrite .env into .env.example's clean structure
hs secrets         # fill any newly-blank machine secret (DB-safe)
hs network         # (re)create the `home` docker network
hs cron            # (re)install the maintenance cron jobs
hs hooks           # (re)install the git pre-push validation hook
```

> **UI edits:** Arcane edits compose files directly in the git tree. If you also develop via PRs, do significant changes in a branch/PR rather than editing live, to avoid `main` diverging from origin.

Low-effort maintenance (log caps, image cleanup, update/outage alerts, backups) → [docs/INSTALL.md](docs/INSTALL.md#-maintenance-set-it-and-forget-it).

---

## 🔒 Security

**What protects you out of the box:**
- **Zero open ports by default.** Nothing is exposed to the internet unless you opt in. Remote access is via **Cloudflare Tunnel** (outbound-only, no port-forwarding) or **Tailscale** (private WireGuard VPN) — your home IP is never exposed.
- **Zero-knowledge password vault.** Vaultwarden is client-side encrypted — the server never sees your passwords, and they can't be reset/recovered by email.
- **Secrets stay local.** All secrets live in a **gitignored `.env`**, never committed; `git pull` never touches them.
- **Private by default.** Services bind to your LAN; AdGuard blocks trackers network-wide; all torrent traffic is forced through a VPN (Gluetun) or won't connect.
- **Update awareness.** Diun alerts on new images (you review before applying); Uptime Kuma watches every service.

**Hardening checklist (do these):**
- [ ] Strong master password **+ 2FA** on Vaultwarden
- [ ] 2FA on Arcane and Immich admin
- [ ] `VAULTWARDEN_SIGNUPS_ALLOWED=false` after creating your account
- [ ] Caddy auto-HTTPS (one `*.${DOMAIN}` wildcard cert via Cloudflare DNS-01) covering local services
- [ ] Tailscale for remote admin; Cloudflare Tunnel for public services only (**never** stream Jellyfin through the tunnel — see below)
- [ ] Arcane, Paperless, Actual Budget never exposed publicly
- [ ] Diun + Uptime Kuma notifications wired up

> Full remote-access & exposure design (tunnel vs. Tailscale vs. direct, and how Jellyfin is served): [docs/network-and-remote-access.md](docs/network-and-remote-access.md).

---

## 🛠️ Requirements

- Docker 24+ · Docker Compose v2
- 8GB RAM minimum (16GB+ recommended for Immich ML)
- Ubuntu 22.04+ or Debian 12+
- Arcane

---

## 🤝 Contributing

Issues and PRs welcome. If you find this useful, give it a ⭐

---

## 📄 License

MIT
