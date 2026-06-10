# Ansible — provision a homeserver host

Stand up the **host layer** for this stack on any machine — yours or a friend's
— from a single per-host vars file, then hand off to the repo's own turn-key
bootstrap. Agentless: plain SSH, no control node, no daemons.

## What it does (and the line it won't cross)

Ansible owns the **host**: OS packages, timezone, kernel/grub params, NFS
mounts, systemd units, SMART monitoring, Docker install, and **cloning this
repo**. It then **stops and hands off** to `bootstrap.sh` / `hs` for the
container stack — that stays the repo's job, so there's one source of truth.
Appliances (Synology / Home Assistant OS / OpenWrt) are out of scope; manage
those via their own UI/API.

## The model: fill out vars, point, run

Every behaviour is a variable that **defaults to off**. A host opts in via
`host_vars/<name>.yml`. No vars = a safe no-op. Real values (IPs, hostnames)
live in **gitignored** `inventory/hosts.yml` + `host_vars/*.yml`; the repo ships
`.example` templates — same pattern as `.env`.

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml   # once

cp inventory/hosts.example.yml inventory/hosts.yml
cp host_vars/example.yml       host_vars/myhost.yml      # name == inventory host
$EDITOR inventory/hosts.yml host_vars/myhost.yml

ansible all -m ping                       # connectivity
ansible-playbook site.yml --check --diff  # PREVIEW — no changes
ansible-playbook site.yml                 # apply
```

**Always `--check --diff` first.** Roles are written to match *live* config, so
a check against a healthy, already-set box reports **no changes** — a diff means
drift.

## Deploy the whole thing on a fresh box (e.g. a friend's)

1. Add the box to `inventory/hosts.yml` (its IP + an SSH user with sudo).
2. `cp host_vars/example.yml host_vars/<name>.yml` and set:
   `homeserver_stack_enabled: true`, `install_docker: true`, plus any
   `nfs_mounts` / tuning that box needs.
3. `ansible-playbook site.yml --limit <name>` → installs Docker, clones the repo
   to `/opt/docker/stacks`, and prints the hand-off.
4. On the box: `cd /opt/docker/stacks && ./bootstrap.sh` (creates `.env` +
   secrets + network, installs `hs`), then `hs up`.

> The stack bring-up stays a deliberate, eyes-on step (it wants real secrets —
> ideally `ansible-vault` / SOPS-managed, not plaintext). Ansible gets the box
> to "ready for `hs setup`"; you pull the trigger.

## Roles

| Role | Opt-in var | Does |
|---|---|---|
| `base` | `base_timezone`, `base_extra_packages` | timezone + packages |
| `kernel_cmdline` | `kernel_cmdline_params` | manage GRUB kernel params (no reboot) |
| `cpu_turbo` | `cpu_turbo_disabled` | disable CPU turbo (thermal mitigation) |
| `smart_monitoring` | `smart_monitoring_enabled` | smartd self-tests + optional ntfy alerts |
| `nfs_mounts` | `nfs_mounts` | NFS shares via fstab |
| `homeserver_stack` | `homeserver_stack_enabled` | Docker + clone repo + hand off |

See `host_vars/example.yml` for every knob.
