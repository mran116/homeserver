# Theming — make Jellyfin (and the whole stack) look polished

Jellyfin's default UI is the main thing people miss vs Plex. Custom CSS closes
most of that gap, and you can theme the *arr apps to match for a consistent look.

These settings live in **each app's own config** (not in this repo), so it's a
**one-time paste** per app. They're `@import` URLs, so the themes **auto-update**
from upstream — nothing to maintain.

## Jellyfin

**Dashboard → General → Custom CSS**, paste ONE of these, Save, refresh:

**Option A — a media-center-polished theme (recommended for Jellyfin):**
```css
@import url("https://cdn.jsdelivr.net/gh/CTalvio/Ultrachromic@latest/presets/ultrachromic.css");
```
Other popular standalone themes (swap the URL): **Finile**, **Ciri**, **Zombie**,
**Kosmos** (search "Jellyfin <name> theme css"). Try a couple — it's just the URL.

**Option B — match the rest of your stack (theme.park):**
```css
@import url("https://theme-park.dev/css/base/jellyfin/dark.css");
```
Swap `dark` for `dracula`, `nord`, `hotline`, `plex`, `aquamarine`, etc.

> Per-user: each Jellyfin user can also set a theme under their own Display
> settings; the Custom CSS above is server-wide.

## The *arr + downloaders (theme.park) — consistent look across the stack

theme.park themes Sonarr, Radarr, Lidarr, Prowlarr, Bazarr, SABnzbd, qBittorrent
and more, so everything shares one color scheme. Two ways:

1. **Custom CSS field** (apps that have one, e.g. via their UI settings): paste
   ```css
   @import url("https://theme-park.dev/css/base/<app>/<theme>.css");
   ```
   (e.g. `sonarr/dark`, `radarr/nord`).
2. **Sidecar injection** (apps with no CSS field): theme.park's lightweight addon
   injects the CSS. See theme-park.dev for the per-app snippet.

Pick the **same theme name** everywhere (e.g. all `nord`) for a unified UI.

## Homepage (your dashboard)

Homepage is themed via its own config (already in this repo under
`dashboard/homepage/`): set the theme + accent color in `settings.yaml`:
```yaml
theme: dark
color: slate      # or zinc, gray, neutral, stone, red, rose, etc.
```
That one's version-controlled, so it deploys with the stack.

## Why these aren't baked into the repo

Jellyfin/​*arr store custom CSS in their own databases (set via the admin UI),
not a mountable file — so the repo can't ship them as config. The `@import` URLs
above are the closest thing: paste once per app, and the theme tracks upstream.
Homepage is the exception (real config file), so its theme *is* in the repo.
