# Network & Remote-Access Design

How this homeserver is reached — at home and from outside — plus the network
segmentation and Home Assistant integration that make it seamless and resilient.

> Concrete hostnames below use **`example.com`** as the example domain. The real
> value lives only in your gitignored `.env` (`DOMAIN=`); the committed
> `.env.example` stays generic. If you'd rather not reference the domain in a
> committed file, move this doc to `*.local.md` (gitignored).

## Goals

- **Seamless** — the same hostnames work identically at home and away, all over
  valid HTTPS.
- **Secure** — minimal public surface, segmented network, sensitive admin tools
  never exposed.
- **Resilient** — DNS and VPN live on the always-on router, so a Docker/Proxmox
  reboot never takes the house's internet (or your remote access) down.

## Hardware context

- **Router:** GL.iNet **Flint 3** (Wi-Fi 7, OpenWrt-based). Runs AdGuard Home,
  Tailscale and WireGuard natively and supports VLANs — so the resilient layer
  lives here, not in Docker.
- **APs:** TP-Link (Omada/EAP) — each SSID maps to a VLAN tag.
- **Compute:** one Proxmox host running the **Docker VM** (this repo's stacks)
  and the **Home Assistant OS VM**. Single physical NIC, VLAN trunk from the
  Flint 3 into a VLAN-aware Linux bridge — virtual NICs do the rest.

## Network segmentation (VLANs)

The Flint 3 trunks these VLANs to the Proxmox bridge; APs map SSIDs to them.

| VLAN | Name | Members | Internet | Notes |
|---|---|---|---|---|
| 10 | Trusted | PCs, phones, laptops | yes | Your daily devices |
| 20 | Servers | Proxmox mgmt, Docker VM, HA VM, NAS | yes | Infrastructure |
| 30 | IoT | Plugs, bulbs, TVs, speakers | restricted | Smart-home gear |
| 40 | Guest | Visitors | yes (isolated) | No LAN access |

**Firewall posture:** default-deny between VLANs. Allow `Trusted → Servers` and
`Trusted → IoT`. IoT cannot initiate to Trusted/Servers (except the HA path
below). Guest is internet-only.

**Static addressing:** DHCP reservations on the Flint 3 for the Proxmox host,
Docker VM, HA VM and NAS, so hostnames and integrations never drift.

## Home Assistant integration

HA runs as its own VM (keeps Supervisor add-ons + backups). Two design choices
make it integrate cleanly:

- **Dual virtual NIC for discovery.** Give the HA VM two virtual NICs on the
  VLAN-aware bridge: one tagged **VLAN 20 (Servers)**, one tagged **VLAN 30
  (IoT)**. HA then sits *on* the IoT segment, so mDNS / Matter / Chromecast /
  HomeKit discovery just works — **no Avahi reflector, no cross-VLAN multicast
  hacks**. This is free on a single physical port (NICs are virtual).
  - *Fallback if you skip the second NIC:* run an mDNS reflector on the Flint 3
    (it sees every VLAN) plus a firewall rule for the real traffic, or add
    devices by IP, or keep HA + IoT on the same VLAN.
- **HA behind the reverse proxy** at `home.example.com` (see TLS below). Set in
  HA's `configuration.yaml`:
  ```yaml
  homeassistant:
    external_url: "https://home.example.com"
    internal_url: "https://home.example.com"
  http:
    use_x_forwarded_for: true
    trusted_proxies:
      - <server LAN IP>          # the server's LAN IP where Caddy listens
  ```
- **Service integrations use hostnames, not `IP:port`.** Point HACS
  integrations (Jellyfin, Navidrome, Mealie, KitchenOwl, Donetick, Immich,
  Uptime Kuma) at `*.example.com` names so they survive IP changes and get valid
  TLS. The reference packages in `reference/home-assistant/` drive notifications
  off entity IDs and don't hard-code URLs, so only the integration setup (HA UI)
  changes.
- **Notification split (keep both):**
  - **HA mobile app** → household nudges (briefings, chores, meals, shopping).
  - **ntfy** (Docker) → infra/ops alerts **and** an Uptime-Kuma "HA is down"
    watchdog — because ntfy keeps working when HA is the thing that's down.
- **Remote HA** is reached over **Tailscale**, not the public internet.
- **Backups:** HA Supervisor backup → NAS/Docker host, folded into the offsite
  (Borgmatic) job; Proxmox `vzdump` of both VMs as the coarse layer.

## DNS

- **AdGuard Home on the Flint 3 is primary DNS** (resilient — the router is
  always up; AdGuard is near-zero CPU). The repo's Docker `adguard` stack can
  stay as an optional secondary resolver for failover.
- **Split-horizon:** AdGuard rewrites `*.example.com` → the **server's LAN IP**
  (where Caddy listens), so at home every request goes straight to the reverse
  proxy (no hairpin out to the internet and back).
- **Public DNS** lives in Cloudflare and only has records for the exposed subset
  (Tunnel CNAMEs + the Jellyfin DNS-only A record). Admin tools resolve
  **internally only**, so they're invisible from outside.

## TLS (one wildcard cert, via DNS-01)

- Domain registered/managed at **Cloudflare** (`example.com`).
- **Caddy issues one wildcard cert `*.example.com` via the DNS-01 challenge**
  using a scoped Cloudflare API token (Zone → DNS → Edit + Zone → Read, for
  `example.com` only). DNS-01 means **nothing is exposed publicly to validate**
  (so internal-only names are covered too), the cert **auto-renews**, and it
  persists in the `caddy/data` volume. One wildcard also keeps individual
  service names **out of public Certificate Transparency logs**.
- Every service shares one `*.example.com` Caddy site (host-matched routes from
  container labels), so both the split-horizon internal path and the public path are valid HTTPS. This is
  what removes the mixed-content/embedding pain (e.g. Homepage inside HA).

## Remote access

Three coordinated paths:

1. **Tailscale (private, everything)** — the **Flint 3 acts as a subnet router**
   advertising VLAN 20. Family installs the Tailscale app; add Tailscale
   **split-DNS** pointing `example.com` at AdGuard so the same names resolve over
   the tunnel. This is the path for **Vaultwarden**, **HA**, all admin tools, and
   Jellyfin on devices that can run Tailscale.
2. **Cloudflare Tunnel (public subset)** — the `cloudflared` container (on the
   `home` network, so it reaches services by container name). Zero open ports.
   Used for small/HTML and audio/photo services. Cloudflare **Access** can gate
   sensitive paths.
3. **Direct (Jellyfin only)** — Jellyfin's video library **must not** go through
   Cloudflare's proxy (violates the free-plan ToS on non-HTML/streaming content
   and risks account action). Instead: a **DNS-only (grey-cloud) A record** for
   `jellyfin.example.com` → your home IP, **port 443 forwarded** on the Flint 3
   to Caddy, kept current by **DDNS** (dynamic WAN IP). Hardened (below).

## Exposure matrix

Internal ports are the container's own port on the `home` network (from each
stack's compose), **not** the host `${*_PORT}`.

| Service | Public? | Transport | Hostname | Upstream |
|---|---|---|---|---|
| Jellyfin | yes | Direct (DNS-only A + 443) **+** Tailscale | `jellyfin.example.com` | `http://jellyfin:8096` |
| Seerr | yes | Cloudflare Tunnel | `requests.example.com` | `http://seerr:5055` |
| Immich | yes | Cloudflare Tunnel | `photos.example.com` | `http://immich-server:2283` |
| Audiobookshelf | yes | Cloudflare Tunnel | `audiobooks.example.com` | `http://audiobookshelf:80` |
| Navidrome | yes | Cloudflare Tunnel | `music.example.com` | `http://navidrome:4533` |
| Vaultwarden | yes* | Cloudflare Tunnel (+Access on `/admin`) | `vault.example.com` | `http://vaultwarden:80` |
| Home Assistant | no | Tailscale only | `home.example.com` | `http://<ha-vm-ip>:8123` |
| Homepage | no | Tailscale only | `dash.example.com` | `http://homepage:3000` |
| Arcane / Paperless / Actual | no | Tailscale only | `*.example.com` (internal DNS only) | respective containers |

\* Vaultwarden is public but **Cloudflare Access wraps `/admin` only** — see the
hardening note; wrapping the whole domain breaks the Bitwarden clients.

## Hardening (anything public)

- **Jellyfin:** Crowdsec host firewall bouncer or fail2ban, strong passwords,
  keep the image updated (Diun alerts), optional **geo-block** to your country on
  the Flint 3 firewall or a Cloudflare WAF rule.
- **Vaultwarden:** Cloudflare Access policy scoped to **`/admin` only** (email
  OTP). The app/API endpoints stay protected by Vaultwarden's own auth —
  **enforce 2FA**, keep `VAULTWARDEN_SIGNUPS_ALLOWED=false`, set a strong
  `VAULTWARDEN_ADMIN_TOKEN`. (Full-domain Access can't complete the Bitwarden
  apps' non-interactive login, so sync would break.)
- **Enforce 2FA** on Immich, Seerr, Jellyfin and Vaultwarden.
- **Never expose** Arcane, Paperless, Actual Budget, or HA's
  admin — Tailscale only.

## Rollout checklist

**Phase 0 — repo ready (done in this branch)**
- [x] `.env.example`: `DOMAIN`, `CLOUDFLARE_DNS_API_TOKEN`, `DDNS_DOMAINS`
- [x] `infrastructure/`: `cloudflared` + `ddns-updater` blocks (commented, ready)
- [x] This design doc + HA reverse-proxy notes

**Phase 1 — when `example.com` is live (tomorrow)**
- [ ] Add `example.com` to Cloudflare; create a scoped API token (Zone:DNS:Edit)
- [ ] Create a Tunnel; copy its token
- [ ] `.env`: set `DOMAIN`, `CLOUDFLARE_TUNNEL_TOKEN`, `CLOUDFLARE_DNS_API_TOKEN`,
      `DDNS_DOMAINS=jellyfin.example.com`
- [ ] Caddy: enable the profile; it auto-issues the `*.example.com` wildcard cert
      (DNS-01 / Cloudflare token)
- [ ] Caddy: add the two `caddy:` labels to each service in the matrix — routes
      and their certs generate themselves
- [ ] AdGuard (Flint 3): rewrite `*.example.com` → the server's LAN IP (Caddy)
- [ ] Uncomment `cloudflared` + `ddns-updater`; deploy `infrastructure`
- [ ] Cloudflare Tunnel: add public hostnames (requests/photos/audiobooks/music/
      vault → the upstreams above)
- [ ] Cloudflare: DNS-only A record `jellyfin` → home IP; forward 443 on Flint 3
- [ ] Cloudflare Access: policy on `vault.example.com` path `/admin`
- [ ] Harden Jellyfin (Crowdsec/fail2ban, 2FA), enforce 2FA on the rest

**Phase 2 — segmentation (independent, any time)**
- [ ] VLANs on Flint 3 + APs; VLAN-aware Proxmox bridge
- [ ] HA VM second virtual NIC on the IoT VLAN
- [ ] Inter-VLAN firewall rules

**Phase 3 — remote polish**
- [ ] Flint 3 Tailscale subnet router + split-DNS
- [ ] HA `external_url`/`trusted_proxies`; repoint integrations to hostnames
- [ ] Add `dash.example.com` (and any new proxied host) to
      `HOMEPAGE_ALLOWED_HOSTS` in `dashboard/docker-compose.yml`
