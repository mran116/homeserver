# scripts/

These are the building blocks behind the **`hs`** command — the single
entrypoint for the homeserver. You rarely call them directly; run `hs <command>`
instead. `hs` works from **any directory** (it resolves the repo location
itself), so you never need to `cd` in.

```sh
hs install     # symlink `hs` onto your PATH, then just type `hs ...` anywhere
hs help        # list every command
hs <cmd> -h    # help for one command
```

The scripts are **location-independent** and share `lib/common.sh`. Most are
**plan-then-apply**: they print what they'd change, then ask. Flags are the same
everywhere: `-n/--dry-run` (preview), `-y/--yes` (no prompt), `-h/--help`.

## When to run what

| Situation | Command |
|---|---|
| Brand-new bare Ubuntu/Debian box | `hs setup --fresh` |
| First-time setup of this repo on a host | `hs setup` — **once** |
| Routine "pull latest + redeploy" | `hs update` |
| "Is anything wrong / what changed?" | `hs doctor` (read-only) |
| Start / stop / restart stacks | `hs up` / `hs down` / `hs restart [stack]` |
| New vars appeared in `.env.example` after a pull | `hs env sync` |
| Tidy `.env` back into the template layout | `hs env tidy` |
| A blank machine secret needs generating | `hs secrets` |
| Pull app API keys for the dashboard | `hs keys` |
| (Re)install the maintenance cron jobs | `hs cron` |

**`hs setup` is the first run** — it orchestrates the setup steps below in order
(idempotent). After that, **`hs doctor` tells you which command to run** if
something's off, and `hs update` handles routine pull + redeploy.

The tables below document the underlying scripts (what each `hs` command runs).

## Setup steps

| Script | What it does |
|---|---|
| `lib/common.sh` | Shared helpers (colours, prompts, `.env` read/write, plan/gate, `require_*`). Sourced, not run. |
| `env-init.sh` | Create `.env` from `.env.example` (prompts for system values). No-op if `.env` exists. |
| `env-sync.sh` | Append vars added to `.env.example` that are missing from `.env`. |
| `env-rebuild.sh` | Rewrite `.env` into `.env.example`'s structure, keeping your values (extras parked in a `LOCAL EXTRAS` block). |
| `gen-secrets.sh` | Fill blank machine secrets; skips DB passwords whose data dir already exists. |
| `make-dirs.sh` | Create the data/media dir layout and sync Homepage config (repo → config dir). |
| `link-env.sh` | Set `STACKS_PATH` and symlink the root `.env` into each stack folder. |
| `create-network.sh` | Create the shared external `home` docker network. |
| `schedule-maintenance.sh` | Install the cron jobs (see below). |

## Operations

| Script | What it does |
|---|---|
| `doctor.sh` | Read-only health check (docker, `home` net, `.env` sync, symlinks, compose validity, blank required vars, port-53 conflict). Non-zero exit on hard failures. |
| `update.sh` | `git pull` (autostash) then redeploy all stacks. |
| `stack.sh` | Bulk `up`/`down`/`restart`/`pull`/`status` across stacks in dependency order. |
| `harvest-keys.sh` | Collect app API keys into `.env` (auto-detects *arr keys; `--sync` recreates consumers on change). |
| `sab-watchdog.sh` | Auto-recover a stalled SABnzbd (pause/resume, then container restart). Run by cron. |
| `setup-fresh.sh` | Full host prep for a brand-new Ubuntu/Debian box, then runs `bootstrap.sh`. |
| `install-hooks.sh` | Install a git pre-push hook that validates every stack's compose locally before a push (same check as CI, caught earlier). |

## Scheduled jobs (installed by `schedule-maintenance.sh`)

It writes these into your user crontab, each tagged with a marker comment so
re-running is idempotent. Logs land in the repo root.

| Schedule | Job | Command | Log | Marker |
|---|---|---|---|---|
| `0 4 * * *` (daily 04:00) | *arr API key auto-sync | `harvest-keys.sh --sync` | `key-sync.log` | `# homestack-key-sync` |
| `0 5 * * 0` (Sun 05:00) | Unused-image cleanup | `docker image prune -af` | `image-prune.log` | `# homestack-image-prune` |
| `*/5 * * * *` (every 5 min) | SABnzbd stall watchdog | `sab-watchdog.sh` | `sab-watchdog.log` | `# homestack-sab-watchdog` |

Remove any of them with `crontab -e` (delete the line with the matching
`homestack-*` marker). Re-add them anytime with `./scripts/schedule-maintenance.sh`.
