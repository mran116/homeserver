# Mediastack — wiring the *arr automation chain

Getting Jellyfin to play a file is easy; the hard part is the **acquisition
chain** — Prowlarr feeds indexers to Sonarr/Radarr/Lidarr, which send grabs to a
download client, which drops files where the *arr import them by hardlink. This
is the order to set it up in, and the connection details that actually work on
this stack.

> 🔑 **Golden rule for every box-to-box URL below:** services reach each other by
> **container name + internal port** on the shared `home` Docker network — e.g.
> `http://sonarr:8989`, **not** `http://<server-ip>:8989`. The host `${*_PORT}`
> values are only for *your* browser. (Open each UI at `http://<server-ip>:${*_PORT}`
> to configure it.)

> 🔗 **The hardlink layout (why imports are instant):** every *arr mounts the
> whole media root at **`/data`**, and downloads live under the *same* mount
> (`/data/torrents`, `/data/usenet`). Because library and downloads share one
> filesystem, imports are **hardlinks** — no copy, no double disk use. Never set a
> root folder or download path *outside* `/data`.

## Order of operations
1. Download clients — qBittorrent + SABnzbd
2. Prowlarr — indexers, FlareSolverr, connect the apps
3. Sonarr / Radarr / Lidarr — download clients + root folders
4. Quality profiles — already handled by Recyclarr (nothing to do)
5. Seerr — point at Sonarr/Radarr
6. Bazarr — subtitles

## 1. Download clients

### qBittorrent — reached at host `gluetun`, **not** `qbittorrent`
⚠️ **The #1 gotcha on this stack.** qBittorrent runs `network_mode:
service:gluetun`, so it has **no network identity of its own** — it lives inside
the `gluetun` container's network. Everywhere a *arr asks for the qBittorrent
**Host**, enter **`gluetun`** with port **`${BITTORRENT_PORT}`** (8080). Using
`qbittorrent` as the host will never connect.
- Browser: `http://<server-ip>:${BITTORRENT_PORT}`. Default login `admin` /
  `adminadmin` — change it immediately (Tools → Options → Web UI).
- If qBittorrent won't load **at all**, it's Gluetun, not qBittorrent: the VPN
  needs valid `WIREGUARD_*` creds in `.env` or the shared namespace has no
  internet. Check `hs logs gluetun`.
- Downloads land in `/data/torrents` (already mounted). The *arr create their own
  categories when you add the client below, so you rarely touch this by hand.

### SABnzbd (usenet) — host `sabnzbd`, port `8080`
- Browser: `http://<server-ip>:${SABNZBD_PORT}`. Run the wizard, add your usenet
  provider.
- **Config → Folders:** set **Temporary (incomplete) folder = `/data/incomplete`**
  (local SSD scratch); leave **Completed = `/data/usenet`** (the array). par2
  repair/unpack is heavy random I/O and stalls on a NAS mount — keep scratch local.
- API key: **Config → General → API Key** (or let `hs keys` auto-detect it).

## 2. Prowlarr — the indexer hub · `http://<server-ip>:${PROWLARR_PORT}`
Prowlarr manages indexers **once** and pushes them to every *arr automatically —
you never add indexers in Sonarr/Radarr directly.
1. **Indexers → Add Indexer** — add your torrent/usenet trackers.
2. Indexers behind Cloudflare? **Settings → Indexers → Add proxy → FlareSolverr**,
   Host `http://flaresolverr:8191`, give it a tag (e.g. `flaresolverr`), then add
   that tag to the indexers that need it.
3. **Settings → Apps → Add** one entry per *arr:
   - **Prowlarr Server:** `http://prowlarr:9696`
   - **<App> Server:** `http://sonarr:8989` (radarr `:7878`, lidarr `:8686`,
     whisparr `:6969`)
   - **API Key:** that app's **Settings → General** (or run `hs keys` and read it
     from `.env`)

   Prowlarr now syncs all indexers into that app.

## 3. Sonarr / Radarr / Lidarr
For each app (Sonarr `:${SONARR_PORT}`, Radarr `:${RADARR_PORT}`, Lidarr
`:${LIDARR_PORT}`):
1. **Settings → Download Clients → Add:**
   - **qBittorrent** — Host `gluetun`, Port `${BITTORRENT_PORT}`, your qBit login.
   - **SABnzbd** — Host `sabnzbd`, Port `8080`, the SAB API key.
2. **Settings → Media Management → Root Folders → Add:**
   - Sonarr → `/data/tv` · Radarr → `/data/movies` · Lidarr → `/data/music`
     (any folder name under `/data` is fine — match your Jellyfin libraries).
3. Indexers should already be present, synced from Prowlarr — confirm under
   **Settings → Indexers**.

## 4. Quality profiles — already done for you
Recyclarr seeds TRaSH-Guides quality profiles into Sonarr/Radarr automatically
(`mediastack/recyclarr/recyclarr.yml`). Just set `SONARR_API_KEY` /
`RADARR_API_KEY` in `.env`; it syncs on its daily tick, or force it now:
`docker exec recyclarr recyclarr sync`. See
[INSTALL.md → Recyclarr](INSTALL.md#recyclarr).

## 5. Seerr — family requests · `http://<server-ip>:${SEERR_PORT}`
1. Sign in with your Jellyfin/Plex account (the front door for requests).
2. **Settings → Services → Add Sonarr / Radarr:** Hostname `sonarr` / `radarr`,
   port `8989` / `7878`, the API key; pick the root folder + quality profile from
   step 3. Family requests now flow straight into the *arr.

## 6. Bazarr — subtitles
**Settings → Sonarr / Radarr:** Address `sonarr` / `radarr`, port `8989` / `7878`,
API key. Add subtitle sources under **Settings → Providers**.

## Already wired for you (no setup)
- **Unpackerr** extracts archived downloads — paths pre-set in compose
  (`/data/torrents/*`, `/data/usenet/*`).
- **Decluttarr** clears stalled/failed grabs automatically.
- **Recyclarr** quality profiles (above).

## Quick sanity test
In Sonarr: add a show → **Interactive Search** an episode → grab a release. It
should appear in qBittorrent/SAB, download under `/data/torrents` (or
`/data/usenet`), and **hardlink-import** into `/data/tv` within a minute or two.
If the grab never starts, re-check the download-client **Host** (`gluetun`, not
`qbittorrent`) and that Gluetun's VPN is connected (`hs logs gluetun`).
