# Beginner's Guide — from blank server to running homelab

A complete, copy-paste walkthrough. **No Linux or Docker experience needed.**
At every prompt, pressing **Enter** takes the safe default.

> If a step's command starts with `sudo`, it may ask for your password — type it
> (you won't see characters as you type; that's normal) and press Enter.

Time: ~20 minutes of you, plus some unattended download time.

---

## What you'll end up with

A web **dashboard** linking to ~30 self-hosted apps (media library, photos,
documents, passwords, recipes, fitness, and more), all managed from one place,
with automatic backups and update alerts.

---

## Before you start — the checklist

1. **A computer/server** with **Ubuntu or Debian** already installed, that stays
   on. (A spare PC, a NUC, or a VM all work.)
2. **Its IP address.** On the server, run `hostname -I` and note the first number
   (e.g. `192.168.1.100`). You'll use it a lot — call it **`YOUR_IP`**.
3. **Your storage mounted.** If you keep media on a separate drive or NAS, mount
   it now and note the path (e.g. `/mnt/media`). One drive for everything is
   simplest. *(Different layout? See [porting-to-your-own-layout.md](porting-to-your-own-layout.md).)*
4. **About 30 minutes** and the password for your server login.

That's it. Everything else is automated below.

---

## Step 1 — Open a terminal on the server

Either sit at the server, or connect from another computer over SSH:

```bash
ssh youruser@YOUR_IP
```
(Replace `youruser` with your server username and `YOUR_IP` with the address from
the checklist.)

---

## Step 2 — Download the project and run one-time setup

Copy-paste this whole block and press Enter:

```bash
sudo apt update && sudo apt install -y git
sudo mkdir -p /opt/docker && sudo chown -R $USER /opt/docker
git clone https://github.com/mran116/homeserver.git /opt/docker/stacks
cd /opt/docker/stacks
./scripts/setup-fresh.sh
```

**What this does for you, automatically:**
- Installs Docker and all dependencies
- Asks a few simple questions: your **timezone**, and **where to store data**
  (press Enter for defaults, or type your media path from the checklist)
- **Generates all strong passwords and secret keys** (you never invent these)
- Creates all the folders, the private network, and the symlinks
- Installs the **`hs`** command (your one control command) and a control panel

> You'll be asked things like *"Media library root [/mnt/media]"*. Type your path
> or press Enter. When in doubt, **Enter**.

When it finishes, it may offer to start the control panel — say **yes**.

### The storage paths you'll be asked about

Setup prompts for these (Enter = the default shown). This is where all your data
lives — get them right now and you won't touch them again. You can also edit them
later in `/opt/docker/stacks/.env`.

| Setting | Default | What goes here | Put it on… |
|---|---|---|---|
| `CONFIG_PATH` | `/opt/docker/data` | App settings + **databases** | **Local disk only** — databases corrupt on a NAS |
| `MEDIA_PATH` | `/mnt/media` | Movies, TV, music, books **+ downloads** | One drive/pool (must hold downloads too, for instant imports) |
| `PHOTOS_PATH` | `/mnt/photos` | Immich photo/video library | Local or NAS |
| `DOCS_PATH` | `/mnt/documents` | Paperless documents | Local or NAS |
| `SYNC_PATH` | `/mnt/sync` | Syncthing synced folders | Local or NAS |
| `SAB_INCOMPLETE_PATH` | `/opt/docker/incomplete` | Usenet download scratch space | **Fast local disk (SSD)** — heavy work stalls on a NAS |
| `BACKUP_PATH` | `/mnt/media/backups` | Nightly backups | **A different physical disk** from `CONFIG_PATH`, so one dead disk can't lose both |

**The golden rules:**
- **`CONFIG_PATH` = local disk, always.** Never a network share — databases corrupt.
- **All media + downloads share one filesystem** under `MEDIA_PATH`. Folder names
  and nesting don't matter; *same drive/pool* does (see
  [porting-to-your-own-layout.md](porting-to-your-own-layout.md)).
- **`BACKUP_PATH` on a separate disk** from your config/data, or a backup is
  pointless when that disk dies.

Two more advanced paths exist in `.env` if you need them: `STACKS_PATH` (where
this project lives) and `MUSIC_PATH` (override Navidrome's music folder; defaults
to `MEDIA_PATH/music`). Most people leave both alone.

---

## Step 3 — Choose what gets installed (optional but worth it)

You don't have to run everything. There are **two** levels of choice:

### A) Whole apps/stacks — `hs stacks`
```bash
hs stacks
```
This walks you through each group of apps (media, household, documents, photos,
etc.) and lets you pick **deploy** or **skip**. Skipped ones never start and use
no resources. You can re-run it anytime to add/remove.

### B) Options & your media server — `COMPOSE_PROFILES` in `.env`
Open the settings file:
```bash
nano /opt/docker/stacks/.env
```
Find the line starting `COMPOSE_PROFILES=` and pick from:

| Add this word | Turns on |
|---|---|
| `jellyfin` *(default)* or `plex` | your media server (pick one) |
| `tunnel` | Cloudflare Tunnel (secure remote access) |
| `vpn` | Tailscale (private remote access) |
| `backup` | automatic encrypted backups |
| `ddns` | auto-update your domain's IP |
| `matrix` | Matrix chat server |
| `tdarr` | automatic video transcoding |

Combine with commas, e.g. `COMPOSE_PROFILES=jellyfin,backup,vpn`.
Save in nano with **Ctrl+O, Enter**, then exit with **Ctrl+X**.

> Not sure? Leave it as `jellyfin` for now — you can change it later and re-run
> `hs update`.

---

## Step 4 — Open the control panel (Arcane)

In a web browser on any computer on your network, go to:

```
http://YOUR_IP:3552
```

Log in with **`arcane` / `arcane-admin`** and **change the password immediately**
(top-right → settings).

This is your "engine room" — start/stop apps and watch them run.

---

## Step 5 — Turn on the apps (in order)

In Arcane, click each stack and press **Start**, **in this order** — let the first
few finish before starting the next:

```
1. vaultwarden       (passwords)
2. infrastructure    (proxy, ad-block, networking)
3. monitoring        (uptime + alerts)
4. dashboard         (your homepage)
5. mediastack        (movies/TV/music/downloads)
6. household, records, knowledge, syncthing, cloud, fitness  (the rest)
```

> Prefer the command line? `hs up vaultwarden`, `hs up infrastructure`, … or
> `hs up` to start everything at once.

Give them a couple of minutes. Check health anytime with:
```bash
hs doctor
```
It's a read-only checkup that tells you in plain English what (if anything) still
needs attention.

---

## Step 6 — Create your logins

Open your **dashboard** at `http://YOUR_IP:3000` — it has a tile linking to every
app. For each app you want to use, click it and create your account. Notes:

- **Start with Vaultwarden** (passwords) and turn on 2FA — then store every other
  password you create in it.
- **Most apps:** the first account you create becomes the admin.
- **qBittorrent:** default login is `admin` / `adminadmin` — change it.
- **Paperless:** no signup needed — its admin login was auto-created for you (find
  it in `.env` as `PAPERLESS_ADMIN_USER` / `PAPERLESS_ADMIN_PASSWORD`).
- **Media folders:** in Sonarr/Radarr, go to *Settings → Media Management → Root
  Folders* and point them at your library under `/data` (e.g. `/data/tv`,
  `/data/movies`, or whatever your folders are called).

*(Full per-app "who-creates-what" table: [porting-to-your-own-layout.md](porting-to-your-own-layout.md#logins--secrets--whats-generated-vs-what-you-create).)*

---

## Step 7 — Light up the dashboard's live data

The dashboard can show live stats (download speeds, library counts, etc.) once it
has each app's API key. This command grabs most of them automatically:

```bash
hs keys
```
It auto-detects what it can and prints exactly where to copy the few that must be
generated inside an app's web page. Paste those into `.env`, then refresh the
dashboard with `hs up dashboard`.

---

## You're done. Day-to-day commands

Run these from anywhere:

```bash
hs update      # get the latest version + apply settings + restart (run occasionally)
hs doctor      # health check — tells you what to fix
hs status      # what's running
hs logs <app>  # see an app's logs (e.g. hs logs sonarr)
hs help        # the full list
```

---

## If something looks wrong

1. **Run `hs doctor`** first — it names the problem and the fix.
2. **An app won't load?** Give it 1–2 minutes after starting (databases warm up).
   Then `hs logs <app>` to see why.
3. **"Bad Gateway"** usually means the app behind it is still starting — wait, or
   `hs restart <stack>`.
4. **Wrong media path / "folder doesn't exist"?** Your storage drive may not be
   mounted, or the *arr root folder points somewhere that doesn't exist — check
   *Settings → Media Management* in the app.
5. Still stuck? The deep-dive walkthrough is [INSTALL.md](INSTALL.md), and remote
   access is [network-and-remote-access.md](network-and-remote-access.md).

---

## Quick reference — the whole thing in 6 lines

```bash
ssh youruser@YOUR_IP
sudo apt update && sudo apt install -y git
git clone https://github.com/mran116/homeserver.git /opt/docker/stacks
cd /opt/docker/stacks && ./scripts/setup-fresh.sh   # answer prompts, Enter = default
# open http://YOUR_IP:3552  → start the stacks in order
hs keys                                              # then fill the dashboard
```
