# The Super Simple Setup Guide

This sets up your own private "app server" at home — a web page that links to ~30
apps (for movies, photos, documents, passwords, recipes, workouts, and more).

**You do not need to know anything about Linux, Docker, or coding.** You'll mostly
**copy text, paste it, and press Enter.** Follow the steps in order. Don't skip.

> 💡 When you "copy-paste a command," you copy the grey box, paste it into the
> black window (the terminal), and press the **Enter** key. That's it.

---

## What you need first

- [ ] A computer that will be your server, with **Ubuntu** or **Debian** already
      installed, and that you can leave turned on.
- [ ] That computer plugged into your internet (cable is best).
- [ ] About **30 minutes**.

If you have those three things, you're ready. 👍

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

| It asks about… | In plain English | Just press Enter unless… |
|---|---|---|
| **Timezone** | Your local time, so logs/schedules are right | …it guessed the wrong region |
| **Config folder** | Where the apps keep their settings | …always press Enter (keep it on this computer) |
| **Media folder** | Where your movies/TV/music go | …your movies are on a different drive (type that drive's path) |
| **Photos folder** | Where your photos go | …you want them somewhere specific |
| **Documents folder** | Where scanned documents go | …you want them somewhere specific |
| **Downloads scratch** | Temporary space while downloading | …press Enter (keep it on this computer) |

> 🧠 **The only rule that matters:** your **movies/TV folder** and your
> **downloads** should be on the **same drive**. If everything is on one disk,
> you're automatically fine — just press Enter through all of it.

When it's done it may ask **"Start the control panel now?"** → type **y** and Enter.

✅ **You now have everything set up.** No apps are running yet — that's next.

---

## Part 4 — Open the control panel

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

## Part 5 — Turn the apps on (in this order!)

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

## Part 6 — Your home page + first logins

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

## Part 7 — Make the home page show live info

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
