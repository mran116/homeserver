# CrowdSec — intrusion detection + prevention (opt-in)

CrowdSec watches your logs, **detects** attacks (brute-force, scanners, CVE
probes) and **blocks** the offenders — plus it pulls a **community blocklist** so
known-bad IPs are blocked before they ever hit you. Worth turning on once you
expose anything publicly (Vaultwarden, the Cloudflare tunnel, the direct Jellyfin
port). Off by default.

## Two parts (and why)

1. **Engine** — a container (`COMPOSE_PROFILES=crowdsec`). Reads Caddy's JSON access logs (mounted at `/var/log/caddy`) +
   host SSH auth, runs detection scenarios + the community blocklist, and exposes
   a **local API** on `127.0.0.1:8080`. This is detection + decisions + console
   visibility. Safe — it touches nothing on the host.
2. **Firewall bouncer** — the **enforcer**. CrowdSec ships it as an **OS package,
   not a container**, so it runs on the host and blocks banned IPs in iptables
   (incl. Docker's `DOCKER-USER` chain, so bans apply to your published container
   ports). Installed/wired by `scripts/install-crowdsec-bouncer.sh`.

The engine alone tells you who's attacking; the bouncer actually blocks them.

## Turn it on

1. `hs secrets` → fills `CROWDSEC_BOUNCER_KEY`.
2. Add `crowdsec` to `COMPOSE_PROFILES`; `hs up infrastructure` → engine starts and
   auto-registers the bouncer key. (Optionally set `CROWDSEC_ENROLL_KEY` from
   app.crowdsec.net first for a web dashboard.)
3. Install the enforcer on the host:  `hs crowdsec-bouncer`  (adds the CrowdSec
   repo, installs `crowdsec-firewall-bouncer-iptables`, points it at the engine,
   blocks in INPUT + DOCKER-USER).

## Verify

```bash
docker exec crowdsec cscli metrics          # acquisition: is it reading the logs?
docker exec crowdsec cscli bouncers list     # the 'firewall' bouncer should be present + validated
docker exec crowdsec cscli decisions list    # current bans (yours + community)
docker exec crowdsec cscli alerts list       # what it has detected
```

## Notes & gotchas

- **journald-only hosts:** if `/var/log/auth.log` doesn't exist (some minimal
  Ubuntu/Debian), SSH detection won't read it. Either enable rsyslog, or switch
  the SSH source in `infrastructure/crowdsec/acquis.yaml` to a journald source:
  ```yaml
  source: journalctl
  journalctl_filter: ["_SYSTEMD_UNIT=ssh.service"]
  labels: { type: syslog }
  ```
- **Test before you rely on it.** Because the bouncer edits the host firewall,
  enable it and confirm legit traffic still flows (and that a test ban actually
  blocks) before counting it as protection. It's off by default for this reason.
- **Don't lock yourself out:** your LAN/Tailscale admin paths shouldn't trip the
  SSH scenarios under normal use, but if you fat-finger SSH a lot, whitelist your
  admin IPs: `docker exec crowdsec cscli decisions add --ip <your-ip> ...` is the
  manual unban; add a parser whitelist for a permanent allow (see CrowdSec docs).

## Alternative enforcer — the Cloudflare bouncer

If your public exposure is **only** through the Cloudflare tunnel, you can skip
the host firewall bouncer and use CrowdSec's **Cloudflare bouncer** instead
(`crowdsecurity/cloudflare-bouncer`) — it pushes bans to Cloudflare's edge (a
clean container, no host iptables). It only protects Cloudflare-fronted traffic,
though — not the direct Jellyfin port or the LAN. The firewall bouncer covers
everything, which is why it's the default recommendation here.
