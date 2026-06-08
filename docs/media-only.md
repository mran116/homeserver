# Deploy only the media components

You don't need a separate repo to run just the media server + downloaders. This stack is
modular on two levels:

- **`hs stacks`** chooses which *stacks* deploy (state in gitignored `.stacks.local`, survives `git pull`).
- **`COMPOSE_PROFILES`** (in `.env`) chooses optional *services within* a stack (e.g. Jellyfin vs Plex, Tdarr).

## What a media-only deployment needs

| Component | Where | Required? |
|---|---|---|
| **mediastack** — media server, *arr apps, SABnzbd, qBittorrent, built-in `gluetun` VPN | `mediastack/` | **yes** |
| **infrastructure** — runs **Caddy** (reverse proxy) for `https://jellyfin.${DOMAIN}` | `infrastructure/` | recommended |
| **`home` docker network** | created by `scripts/create-network.sh` (via `bootstrap.sh`) | auto — not a stack |

The torrent VPN (`gluetun`) is **inside** mediastack, so no other stack is needed for it. Skip
`infrastructure` and services still run — you just reach them at `${SERVER_IP}:<port>` instead of
nice HTTPS hostnames.

## Steps

1. **Clone + bootstrap** (creates the `home` network, data dirs, and `.env`):
   ```bash
   git clone <repo-url>
   cd <repo>
   ./bootstrap.sh
   ```

2. **Enable only the media stacks** (everything else excluded, remembered in `.stacks.local`):
   ```bash
   hs stacks disable arcane vaultwarden monitoring dashboard household fitness records knowledge syncthing cloud devops
   # leaves: mediastack + infrastructure
   ```

3. **Pick your media server** — set in `.env`:
   ```ini
   COMPOSE_PROFILES=jellyfin     # or: plex   (or both: jellyfin,plex)
   # add tdarr for library transcoding, e.g. jellyfin,tdarr
   ```

4. **Set the essentials** in `.env`:
   - `MEDIA_PATH` — where your library lives
   - `gluetun` VPN provider + credentials — **required**, or qBittorrent won't start

5. **Deploy:**
   ```bash
   hs up
   ```

## Notes

- **No `infrastructure`?** Services still run, reachable at `${SERVER_IP}:<port>` (Jellyfin `8096`, etc.) — you just lose the Caddy HTTPS hostnames.
- **qBittorrent routes through `gluetun`** — if the VPN isn't configured, qBittorrent stays down by design (no leaks).
- **Add more later:** `hs stacks enable <stack>` then `hs up <stack>`.
- **GPU transcoding** (Intel Quick Sync / NVIDIA) is per-host — configure it in the gitignored `mediastack/docker-compose.override.yml` (see `mediastack/docker-compose.override.yml.example`) and set `RENDER_GID`.
