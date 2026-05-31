# Home Assistant — household coordination

Reference config you copy onto your **Home Assistant OS VM** (HA runs separately,
not in this Docker stack). The goal is to make HA the *household brain* — it
nudges you about chores, calendar, meals and shopping, and routes alerts — so
you carry less in your head.

These are starting points, not magic: every file has `CHANGE ME` markers where
you plug in your own entity IDs and notify target.

## What's here

| File | What it does |
|---|---|
| `packages/household.yaml` | Morning briefing, bins reminder, "thaw tomorrow's dinner", weekly chore digest, shopping nudge — built on your Donetick / Mealie / Calendar integrations. |
| `packages/alerts.yaml` | Turns your existing Diun webhook and Uptime Kuma integration into a calm notification stream (update available, service down/recovered), plus a daily low-battery roundup. |

## Install

1. **Enable packages.** In `/config/configuration.yaml` on the HA VM:
   ```yaml
   homeassistant:
     packages: !include_dir_named packages
   ```
2. **Copy the files** into `/config/packages/` (use the Studio Code Server or
   Samba add-on). You should end up with `/config/packages/household.yaml` and
   `/config/packages/alerts.yaml`.
3. **Set your notify target.** Edit `script.notify_household` in
   `household.yaml` — change `notify.notify` to your phone, e.g.
   `notify.mobile_app_pixel_8`. Every automation routes through this one script,
   so you set it once.
4. **Fix the entity IDs.** Open *Developer Tools → States*, search for your
   Donetick / Mealie / calendar entities, and replace each
   `CHANGE ME` placeholder with the real `entity_id`.
5. **(Optional) Diun alerts in HA.** Diun already pushes update alerts to **ntfy**
   (the `diun-updates` topic) from the monitoring stack, so you get them on your
   phone without HA. The `alerts.yaml` Diun-webhook automation is only needed if
   you *also* want update alerts inside HA — to use it, point Diun's notifier at
   HA's webhook (instead of ntfy) and match the `webhook_id`.
6. **Reload.** *Developer Tools → YAML → Reload all*, or restart HA. Test from
   *Developer Tools → Actions* by running `script.notify_household`.

## Embed Homepage in HA (one front door, optional)

Keep Homepage as your admin launcher, but reach it from inside HA so there's a
single place to go:

1. HA → **Settings → Dashboards → Add Dashboard → Webpage**.
2. Title it "Homepage", pick an icon, URL: `http://<server-ip>:3000`.
3. Save — it shows in the HA sidebar; one click opens Homepage inside HA.

**Mixed-content gotcha:** a browser blocks an `http://` page embedded in an
`https://` HA. If your HA is served over https, either:
- give Homepage an https URL (e.g. `https://homepage.home` via Nginx Proxy
  Manager) and use that as the Webpage URL, or
- access HA over http on the LAN.

If you move Homepage to a hostname, add it to `HOMEPAGE_ALLOWED_HOSTS` in
`dashboard/docker-compose.yml` (it currently allows `${SERVER_IP}:${HOMEPAGE_PORT}`).

> Homepage stays your *admin* board; build the *family* dashboard in HA from its
> integrations (calendar, chores, shopping, lights, weather). They pull from the
> same services — you don't rebuild Homepage in HA.

## Reverse proxy & external access

HA reaches the Docker services over the LAN (it's a separate VM, not on the
`home` network), so point its integrations at **hostnames**, not `IP:port` —
they survive IP changes and get valid TLS. Full design:
[`docs/network-and-remote-access.md`](../../docs/network-and-remote-access.md).

Put HA itself behind Caddy (`home.<domain>` → `http://<ha-vm-ip>:8123`)
and tell HA to trust the proxy. In `/config/configuration.yaml`:

```yaml
homeassistant:
  external_url: "https://home.<domain>"   # CHANGE ME
  internal_url: "https://home.<domain>"   # CHANGE ME (split-horizon: same name)
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - <server LAN IP>                      # CHANGE ME — the server's LAN IP where Caddy listens
```

Reach HA from outside over **Tailscale**, not the public internet — it's an
admin surface, so it stays off the Cloudflare Tunnel.

## Prerequisites (already in the main README's HA section)

- HACS installed, with the **Donetick, Mealie** integrations.
- The **Uptime Kuma** integration (gives you `binary_sensor.uptime_kuma_*`).
- A **Google Calendar** integration for the family calendar.
- The HA **companion app** on at least one phone (provides `notify.mobile_app_*`).

## Where to grow next

Once these feel natural, the highest-leverage *device* additions are mmWave
presence sensors + Adaptive Lighting (lights handle themselves) and local voice
(Assist + Whisper/Piper). See the discussion in the main README's HA section.
