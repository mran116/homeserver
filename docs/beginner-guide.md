# The Super Simple Setup Guide

This sets up your own private "app server" at home — a web page that links to ~30
apps (for movies, photos, documents, passwords, recipes, workouts, and more).

**You do not need to know anything about Linux, Docker, or coding.** You'll mostly
**copy text, paste it, and press Enter.** Follow the steps in order. Don't skip.

> 💡 When you "copy-paste a command," you copy the grey box, paste it into the
> black window (the terminal), and press the **Enter** key. That's it.

You don't need to be an expert, but the next 2 minutes will make everything below
make sense — so you're not just pasting blindly.

---

## The big picture (read this — 2 minutes)

Here's the whole thing in everyday words:

- **The server** is just a computer that stays on and runs your apps, instead of
  paying companies to run them for you. Your data stays in your house.

- **Each app runs in its own "container."** Think of a container as a sealed
  lunchbox: the app and everything it needs are inside, and it can't make a mess
  of the rest of the computer. If one app breaks, the others don't care. (The
  software that runs these lunchboxes is called **Docker** — you won't deal with
  it directly.)

- **A "stack" is a group of related lunchboxes** that work together. For example
  the *mediastack* contains the movie app, the TV app, the downloader, etc. — all
  the boxes that make "media" work, bundled so you start them together.

- **Two web pages run the show:**
  - **Arcane** (the *control panel*, at port `3552`) = the **light switches**. You
    turn stacks on and off here, and watch them run.
  - **Homepage** (the *dashboard*, at port `3000`) = your **front door**. It's the
    page you'll actually use every day, with a button for every app.

- **One settings file, `.env`,** holds your choices (where files go, your
  passwords, which apps to run). The setup fills most of it in for you.

- **One command, `hs`,** is your **remote control** for everything. `hs update`,
  `hs doctor`, `hs status` — you'll learn the five that matter at the end.

**So the plan is simple:** set it up (Part 3) → pick what you want (Part 4) →
flip the switches on (Part 6) → use your front door (Part 7). That's the shape of
everything below.

---

## What you need first

- [ ] A computer that will be your server, with **Ubuntu** or **Debian** already
      installed, and that you can leave turned on.
- [ ] That computer plugged into your internet (cable is best).
- [ ] About **30 minutes**.

If you have those three things, you're ready. 👍

---

## Part 0 — Blank computer? Start here (otherwise skip to Part 1)

**Already have Ubuntu/Debian installed?** Skip this whole part — go to Part 1.

This part is only for a computer with **nothing** on it (or with Windows you want
to replace).

### 0a. Put Ubuntu on the machine

1. On any working computer, go to **ubuntu.com/download/server** and download
   **Ubuntu Server LTS** (LTS = the stable long-term version). You'll get one big
   file ending in `.iso`.
2. Download a free tool called **balenaEtcher** (balena.io/etcher) — it copies that
   file onto a USB stick correctly.
3. Plug in a USB stick (**it will be wiped — use an empty one**). Open Etcher,
   pick the `.iso` file, pick the USB stick, click **Flash**. Wait until it says
   done.
4. Plug that USB stick into the server computer and turn it on. As it starts,
   tap the boot-menu key repeatedly — usually **F12**, sometimes **F2**, **Esc**,
   or **Del** (the screen often shows which for a second). Choose the **USB stick**
   from the list.
5. The Ubuntu installer starts. **Accept the defaults** by pressing Enter through
   the screens. When it asks:
   - **Your name / server name / username / password** — fill these in and
     **remember them** (this is your login).
   - **"Install OpenSSH server"** — turn this **ON** (lets you connect from another
     computer, like in Part 2).
6. When it finishes, it says to **remove the USB stick and reboot**. Do that.

✅ The machine now has Ubuntu. Log in with the username/password you just set, and
continue below.

### 0b. Got a second drive for media? Mount it

"Mounting" just means: make a drive show up at a folder like `/mnt/media` so the
apps can use it.

> 🟢 **Only have ONE drive** (everything on the same disk)? **Skip this** — there's
> nothing to do. Go to Part 1.

> 🛑 **STOP AND READ.** The format command below **erases a drive completely**.
> Pick the wrong one and you wipe your system or your existing files. If you're
> not 100% sure which drive is which, **ask someone** before running the format
> step. When unsure, it's safer to stop here and get help — this is the only
> dangerous step in the whole guide.

1. **See your drives:**
   ```bash
   lsblk -o NAME,SIZE,MODEL,MOUNTPOINT
   ```
   Your main system drive is the one with `/` under MOUNTPOINT — **leave it alone.**
   Your media drive is usually the big one with a blank MOUNTPOINT (e.g. `sdb`).

2. **Does that media drive already have your files on it?**
   - **YES, it has files I want to keep** → **do NOT format.** Skip to step 4 and
     just mount it.
   - **NO, it's a brand-new empty drive** → format it (step 3 erases it).

3. *(New empty drive only)* Format it as `ext4`. Replace `sdX1` with your drive's
   partition (e.g. `sdb1`):
   ```bash
   sudo mkfs.ext4 /dev/sdX1
   ```

4. **Create the folder and mount the drive** (replace `sdX1` with your drive):
   ```bash
   sudo mkdir -p /mnt/media
   echo "UUID=$(sudo blkid -s UUID -o value /dev/sdX1) /mnt/media ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
   sudo mount -a
   ```
   That last block also makes the drive mount itself automatically every time the
   server restarts.

5. **Check it worked:**
   ```bash
   df -h /mnt/media
   ```
   If it shows your drive's size, you're done. Remember the path `/mnt/media` —
   you'll type it (or just press Enter for it) during setup in Part 3.

✅ Your media drive is ready.

---

## Part 1 — Find your server's address

Every device on your network has an address that looks like `192.168.1.100`.
You need your server's address.

**On the server**, open the **Terminal** app (it's a black window where you type),
type this, and press Enter:

```bash
hostname -I
```

You'll see one or more numbers. **Write down the first one.** Example: `192.168.1.100`.

From now on, whenever this guide says **YOUR_IP**, use that number.

---

## Part 2 — Connect to the server (skip if you're sitting at it)

If you want to control the server from a *different* computer, open its Terminal
and type this (put in your server's username and YOUR_IP):

```bash
ssh youruser@YOUR_IP
```

It may ask "are you sure?" — type **yes** and Enter. Then type your server
password and Enter.

> 😟 The password won't show any dots or stars as you type. **That's normal.**
> Just type it and press Enter.

If you're sitting right at the server, ignore this part — just open the Terminal.

---

## Part 3 — Install everything (one big copy-paste)

Copy this **entire grey box**, paste it into the Terminal, and press Enter:

```bash
sudo apt update && sudo apt install -y git
sudo mkdir -p /opt/docker && sudo chown -R $USER /opt/docker
git clone https://github.com/mran116/homeserver.git /opt/docker/stacks
cd /opt/docker/stacks
./scripts/setup-fresh.sh
```

It might ask for your password again — type it (no dots appear) and Enter.

**Now it does the hard work by itself** (installs everything, makes all your
passwords for you). This takes a few minutes. **Let it run.**

### It will ask you a few easy questions

Each question shows a suggested answer in `[brackets]`. **If you're not sure, just
press Enter** to accept it. Here's what the questions mean:

| It asks about… | Setting name | Suggested answer | What it means / when to change it |
|---|---|---|---|
| **Timezone** | `TZ` | your region | Sets your local time. Change only if it guesses wrong. |
| **Config folder** | `CONFIG_PATH` | `/opt/docker/data` | Where apps keep their settings + databases. **Always press Enter** — this must stay on this computer's own disk (databases break on a network drive). |
| **Media folder** | `MEDIA_PATH` | `/mnt/media` | Where your movies/TV/music live. Change it if your media is on a different drive — type that drive's path. |
| **Photos folder** | `PHOTOS_PATH` | `/mnt/photos` | Where your photos go (the Immich app). |
| **Documents folder** | `DOCS_PATH` | `/mnt/documents` | Where scanned documents go (the Paperless app). |
| **Sync folder** | `SYNC_PATH` | `/mnt/sync` | Folders shared between your devices (Syncthing). |
| **Downloads scratch** | `SAB_INCOMPLETE_PATH` | `/opt/docker/incomplete` | Temporary space used *while* downloading. **Press Enter** — keep it on this computer's fast disk. |

You can change any of these later by editing the file `/opt/docker/stacks/.env`.

> 🧠 **The only rule that matters:** your **movies/TV folder** and your
> **downloads** should be on the **same drive**. If everything is on one disk,
> you're automatically fine — just press Enter through all of it.

When it's done it may ask **"Start the control panel now?"** → type **y** and Enter.

✅ **You now have everything set up.** No apps are running yet — that's next.

---

## Part 4 — Choose which apps you want (optional)

You don't have to run everything. There are **two** ways to pick — and it's fine
to skip this whole part and just run the defaults.

### Way 1 — Pick whole groups of apps

In the Terminal, type:

```bash
hs stacks
```

It asks you, one group at a time (movies, recipes, documents, photos, etc.),
whether to **keep it** or **skip it**. Skipped groups never turn on and use
nothing. You can run this again anytime to add or remove groups.

### Way 2 — Pick options + which media player

These live in the settings file. Open it with:

```bash
nano /opt/docker/stacks/.env
```

Find the line that starts with `COMPOSE_PROFILES=` and add any of these words
(separated by commas):

| Word | Turns on |
|---|---|
| `jellyfin` *(already on)* or `plex` | Your media player — pick **one** |
| `backup` | Automatic backups |
| `vpn` | Private remote access (Tailscale) |
| `tunnel` | Secure remote access (Cloudflare) |
| `ddns` | Keeps your home address up to date for a web domain |
| `tdarr` | Automatically shrinks video files |
| `matrix` | A private chat server |

Example: `COMPOSE_PROFILES=jellyfin,backup,vpn`

To save in the `nano` editor: press **Ctrl+O**, then **Enter**, then **Ctrl+X** to
exit.

> 😌 **Not sure? Don't touch this.** The default (`jellyfin`) is a great starting
> point, and you can change it later, then run `hs update`.

---

## Part 5 — Open the control panel

On any computer, open a web browser (Chrome, Firefox, etc.) and go to this address
(use YOUR_IP):

```
http://YOUR_IP:3552
```

Example: `http://192.168.1.100:3552`

A login page appears. Type:
- Username: **arcane**
- Password: **arcane-admin**

**The very first thing to do:** change that password (look for a settings/profile
button, usually top-right). Pick a new password and save it somewhere safe.

> This control panel is where you turn apps on and off. Think of it as the
> light switches for your server.

---

## Part 6 — Turn the apps on (in this order!)

In the control panel you'll see a list of "stacks" (groups of apps). Click each
one and press the **Start** button, **in this exact order**. Wait about a minute
between each of the first four:

1. **vaultwarden** ← your password vault
2. **infrastructure** ← the plumbing (networking, ad-blocking)
3. **monitoring** ← keeps an eye on everything
4. **dashboard** ← your main home page
5. **mediastack** ← movies, TV, music, downloads
6. Then the rest: **household, records, knowledge, syncthing, cloud, fitness**

Order matters because some apps need the earlier ones to be running first.

> 🩺 Want to check everything is healthy? Back in the Terminal, type `hs doctor`
> and press Enter. It checks everything and tells you, in plain English, if
> anything needs fixing.

---

## Part 7 — Your home page + first logins

Open your **dashboard** (home page) in a browser (use YOUR_IP):

```
http://YOUR_IP:3000
```

This page has a button for every app. To start using an app, click it and **make
an account** (pick a username and password).

A few important tips:
- **Do Vaultwarden first** (the password app). Turn on 2FA. Then save every other
  password you make inside it.
- For most apps, the **first account you make becomes the boss/admin account.**
- **qBittorrent** (downloads) starts with username `admin` and password
  `adminadmin` — log in and change it right away.
- **Paperless** (documents) already made your login for you — you don't need to
  sign up. (Ask later and we'll show you where to find it.)

> 🎬 For movies/TV apps (Sonarr, Radarr): after logging in, go to
> **Settings → Media Management → Root Folders** and pick the folder where your
> movies/shows live. That tells them where to put things.

---

## Part 8 — Make the home page show live info

Your dashboard can show live numbers (download speeds, how many movies, etc.).
One command sets most of this up. In the Terminal, type:

```bash
hs keys
```

It does the easy parts automatically and tells you the few things to copy by hand.
When you're done, type `hs up dashboard` to refresh the home page.

🎉 **That's it — you have a working home server!**

---

## The 5 commands you'll ever need

Type these in the Terminal anytime, from anywhere:

| Type this | What it does |
|---|---|
| `hs doctor` | Checks everything and tells you what's wrong (if anything) |
| `hs update` | Gets the newest version and restarts things (run now and then) |
| `hs status` | Shows what's running |
| `hs logs sonarr` | Shows messages from an app (swap `sonarr` for any app) |
| `hs help` | Lists everything you can do |

---

## "Help, something's wrong!"

Try these in order — most problems are tiny:

1. **Type `hs doctor`.** It usually names the exact problem and the fix.
2. **An app won't open?** Wait 1–2 minutes (apps take a moment to wake up), then
   try again.
3. **It says "Bad Gateway"?** The app is still starting. Wait a minute, or type
   `hs restart` and the stack name (e.g. `hs restart fitness`).
4. **A movie/TV app says a folder is missing?** Your storage drive might not be
   plugged in/turned on, or you picked the wrong folder in the app's
   *Settings → Media Management*.
5. **Still stuck?** Don't panic — nothing is broken permanently. Ask for help and
   include what `hs doctor` said.

---

## The whole thing, super short

```bash
ssh youruser@YOUR_IP                  # connect (or just sit at the server)
sudo apt update && sudo apt install -y git
git clone https://github.com/mran116/homeserver.git /opt/docker/stacks
cd /opt/docker/stacks && ./scripts/setup-fresh.sh   # answer questions, Enter = default
# open http://YOUR_IP:3552 → turn on the stacks in order
hs keys                               # fill in the home page
```

Press Enter through the questions, turn things on in order, and you're done.
