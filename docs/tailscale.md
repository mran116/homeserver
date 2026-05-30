# Tailscale — private remote access (opt-in)

A WireGuard mesh VPN that lets you reach your stuff from anywhere **without
opening a single inbound port**. Off by default; enable with
`COMPOSE_PROFILES=vpn`.

## The model: one subnet router → reach the whole house

The `tailscale-infra` container advertises your **LAN subnet** to your tailnet,
so from any Tailscale device (laptop, phone, anywhere) you reach **every device
on the home LAN by its normal `172.25.x.x` IP** — the Docker host and all
services, the **HA VM**, **Proxmox**, printers — with no per-box install and no
port-forwarding.

```
[your laptop, anywhere] ──WireGuard──▶ [tailscale-infra] ──advertises LAN subnet──▶ whole home LAN
```

## Setup

1. **Auth key** — create a **reusable, non-expiring** key (tag it `tag:server`)
   at login.tailscale.com → set `TS_AUTHKEY` in `.env`.
2. **Subnet** — set `TAILSCALE_SUBNET` to your **real** LAN subnet (not the
   template's `192.168.1.0/24`). Find it:
   `ip -o -f inet route show scope link | awk '{print $1}'` (e.g. `172.25.1.0/24`).
3. Add `vpn` to `COMPOSE_PROFILES`; `hs up infrastructure`.
4. **One-time in the admin console:** **approve** the advertised subnet route
   (Machines → the node → Subnets), **disable key expiry** for the node, and turn
   on **MagicDNS**. Without the route approval, nothing routes.

## What it gives you

- **Remote VS Code / SSH from outside the house** — connect to the host's LAN IP
  over Tailscale (no public exposure).
- **Every admin UI privately** (NPM `:81`, Arcane, Dozzle, Uptime Kuma).
- **HA + Proxmox reachable remotely** by their LAN IPs.

## Optional: private HTTPS via `tailscale serve`

Tailscale can issue valid `*.ts.net` Let's Encrypt certs and proxy a service over
the tailnet with HTTPS — **zero cert config**. Handy for apps that demand HTTPS
when you only need private access. Enable HTTPS certs in the console, then
`tailscale serve` the service. (Complements the Caddy/cert setup in
[caddy.md](caddy.md) for anything you don't expose publicly.)

## How it fits with the rest

| Channel | Use for |
|---|---|
| **Tailscale** | All **private/admin** access — you, remote dev, the whole LAN. No public exposure. |
| **Cloudflare Tunnel** | Only **genuinely public** services (sharing with non-Tailscale family). |
| **Caddy / NPM** | LAN HTTPS + the directly-exposed Jellyfin. |

## Overhead & risk

Very low. WireGuard mesh, **no inbound ports opened** (outbound-only to the
coordination server) — far safer than port-forwarding. Subnet routing needs IP
forwarding (the container's `NET_ADMIN` handles it) + the one-time console route
approval. The auth key is a secret (stays in gitignored `.env`).
