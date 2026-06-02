# 📚 Reference

> 📖 **Docs:** [README](../README.md) · [Install & Setup](INSTALL.md) · [Remote-access design](network-and-remote-access.md) · [Home Assistant](HOME-ASSISTANT.md)

Look-up material that doesn't belong in the install flow: per-service stack
detail, the mobile apps per service, the network diagram, and hardware specs.

> Home Assistant integration is a **future goal** and lives in its own doc:
> [HOME-ASSISTANT.md](HOME-ASSISTANT.md).

## Contents
- [Stacks in detail](#-stacks-in-detail) (per-service descriptions)
- [Mobile Apps](#-mobile-apps)
- [Network Architecture](#-network-architecture)
- [Hardware Recommendations](#-hardware-recommendations)

---

## 📦 Stacks in detail

Per-service descriptions for every stack. The README has the [compact overview](../README.md#-stacks); this is the full breakdown.

### Arcane — Stack Manager
Compose-native stack manager. Deploy this first via SSH — every other stack is then managed through Arcane's UI, which reads and writes the compose files in this repo directly (no drift between UI and git).

| Service | Purpose |
|---|---|
| Arcane | Web UI for managing Docker compose stacks. Edits the same files you commit to git. |

### Vaultwarden — Password Manager
Deploy this second. Stores all secrets and API keys used across the rest of the stack. Uses the official Bitwarden app ecosystem.

| Service | Purpose |
|---|---|
| Vaultwarden | Self-hosted Bitwarden-compatible password manager. Client-side encrypted — server never sees your passwords. Use the official Bitwarden app on all devices. |

### Infrastructure — Networking and Access

| Service | Purpose |
|---|---|
| Caddy* | Reverse proxy with automatic HTTPS (one `*.${DOMAIN}` wildcard cert via Cloudflare DNS-01). Gives all services clean local URLs and HTTPS. The only proxy. |
| AdGuard Home* | Network-wide DNS ad/tracker blocking for every device, plus local DNS rewrites for clean hostnames. Point your router's DNS here. Enable only if your router can't run DNS. |
| CrowdSec* | Collaborative intrusion detection/prevention — parses logs for attacks and bans offenders via a host firewall bouncer. |
| Tailscale* | Zero-config VPN built on WireGuard. Gives secure remote access to your entire home network from anywhere. |
| Cloudflare Tunnel* | Exposes selected services publicly with zero open ports on your router. Works with a custom domain. |
| DDNS* | Dynamic-DNS updater — keeps a domain's A record pointed at your dynamic WAN IP. |
| Borgmatic* | Automated encrypted offsite backups to Backblaze B2 or any remote storage. |

*Profile-gated/optional — enable when ready (every service in this stack is opt-in via `COMPOSE_PROFILES`).

### Monitoring — Observability

| Service | Purpose |
|---|---|
| Uptime Kuma | Heartbeat monitor for every service. Home Assistant reads this via the Uptime Kuma integration so "is X up?" surfaces on the family HA dashboard. |
| Dozzle | Real-time Docker log viewer. Debugging tool — opened only when something is already known broken. |
| Diun | Docker Image Update Notifier. Watches every running container and notifies when a new image is published. Does not auto-apply — pair with Arcane for one-click updates. |
| ntfy | Self-hosted push-notification hub — POST from Proxmox, cron, scripts or the *arr stack and get a push on your phone (Diun, Uptime Kuma, and the mount/SAB watchdogs all publish here). |
| Pulse* | Proxmox + Docker metrics and alerts to ntfy (no cloud, no cap). See [observability.md](observability.md). |
| Vector* | Ships container logs to ndjson files for lightweight central retention, read with lnav. |
| Loki + Grafana + Alloy* | Heavy indexed full-text log search — collects all container + host logs into Loki, browsed in Grafana. |

*Profile-gated/optional — enable when ready.

### Dashboard

| Service | Purpose |
|---|---|
| Homepage | Service launcher with live stats widgets. Single bookmark to reach everything. |

### Mediastack — Media Server

> 🎬 Wiring it up (Prowlarr → *arr → downloaders → root folders) is the fiddliest
> setup in the stack — see **[mediastack-setup.md](mediastack-setup.md)**.

| Service | Purpose |
|---|---|
| Jellyfin / Plex | Media server — stream movies, TV, music, and books to any device. Pick one via `COMPOSE_PROFILES`. |
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
| Tdarr* | Library transcoder — re-encodes to HEVC/x265 (and AV1) to reclaim disk space. Off by default; see [INSTALL.md](INSTALL.md#-hardware-transcoding-tdarr--the-override-file). |

### Household — Family Management

| Service | Purpose |
|---|---|
| Mealie | Recipe manager and meal planner — paste any URL to import recipes, plan weekly meals, and manage shopping lists with real-time family sync. |
| Donetick | Chore and task manager with recurring schedules, family member assignment, and points/rewards for kids. |
| Actual Budget | Local-first budget and finance tracker. Connect your bank via SimpleFIN ($15/yr) for automatic transaction sync. |

### Fitness — Workout Tracking

| Service | Purpose |
|---|---|
| wger | Self-hosted workout & fitness tracker — routines, set/rep/weight logging, body-weight and progress charts, a filterable exercise database, optional nutrition. Dumbbells are first-class (filter the exercise DB by "Dumbbell"); for resistance bands, add custom exercises and log reps (band level in notes), since wger has no native "band tension" metric. Runs as web + nginx + Postgres + Redis + Celery. |

After deploy, register the first account, then (optionally) populate the exercise database immediately instead of waiting for the periodic sync: `docker exec wger python3 manage.py sync-exercises`.

### Records — Document Management

| Service | Purpose |
|---|---|
| Paperless-ngx | Scan, store, and search all your important documents. OCR makes everything full-text searchable. Use the mobile app to scan with your phone. |
| Stirling PDF | PDF toolkit — merge, split, compress, convert, and manipulate PDFs directly in the browser. |
| DocuSeal* | Legally binding document signing (ESIGN/UETA/eIDAS compliant). Self-hosted DocuSign alternative. Requires SMTP. (Commented-out template in `records/docker-compose.yml`.) |

### Knowledge — Notes and Bookmarks

| Service | Purpose |
|---|---|
| Memos | Frictionless quick-capture notes — markdown + tags for "remember this" without ceremony. |
| Karakeep* | Bookmarks / read-later with full-text search and automatic archiving (formerly Hoarder). |

### Syncthing — File Sync

| Service | Purpose |
|---|---|
| Syncthing | Private peer-to-peer file sync across your PCs and phones — your Dropbox replacement, no cloud, no database. |

### Cloud — Private Cloud Storage

| Service | Purpose |
|---|---|
| Immich | Self-hosted Google Photos replacement. Backs up photos and videos from all family phones automatically. Face recognition, shared albums, timeline view, and a great mobile app. |

### DevOps
Empty placeholder for self-hosted developer tooling (Gitea + Actions runner) — populated in Phase 3.

\*Optional / profile-gated — see [Choosing what runs](../README.md#-choosing-what-runs).

---

## 📱 Mobile Apps

One app per service — install these on family devices:

| App | Service | iOS | Android |
|---|---|---|---|
| Bitwarden | Vaultwarden | ✅ | ✅ |
| Immich | Immich | ✅ | ✅ |
| Mealie | Mealie | ✅ | ✅ |
| Jellyseerr | Seerr | ✅ | ✅ |
| Jellyfin | Jellyfin | ✅ | ✅ |
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
  │           ├── infrastructure (Caddy, AdGuard, CrowdSec, Tailscale, Cloudflare, Borgmatic)
  │           ├── monitoring (Uptime Kuma, Dozzle, Diun, ntfy, Pulse...)
  │           ├── dashboard (Homepage)
  │           ├── mediastack (Jellyfin, Sonarr, Radarr...)
  │           ├── household (Mealie, Donetick...)
  │           ├── fitness (wger)
  │           ├── records (Paperless, Stirling PDF...)
  │           ├── knowledge (Memos, Karakeep)
  │           ├── syncthing
  │           ├── cloud (Immich)
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

> Full remote-access design (Cloudflare Tunnel vs. Tailscale vs. direct, and how
> Jellyfin is served): [`network-and-remote-access.md`](network-and-remote-access.md).

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

### Wall tablet
- Any Android tablet with Fully Kiosk Browser (~$7)
- Or iPad with Guided Access (built-in, free)

> Hardware transcoding (Intel QSV / NVIDIA NVENC) and media that lives outside
> `MEDIA_PATH` are covered in [INSTALL.md → Hardware transcoding](INSTALL.md#-hardware-transcoding-tdarr--the-override-file).
