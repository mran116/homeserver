# Tdarr — automatic library transcoding (optional, OFF by default)

Tdarr re-encodes your library to a smaller codec (HEVC/x265) to reclaim disk
space. It's **off unless you opt in**, because it's heavy and — importantly — it
**replaces your original files**. Read the warning before enabling.

## Turn it on

1. **Enable the profile** — add `tdarr` to `COMPOSE_PROFILES` in `.env`:
   ```
   COMPOSE_PROFILES=jellyfin,tdarr
   ```
2. **(Recommended) hardware encoding.** If the host has an Intel iGPU
   (`/dev/dri/renderD128` exists), use it — it's ~10× faster and far lighter on
   CPU than software encoding.
   - Set the render group in `.env`:  `RENDER_GID=$(getent group render | cut -d: -f3)`
     (on this host that's `992`).
   - Enable the GPU block in `mediastack/docker-compose.override.yml` (copy from
     `docker-compose.override.yml.example` if you don't have it):
     ```yaml
     services:
       tdarr:
         devices:
           - /dev/dri:/dev/dri
         group_add:
           - "${RENDER_GID:-render}"
     ```
   No GPU? Skip step 2 — Tdarr falls back to (slow) CPU encoding.
3. **Deploy:** `hs up mediastack`
4. Open the UI at `http://<server>:${TDARR_PORT:-8265}`.

## Recommended flow (avoids the classic A/V-sync drift)

Tdarr runs your transcodes through a **flow** built on the **HandBrake** engine.
Tdarr is notorious for audio drifting out of sync — these three settings prevent
it. Build a HandBrake flow with:

| Setting | Value | Why |
|---|---|---|
| **Video codec** | **HEVC / x265**, via **QSV** (QuickSync) if you enabled the GPU | the space saving; QSV = fast/low-CPU |
| **Framerate** | **same as source** | the #1 cause of drift — never let it re-time, especially variable-frame-rate phone/streaming files |
| **Audio** | **passthrough** (copy, don't re-encode) | keeps perfect sync + quality, and is faster |
| **Container** | **MKV** | robust for HEVC + multiple audio/subtitle tracks |

In the UI: add a **Library** → source `/media` (or a subfolder like
`/media/movies`), transcode cache `/temp`, attach the flow above, then set worker
counts. The internal node auto-registers.

## ⚠️ It replaces your originals — be careful

Tdarr writes the new file to `/temp` and then **swaps out the original**. That's
the point (it shrinks the library), but it *modifies media*:

- **Test on one small library / a copy first** and watch a few transcodes before
  letting it loose on everything.
- Backups do **not** cover media (`BACKUP_PATH` skips it by design), so a
  transcode that mangles a file is **not recoverable** — the source is gone.
- `TDARR_CACHE` needs free space (it holds the re-encoded file before the swap).
  Keep it on a **local** disk, not the NAS.

If unsure, leave Tdarr off — it's purely a space optimization, not required for
anything to work.
