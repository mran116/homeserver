# Pulse — Proxmox + Docker metrics & alerts

[Pulse](https://github.com/rcourtman/Pulse) is the metrics-and-alerting layer for this
stack. One light service monitors **two layers** with no cloud account and no node cap:

- **Proxmox / PBS** — nodes, VMs, LXCs, storage, backup jobs — *agentless*, polls the
  Proxmox API with a read-only token.
- **Docker** — per-container CPU/RAM/network + temps, with history — via a small agent
  installed **on the Docker host** (not a container) that pushes metrics to Pulse.

Alerts (node/guest down, OOM, failed backup, storage full, SMART failing) route to your
phone through **ntfy**. Login reuses your shared `APP_USERNAME` / `APP_PASSWORD`.

> This is the step-by-step install. For the *why* (metrics vs logs, Pulse vs the log
> profiles) and **alert tuning**, see [`observability.md`](observability.md).

---

## 1. Choose where Pulse runs

| | **LXC on Proxmox** (recommended) | **Docker container** (`metrics` profile) |
|---|---|---|
| Survives a Docker-VM reboot/crash | ✅ yes — it's outside the VM it watches | ❌ dies with the VM |
| Managed by this repo (`hs`, certs, updates) | ❌ you manage it | ✅ yes |
| Best for | Proxmox hosts | non-Proxmox / single-box setups |

A monitor shouldn't live inside the thing it monitors — on Proxmox, **prefer the LXC**.
The Docker agent (section 3) is identical either way.

### Path A — LXC (recommended)

1. Deploy Pulse in an LXC (there's a community install script for Proxmox). Note its IP
   and port (default `7655`).
2. **Do _not_** enable the `metrics` profile — that would start a redundant Docker
   container. If you previously ran it, remove it: `hs disable metrics`.
3. Point the Homepage tile at the LXC. In `.env`:
   ```ini
   PULSE_PORT=7655
   PULSE_HOST=<pulse-lxc-ip>   # the LXC IP — IP ONLY, no port (see gotcha below)
   ```
   then sync + recreate the dashboard:
   ```sh
   ./scripts/make-dirs.sh --yes     # sync Homepage config (repo is source of truth)
   hs up dashboard                  # recreate Homepage so it picks up the new vars
   ```
   The tile uses a `siteMonitor` HTTP ping, so the green dot resolves whether Pulse is
   local or remote.

   > ⚠️ **`PULSE_HOST` gotcha:** set it to the **IP only**. The Homepage template already
   > appends `:{{PULSE_PORT}}`, so `PULSE_HOST=<pulse-lxc-ip>:7655` renders the broken
   > `http://<pulse-lxc-ip>:7655:7655` (doubled port → dead link + dead status dot).

### Path B — Docker container

```sh
hs enable metrics
```
Adds the `metrics` profile, redeploys the monitoring stack, and prints the post-steps.
Open it at `pulse.<your-domain>` (or `:7655`). Then continue with sections 2–4.

---

## 2. Finish the Pulse security wizard

Open Pulse, log in with `APP_USERNAME` / `APP_PASSWORD`, and complete the first-run
security wizard. (Falls back to `admin`/`admin` only if `APP_*` are unset.)

---

## 3. Add Proxmox metrics — read-only API token

Pulse polls the Proxmox API; it needs a **read-only** token (`PVEAuditor`).

**Proxmox shell (fastest):**
```sh
pveum user add pulse@pve --comment "Pulse monitoring (read-only)"
pveum user token add pulse@pve monitor --privsep 0      # prints the secret ONCE — copy it
pveum acl modify / --roles PVEAuditor --tokens 'pulse@pve!monitor'
```

**Or the GUI:** *Datacenter → Permissions → Users* (add `pulse@pve`) → *API Tokens*
(add `monitor`, **uncheck "Privilege Separation"**, copy the secret) → *Permissions →
Add → API Token Permission* (Path `/`, token `pulse@pve!monitor`, role `PVEAuditor`,
Propagate ✓).

Then in Pulse: **Settings → Nodes → Add** → URL `https://<proxmox-ip>:8006`, Token ID
`pulse@pve!monitor`, and the secret. The node should go green. `PVEAuditor` is strictly
read-only — it can see everything, change nothing.

> Running **PBS** too? Create a separate token in the PBS UI (*Configuration → Access
> Control → API Token*, role `Audit`/`DatastoreAudit`) and add it as a PBS node.

---

## 4. Add Docker metrics — the host agent

Per-container CPU/RAM needs a small agent **on the Docker host** (it reads the local
docker socket and pushes to Pulse — the Pulse server never needs the socket).

1. In Pulse: **Settings → Agents** → copy the one-line installer. It already bakes in
   the Pulse URL **and** an API token (you don't create this token by hand):
   ```sh
   curl -fsSL http://<pulse-host>:7655/install.sh | sudo bash -s -- \
     --url http://<pulse-host>:7655 --token <baked-in-token> --interval 30s
   ```
2. Run it **on the Docker VM** (must be **root** — use `sudo`). It installs a
   `pulse-agent` systemd service and stores the token at `/var/lib/pulse-agent/token`.
3. The host + all containers appear in Pulse within a poll cycle.

**Verify:**
```sh
systemctl is-active pulse-agent          # active
journalctl -u pulse-agent -n 20          # "host report sent" / "Report sent to Pulse targets"
```

> 🟡 **"Names show up but no CPU/RAM yet" is normal.** CPU% is a *delta* — it needs two
> samples one interval apart. The first sample logs *"First CPU sample collected, no
> previous data for delta calculation"* and renders blank; the next interval fills in
> real numbers. Every agent restart resets that baseline, so just wait ~60–90 s.

Optional host extras for temps/SMART (otherwise those panels stay empty):
```sh
sudo apt install lm-sensors smartmontools
```

---

## 5. Route alerts → ntfy

In Pulse **Settings → Alerts/Notifications**, add a **webhook** channel pointing at the
ntfy service in this stack:
```
http://ntfy/<topic>                       # in-stack
https://ntfy.<your-domain>/<topic>        # via Caddy / when away
```
then subscribe to that topic in the ntfy app. See
[`network-and-remote-access.md`](network-and-remote-access.md) for away-from-home push.

**Before you trust the alerts, tune them** — Pulse is chatty by default and the memory
rule false-fires on cache. See **[Alert tuning — avoid false alarms](observability.md#alert-tuning--avoid-false-alarms)**.

---

## 6. Fix the memory gauge (per VM)

Proxmox reports guest memory as `total − free`, which counts reclaimable page cache as
"used" — a healthy VM reads **85–90%** while real usage is **~20%**, and the memory
alert pages you for nothing. Give each VM a **balloon device** so it reports its real
free/available up to Proxmox:

1. Proxmox → VM → **Hardware → Memory → Advanced → tick "Ballooning Device"**
   (CLI: `qm set <vmid> --balloon <MiB>`; `--balloon 0` *disables* it). Set
   *Minimum memory = Memory* for stats-only with no reclaiming; a lower minimum lets
   the host reclaim, but only under **host** memory pressure.
2. Install the guest agent in the VM and tick **VM → Options → QEMU Guest Agent**:
   ```sh
   sudo apt install qemu-guest-agent && sudo systemctl enable --now qemu-guest-agent
   ```
3. The balloon usually hot-plugs (no reboot needed). **Verify** — note `lsmod` shows
   *nothing* when the driver is built into the kernel, so check the device binding
   instead:
   ```sh
   for d in /sys/bus/virtio/devices/virtio*; do
     echo "$(basename $d): $(basename $(readlink $d/driver))"
   done | grep balloon
   # → virtioN: virtio_balloon  = working
   ```
   The Pulse memory tile then drops from ~90% to the real ~20%.

---

## Troubleshooting cheatsheet

| Symptom | Cause / fix |
|---|---|
| Homepage Pulse tile link is `…:7655:7655` | `PULSE_HOST` has the port — set IP only, `hs up dashboard` |
| Tile dot red but Pulse is up | tile container stale — `docker compose up -d --force-recreate homepage` |
| Containers listed, no CPU/RAM | CPU-delta warm-up — wait ~60–90 s (see §4) |
| No temps / SMART | install `lm-sensors` / `smartmontools` on the host |
| `lscr.io … authentication required` in agent log | image *update-check* only, **not** metrics — harmless |
| VM memory pegged ~90% | page cache counted as used — enable the balloon device (§6) |
| Redundant Pulse running on the Docker VM | you enabled `metrics` while also running the LXC — `hs disable metrics` |
