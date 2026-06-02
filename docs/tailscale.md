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
   `ip -o -f inet route show scope link | awk '{print $1}'` (e.g. `192.168.1.0/24`).
3. Add `vpn` to `COMPOSE_PROFILES`; `hs up infrastructure`.
4. **One-time in the admin console:** **approve** the advertised subnet route
   (Machines → the node → Subnets), **disable key expiry** for the node, and turn
   on **MagicDNS**. Without the route approval, nothing routes.

## Internal DNS — the same hostnames at home *and* away (split DNS)

At home, AdGuard rewrites `*.example.com` → the server's LAN IP, so
`vault.example.com` and friends hit Caddy directly. Away from home you want the
**exact same names** to resolve — without making them public. That's **split
DNS**: tell Tailscale to send *only* `*.example.com` lookups to your AdGuard, and
leave every other query untouched.

> **Prerequisite:** the AdGuard resolver must be reachable over the tailnet — i.e.
> it sits on the LAN subnet that `tailscale-infra` advertises (route approved,
> above). On the Flint 3 design AdGuard runs on the router, which is on that
> subnet.

In the Tailscale admin console → **DNS** page:
1. **Nameservers → Add nameserver → Custom.** Enter AdGuard's **LAN IP** (e.g.
   `192.168.1.1` on the Flint 3, or the Docker `adguard` host's IP). Use the LAN
   IP, **not** a `100.x` Tailscale address — devices reach it via the subnet route.
2. Toggle **"Restrict to domain"** (a.k.a. *Restrict to search domain*) and enter
   **`example.com`**. This is what makes it *split* DNS — only `*.example.com`
   queries go to AdGuard; normal browsing keeps each device's own DNS.
3. **Enable MagicDNS** (toggle near the top of the DNS page). The split-DNS rule is
   pushed to devices *via* MagicDNS — **if MagicDNS is off, the restricted
   nameserver is silently ignored.** This is the single most common reason for
   "works at home, not over Tailscale."
4. Leave **Override local DNS** off unless you deliberately want *all* tailnet DNS
   forced through these nameservers.

Now `vault.example.com` resolves to the server's LAN IP whether you're on the
couch or on cellular, and Caddy serves the same valid wildcard cert either way.

**Gotchas that cost the trial-and-error:**
- **MagicDNS must be on** (step 3) — the #1 trap.
- The nameserver IP must be **reachable through the advertised subnet**; if route
  approval (Setup step 4) never happened, lookups just time out.
- It's the **LAN IP**, not the Tailscale `100.x` IP, for the AdGuard nameserver.

## What it gives you

- **Remote VS Code / SSH from outside the house** — connect to the host's LAN IP
  over Tailscale (no public exposure).
- **Every admin UI privately** (Arcane, Dozzle, Uptime Kuma).
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
| **Caddy** | LAN HTTPS + the directly-exposed Jellyfin. |

## Overhead & risk

Very low. WireGuard mesh, **no inbound ports opened** (outbound-only to the
coordination server) — far safer than port-forwarding. Subnet routing needs IP
forwarding (the container's `NET_ADMIN` handles it) + the one-time console route
approval. The auth key is a secret (stays in gitignored `.env`).
