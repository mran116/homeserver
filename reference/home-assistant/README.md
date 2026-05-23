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
| `packages/household.yaml` | Morning briefing, bins reminder, "thaw tomorrow's dinner", weekly chore digest, shopping nudge — built on your Donetick / Mealie / KitchenOwl / Calendar integrations. |
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
   Donetick / Mealie / KitchenOwl / calendar entities, and replace each
   `CHANGE ME` placeholder with the real `entity_id`.
5. **Wire the Diun webhook.** In `alerts.yaml`, set `webhook_id` to match the id
   in `DIUN_NOTIF_WEBHOOK_URL` in your Docker host `.env`
   (`http://<ha-vm-ip>:8123/api/webhook/<webhook-id>`).
6. **Reload.** *Developer Tools → YAML → Reload all*, or restart HA. Test from
   *Developer Tools → Actions* by running `script.notify_household`.

## Prerequisites (already in the main README's HA section)

- HACS installed, with the **Donetick, Mealie, KitchenOwl** integrations.
- The **Uptime Kuma** integration (gives you `binary_sensor.uptime_kuma_*`).
- A **Google Calendar** integration for the family calendar.
- The HA **companion app** on at least one phone (provides `notify.mobile_app_*`).

## Where to grow next

Once these feel natural, the highest-leverage *device* additions are mmWave
presence sensors + Adaptive Lighting (lights handle themselves) and local voice
(Assist + Whisper/Piper). See the discussion in the main README's HA section.
