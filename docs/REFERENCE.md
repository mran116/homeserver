# 📚 Reference

Look-up material that doesn't belong in the install flow: Home Assistant
integration, the mobile apps per service, the network diagram, and hardware specs.

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

Ready-made HA packages live in [`reference/home-assistant/`](../reference/home-assistant/) — copy them
to your HA VM's `/config/packages/` to turn Donetick / Mealie / KitchenOwl /
Calendar into morning briefings, chore digests, bin/meal/shopping reminders, and
to route Diun + Uptime Kuma into a single alert stream. See
[`reference/home-assistant/README.md`](../reference/home-assistant/README.md) for setup.

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
