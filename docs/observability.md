# Observability — metrics, logs & alerts

The monitoring stack is built from small, single-purpose pieces so you only run
what you need. Three things are always on; the rest are opt-in profiles.

| Layer | Tool | Always on? | What it's for |
|---|---|---|---|
| Service up/down | **Uptime Kuma** | yes | heartbeat checks; HA reads it |
| Live logs | **Dozzle** | yes | real-time tail of any container |
| Image updates | **Diun** | yes | "an update exists" → ntfy |
| Push hub | **ntfy** | yes | every alert lands on your phone |
| **Metrics + alerts** | **Pulse** | `metrics` | Proxmox + Docker metrics & alerting |
| **Old-log history** | **lnav** | host CLI | browse/search logs after the fact |
| **Central log retention** | **Vector** | `logs` | ndjson log tree for lnav (light) |
| **Indexed log search** | **Loki + Grafana + Alloy** | `logging` | full-text search + dashboards (heavy) |

The design splits four concerns that are easy to conflate: **metrics** (Pulse),
**live logs** (Dozzle), **log history** (lnav, fed by Vector or just Docker's own
files), and **heavy log analytics** (the optional Loki profile).

---

## Metrics & alerts — Pulse (`hs enable metrics`)

> **Setting it up?** See the step-by-step **[Pulse install guide](pulse.md)** (LXC vs
> container, the Proxmox token, the Docker agent, ntfy, and the memory-gauge fix). This
> section is the overview + design rationale.

[Pulse](https://github.com/rcourtman/Pulse) monitors **two layers**, with no cloud
account and no node cap:

- **Proxmox / PBS** — nodes, VMs, LXCs, storage, backup jobs. *Agentless*: it polls
  the Proxmox API. Add a host in **Settings → Nodes** with a read-only API token
  (Datacenter → Permissions → API Tokens).
- **Docker** — per-container CPU/RAM/network + temps, with history. This needs the
  **Pulse agent installed on the Docker host** (it's a host install, *not* a
  container). Grab the one-line command from **Settings → Agents** — it bakes in an
  API token and pushes metrics to the server. The Pulse *server* does **not** need
  the Docker socket.

Login reuses your shared `APP_USERNAME` / `APP_PASSWORD`. Open it at
`pulse.<your-domain>` (or `:7655`).

### Alerts → ntfy

Pulse alerts on node-down, container OOM/misbehaving, failed backups, storage full,
etc. Route them to your phone in **Settings → Alerts/Notifications**: add a
**webhook** pointing at the ntfy service in this stack — `http://ntfy/<topic>` —
then subscribe to that topic in the ntfy app. (See `docs/network-and-remote-access.md`
for getting ntfy push working when you're away from home.)

### Alert tuning — avoid false alarms

Out of the box Pulse is chatty, and the **memory** rule is the worst offender. Proxmox
(and therefore Pulse, which reads the Proxmox API) reports guest memory as
`total − free`, which **counts reclaimable page cache as "used."** A healthy VM that's
filled idle RAM with disk cache will read **85–90%** while its *real* usage
(`total − available`, i.e. `MemAvailable`) is closer to **20%** — so a default memory
threshold pages you for nothing. (On a ZFS host the **ARC** does the same thing: it
grabs up to ~50% of RAM by default and shows as used though it's reclaimable.)

Fix the **metric** first, then tune the **rules**:

1. **Make the number honest (root cause).** Give each VM a **balloon device** so the
   guest reports its real free/available up to Proxmox:
   - Proxmox → VM → **Hardware → Memory → Advanced → tick "Ballooning Device"**
     (CLI: `qm set <vmid> --balloon <MiB>`; `--balloon 0` *disables* it). Set
     *Minimum memory = Memory* if you want stats-only with no reclaiming; a lower
     minimum lets the host reclaim, but only ever under **host** memory pressure.
   - Install the guest agent in the VM (`apt install qemu-guest-agent`, enable it,
     and tick **VM → Options → QEMU Guest Agent**) for graceful shutdown, fstrim, IPs.
   - Reboot the VM so the driver binds cleanly, then the tile drops to the real ~20%.
   - **Verify the balloon on a kernel where it's built-in** (so `lsmod` shows nothing):
     `for d in /sys/bus/virtio/devices/virtio*; do echo "$(basename $d): $(basename $(readlink $d/driver))"; done | grep balloon`
     → `virtioN: virtio_balloon` means it's working.

2. **Tune the rules (do regardless).** In Pulse **Settings → Alerts**:
   - **Require a sustained duration** (fire only if the condition holds ~5–10 min, not
     on a single poll) — this alone kills most transient-spike noise.
   - **Per-guest overrides** — until a VM's balloon is enabled, raise or disable *its*
     memory rule specifically instead of dumbing down the global threshold.
   - **Keep the rules that mean "something is actually wrong"** — node/guest **down**,
     **OOM kill**, **failed backup**, **storage >90%**, **SMART failing** — and turn
     off the chatty ones (transient per-container CPU/network spikes).
   - **Gate the webhook to warning/critical** so info-level noise never reaches ntfy.

### Docker vs. LXC — where to run Pulse

The repo ships Pulse as a **Docker container** (the `metrics` profile) because it's
portable — it works on any Docker host, and `hs`/GitOps manage its updates and cert.
That's the right default for most people.

**On Proxmox, consider running Pulse as its own LXC instead.** A monitor shouldn't
live inside the thing it monitors: if Pulse runs in the Docker VM and that VM
crashes, Pulse dies with it and can't tell you the VM is down. As an LXC on Proxmox
it survives the VM and still alerts. Trade-off: an LXC lives *outside* this repo, so
you handle its updates, backup, and reverse-proxy route yourself.

If you go LXC:
1. Deploy Pulse in an LXC (there's a community install script for Proxmox).
2. **Don't** enable the `metrics` profile (skip the Docker Pulse container).
3. Still install the **Docker agent** on the Docker VM — point it at the LXC's
   address instead of localhost. The agent is identical either way.

(Catching a *whole Proxmox host* going down needs something off-box — a cheap
external uptime check — which is a separate layer.)

---

## Logs

### Live — Dozzle (always on)

Real-time tail of any container at `logs.<your-domain>` (or `:${DOZZLE_PORT}`).
**Multi-host:** run a Dozzle *agent* on each extra Docker host and add its address
to the main Dozzle — every host's live logs then show in one UI.

### History — lnav (host CLI)

`lnav` is the Log File Navigator — it merges many log files into one time-ordered,
color-coded, **searchable** view (it even speaks SQL over logs). It's installed on
the host by `setup-fresh.sh` (or `sudo apt install lnav`); it is **not** a container.

- Without the `logs` profile, point it at Docker's own rotated logs:
  `sudo lnav /var/lib/docker/containers/*/*.log`
- With the `logs` profile on, point it at Vector's clean ndjson tree (below).

### Central retention — Vector (`hs enable logs`)

[Vector](https://vector.dev) is a tiny shipper. It tails every container via the
Docker API and writes **one ndjson file per container per day** under
`${CONFIG_PATH}/logs`, which lnav reads:

```sh
lnav -i monitoring/vector/lnav-docker.json   # one-time: install the log format
sudo lnav ${CONFIG_PATH}/logs                # browse everything, merged by time
```

The config (`monitoring/vector/vector.toml`) does **no transforms** — so there's no
VRL to learn; it's ~10 readable lines. This is the **featherweight** central-log
option (~50 MB, one container). For another Docker host, run the same Vector there
and point its sink at a shared location (or swap the `file` sink for a `loki` sink).

### Indexed search — Loki + Grafana + Alloy (`hs enable logging`)

The **heavy** option (~3 containers, ~250–400 MB): Alloy collects every container
log *and* the host journal → Loki stores/indexes them → Grafana gives label-based
**full-text search + dashboards + retention policies**. Reach for this only when you
outgrow lnav (e.g. "show me every 500 across all hosts last week"). Grafana login
reuses `APP_USERNAME` / `APP_PASSWORD`.

**Vector vs. Loki** aren't rivals — Vector is a *pipe*, Loki is a *reservoir*. Start
light (Vector → files + lnav); if you ever need indexed search, point that same
Vector at Loki and turn on Grafana. No rework.
