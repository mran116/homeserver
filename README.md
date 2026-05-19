# 🏠 Homeserver Docker Stack

A complete self-hosted homeserver stack built with Docker Compose and managed via Portainer. Designed for families who want to own their data, reduce reliance on cloud subscriptions, and run a capable home server with minimal ongoing maintenance.

Covers media streaming, household management, photo backup, document storage, password management, budget tracking, private messaging, monitoring, and automation — all self-hosted, all free (or nearly free).

---

## 📋 Prerequisites

Before you start you will need:

- A server or VM running **Ubuntu 22.04+** or **Debian 12+**
- **Docker 24+** and **Docker Compose v2** installed
- **8GB RAM minimum** (16GB+ recommended)
- **Portainer CE** for stack management
- A **GitHub account** for GitOps deployment
- A **private IP address** for your server (e.g. `192.168.1.100`)
- Optional: a domain name for external access via Cloudflare Tunnel (~$10/year)

---

## 🗂️ Directory Structure

```
/opt/docker/
├── stacks/              ← this repo — all compose files
│   ├── portainer/          (will become dockge/)
│   ├── vaultwarden/
│   ├── infrastructure/     (includes borgmatic/ configs)
│   ├── monitoring/
│   ├── dashboard/          (homepage compose + homepage/ configs)
│   ├── mediastack/
│   ├── household/
│   ├── records/
│   ├── cloud/
│   └── automation/
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

### Portainer — Docker Management
Manages all other stacks via a web UI. Deploy this first via SSH — everything else is deployed through Portainer.

| Service | Purpose |
|---|---|
| Portainer CE | Web UI for managing Docker containers, stacks, images, volumes and networks |

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
| Uptime Kuma | Monitors all your services and sends alerts when something goes down. Supports Discord, Telegram, email and more. |
| Dozzle | Real-time Docker log viewer. See logs from all containers in one clean web UI without SSH. |
| Watchtower | Automatically updates all containers to latest images on a nightly schedule. |
| Notifiarr | Sends rich notifications for media stack events — new downloads, import failures, health checks — to Discord/Slack/email. |

---

### Management — Dashboard

| Service | Purpose |
|---|---|
| Homepage | Central dashboard showing all your services with live stats widgets. Single bookmark to access everything. |

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
| Kavita | Book and audiobook server — supports EPUB, PDF, CBZ and more. |
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

### Automation — Workflow Automation

| Service | Purpose |
|---|---|
| n8n* | Self-hosted Zapier alternative. Connects all your services together with automated workflows — e.g. bill arrives by email → logged in Actual Budget, meal planned in Mealie → shopping list updated in KitchenOwl. |

*Commented out — enable after all other stacks are stable.

---

## ⚙️ Environment Variables

All environment variables are managed via **Portainer's environment system** — not committed to this repo.

1. Copy `.env.example` to see every required variable and description
2. Add your values in **Portainer → Environments → your environment → Environment variables**
3. Store actual secrets in **Vaultwarden** for backup and recovery

Never commit `.env` to Git — it is blocked by `.gitignore`.

---

## 🔄 How GitOps Works

This repo is the single source of truth for all stack configurations:

```
Edit compose file locally in VSCode
  → git commit and push to GitHub
    → Portainer detects the change (polling every 5 minutes)
      → Portainer automatically redeploys the stack
        → New config is live
```

To enable auto-updates in Portainer — when adding each stack choose **Repository** and enable **GitOps updates** with a polling interval of 5 minutes.

---

## 🔗 How Stacks Connect

All stacks share a single Docker network called `home`. This allows containers in different stacks to communicate by container name:

```
Unpackerr → calls http://sonarr:8989 (different stack, same network)
Homepage  → calls http://jellyfin:8096 (different stack, same network)
n8n       → calls http://mealie:9000  (different stack, same network)
```

Create the network once before deploying anything:
```bash
docker network create home
```

---

## 🚀 Quick Start

### 1 — Install Docker

```bash
curl -fsSL https://get.docker.com | bash
sudo systemctl enable docker
sudo usermod -aG docker $USER
```

### 2 — Create structure and start Portainer

```bash
# Create shared network
docker network create home

# Create directories
sudo mkdir -p /opt/docker/stacks
sudo mkdir -p /opt/docker/data
sudo mkdir -p /opt/docker/homepage
sudo chown -R $USER:$USER /opt/docker

# Clone repo
git clone https://github.com/mran116/homeserver.git /opt/docker/stacks

# Copy homepage config files
cp -r /opt/docker/stacks/homepage/* /opt/docker/homepage/

# Start Portainer
cd /opt/docker/stacks/portainer
docker compose up -d
```

### 3 — Configure Portainer

Open `http://YOUR_SERVER_IP:9000`

1. Create admin account
2. Go to **Settings → Authentication → Session lifetime** and increase to 8 hours
3. Go to **Environments → your environment → Environment variables**
4. Add all variables from `.env.example` with your values

### 4 — Deploy stacks via Portainer

Go to **Stacks → Add Stack → Repository** for each stack in this order:

1. `vaultwarden` — path: `stacks/vaultwarden/docker-compose.yml`
2. `infrastructure` — path: `stacks/infrastructure/docker-compose.yml`
3. `monitoring` — path: `stacks/monitoring/docker-compose.yml`
4. `dashboard` — path: `stacks/dashboard/docker-compose.yml`
5. `mediastack` — path: `stacks/mediastack/docker-compose.yml`
6. `household` — path: `stacks/household/docker-compose.yml`
7. `records` — path: `stacks/records/docker-compose.yml`
8. `cloud` — path: `stacks/cloud/docker-compose.yml`

---

## 📋 Post-Deploy Setup

### Vaultwarden
- Create your account at `http://YOUR_SERVER_IP:9930`
- Enable 2FA immediately
- Set `VAULTWARDEN_SIGNUPS_ALLOWED=false` in Portainer env vars
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

### Notifiarr
- Sign up free at `notifiarr.com` to get your API key
- Connects arr apps to Discord/Slack/email notifications

### Homepage
- Config files live at `/opt/docker/homepage/`
- Edit `services.yaml` to add API keys for live widget stats
- Edit `widgets.yaml` to add your coordinates for the weather widget
- Changes take effect immediately — no restart needed

---

## 🔓 Enabling Commented Services

### Tailscale — private VPN access
```
1. Get a reusable auth key at: login.tailscale.com/admin/settings/keys
2. Add TS_AUTHKEY to Portainer environment variables
3. Uncomment tailscale in infrastructure/docker-compose.yml
4. Push to GitHub — Portainer auto-redeploys
5. Approve the advertised subnet route in Tailscale admin panel
```

### Cloudflare Tunnel — secure public access, zero open ports
```
1. Buy a domain at cloudflare.com (~$10/year)
2. Zero Trust → Networks → Tunnels → Create tunnel → copy the token
3. Add CLOUDFLARE_TUNNEL_TOKEN to Portainer environment variables
4. Uncomment cloudflared in infrastructure/docker-compose.yml
5. Add hostname routes in the Cloudflare dashboard:
   jellyfin.yourdomain.com    → http://jellyfin:8096
   vaultwarden.yourdomain.com → http://vaultwarden:80
   navidrome.yourdomain.com   → http://navidrome:4533
6. Push to GitHub — Portainer auto-redeploys
```

### Matrix — private encrypted messaging
```
1. Requires a domain and Cloudflare Tunnel first
2. Set MATRIX_SERVER_NAME=yourdomain.com in Portainer environment variables
3. Uncomment synapse in cloud/docker-compose.yml
4. Push to GitHub — Portainer auto-redeploys
5. Add matrix.yourdomain.com to Cloudflare tunnel routes
6. Install the Element app on devices
```

### DocuSeal — legally binding document signing
```
1. Requires a domain and SMTP setup first
2. Set up Cloudflare Email Routing for your domain (free)
3. Add Gmail SMTP credentials to Portainer environment variables
4. Uncomment docuseal in records/docker-compose.yml
5. Push to GitHub — Portainer auto-redeploys
```

### Borgmatic — automated offsite backups
```
1. Create a Backblaze B2 account at backblaze.com (free 10GB, then $6/TB/month)
2. Update infrastructure/borgmatic/config.yaml with your B2 bucket and credentials
3. Add BORG_PASSPHRASE to Portainer environment variables
4. Uncomment borgmatic in infrastructure/docker-compose.yml
5. Push to GitHub — Portainer auto-redeploys
```

### n8n — workflow automation
```
1. Set N8N_USER and N8N_PASSWORD in Portainer environment variables
2. Uncomment n8n in automation/docker-compose.yml
3. Push to GitHub — Portainer auto-redeploys
4. Connect your services via the n8n UI
```

---

## ⚠️ Common Gotchas

**Create the home network first**
All stacks use an external Docker network called `home`. Create it once before deploying anything — stacks will fail to deploy without it:
```bash
docker network create home
```

**Docker API version mismatch**
Watchtower requires the correct Docker API version or it won't start. Check yours with:
```bash
docker version | grep API
```
Update `DOCKER_API_VERSION` in Portainer environment variables to match.

**Portainer session timeout**
By default Portainer logs you out very quickly. Fix it at:
**Settings → Authentication → Session lifetime**


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
- [ ] 2FA enabled on Portainer
- [ ] 2FA enabled on Immich admin
- [ ] `VAULTWARDEN_SIGNUPS_ALLOWED=false` after creating your account
- [ ] NPM SSL certificates configured for local services
- [ ] Tailscale enabled for remote access
- [ ] Cloudflare Tunnel configured for public services only
- [ ] Portainer, Paperless, Actual Budget never exposed publicly
- [ ] Watchtower keeping all containers updated
- [ ] Uptime Kuma monitoring all services with notifications configured

---

## 🛠️ Requirements

- Docker 24+
- Docker Compose v2
- 8GB RAM minimum (16GB+ recommended for Immich ML)
- Ubuntu 22.04+ or Debian 12+
- Portainer CE

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
| Kavita | Kavita | ✅ | ✅ |

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
  │           ├── portainer
  │           ├── vaultwarden
  │           ├── infrastructure (NPM, Tailscale, Cloudflare)
  │           ├── monitoring (Uptime Kuma, Dozzle, Watchtower)
  │           ├── management (Homepage)
  │           ├── mediastack (Jellyfin, Sonarr, Radarr...)
  │           ├── household (Mealie, KitchenOwl, Donetick...)
  │           ├── records (Paperless, Stirling PDF...)
  │           ├── cloud (Immich, Matrix...)
  │           └── automation (n8n...)
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