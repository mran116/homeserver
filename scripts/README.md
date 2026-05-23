# scripts/

Helper scripts for setting up and maintaining the homeserver. They're
**location-independent** (each resolves the repo root from its own path) and
share `lib/common.sh`.

Most are **plan-then-apply**: they print what they'd change, then ask before
doing it. Flags:
- `--dry-run` — preview only, change nothing
- `--yes` — apply without prompting (used by cron / `bootstrap.sh --yes`)

## When to run what

| Situation | Run |
|---|---|
| Brand-new bare Ubuntu/Debian box | `./scripts/setup-fresh.sh` (installs Docker etc., then bootstrap) |
| First-time setup of this repo on a host | `./bootstrap.sh` — **once** |
| Routine "pull latest + redeploy" on a running host | `./scripts/update.sh` |
| "Is anything wrong / what changed?" | `./scripts/doctor.sh` (read-only) |
| New vars appeared in `.env.example` after a pull | `./scripts/env-sync.sh` |
| Stack `.env` symlink missing / `STACKS_PATH` wrong | `./scripts/link-env.sh` |
| A blank machine secret needs generating | `./scripts/gen-secrets.sh` |
| Tidy `.env` back into the template layout | `./scripts/env-rebuild.sh` |
| (Re)install the maintenance cron jobs | `./scripts/schedule-maintenance.sh` |

**`bootstrap.sh` is for the first run.** It's the orchestrator that runs the setup
steps below in order. It's safe to re-run (idempotent), but on a **live** stack
you rarely need to — run the one specific step instead, or `./scripts/update.sh`
to pull + redeploy. **`doctor.sh` will tell you which step to run** if something's
off.

## Setup steps

| Script | What it does |
|---|---|
| `lib/common.sh` | Shared helpers (colours, prompts, `.env` read/write, plan/gate, `require_*`). Sourced, not run. |
| `env-init.sh` | Create `.env` from `.env.example` (prompts for system values). No-op if `.env` exists. |
| `env-sync.sh` | Append vars added to `.env.example` that are missing from `.env`. |
| `env-rebuild.sh` | Rewrite `.env` into `.env.example`'s structure, keeping your values (extras parked in a `LOCAL EXTRAS` block). |
| `gen-secrets.sh` | Fill blank machine secrets; skips DB passwords whose data dir already exists. |
| `make-dirs.sh` | Create the data/media dir layout and seed Homepage config. |
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
