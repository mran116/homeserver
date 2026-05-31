# 🏡 Home Assistant Integration

> 📖 **Docs:** [README](../README.md) · [Install & Setup](INSTALL.md) · [Reference](REFERENCE.md) · [Remote-access design](network-and-remote-access.md)

> **Status: future goal — not yet deployed.** Home Assistant isn't part of the
> running stack today. This documents the *intended* integration once an HA VM is
> added (it runs separately on **Home Assistant OS**, not in this Docker host).
> Ready-made HA packages already live in [`reference/home-assistant/`](../reference/home-assistant/)
> for when you stand it up.

Home Assistant is planned as the smart home brain and family wall dashboard. It
connects to many services in this stack to display everything in one place.

## What HA will connect to from this stack

| Service | HA Integration | What you get |
|---|---|---|
| Jellyfin | HACS — Jellyfin integration | Media player card, now playing, playback control |
| Navidrome | HACS — Navidrome integration | Music player card, currently playing |
| Mealie | HACS — Mealie integration | Meal plan card, recipe count, shopping list on dashboard |
| Donetick | HACS — Donetick integration | Chore list, tasks due today |
| Google Calendar | Built-in | Family and shared calendars on dashboard |

## Recommended HACS frontend cards for wall tablet

| Card | Purpose |
|---|---|
| Atomic Calendar Revive | Beautiful calendar card — color-coded calendars, agenda view |
| Mushroom Cards | Modern, clean card designs for all your dashboard widgets |
| Kiosk Mode | Hides HA header and sidebar for a clean full-screen tablet display |

## Wall tablet setup

For a wall-mounted family dashboard running Home Assistant:

1. Install HACS — see [hacs.xyz](https://hacs.xyz) for instructions
2. Install Atomic Calendar Revive, Mushroom Cards, and Kiosk Mode via HACS
3. Connect Google Calendar integration — Settings → Devices & Services → Add Integration → Google Calendar
4. Connect Mealie and Donetick via HACS integrations
5. Build your dashboard — Settings → Dashboards
6. Enable Kiosk Mode for full-screen display
7. Use **Fully Kiosk Browser** (Android) or **Guided Access** (iOS) to lock the tablet to the dashboard

## Recommended HA add-ons

| Add-on | Purpose |
|---|---|
| Terminal & SSH | Required for HACS installation |
| Music Assistant | Connects Navidrome and other music sources to HA media players |
| Studio Code Server | Edit HA config files from the browser |

## Household automations (proactive nudges + alerts)

Ready-made HA packages live in [`reference/home-assistant/`](../reference/home-assistant/) — copy them
to your HA VM's `/config/packages/` to turn Donetick / Mealie /
Calendar into morning briefings, chore digests, bin/meal/shopping reminders, and
to route Diun + Uptime Kuma into a single alert stream. See
[`reference/home-assistant/README.md`](../reference/home-assistant/README.md) for setup.
