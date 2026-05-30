# Caddy reverse proxy — routes that generate themselves

The reverse proxy for the whole stack: **config-as-code, automatic HTTPS, and
routes that generate themselves** from container labels. No GUI, no per-cert
clicking, no manual proxy hosts.

`COMPOSE_PROFILES=caddy` (or `hs enable caddy`) turns it on. Caddy binds host
:80/:443 to serve HTTP/HTTPS.

## How it works

`caddy-docker-proxy` watches Docker and turns **labels** on each service into
Caddy config. Every service joins **one shared `*.${DOMAIN}` site** via a host
matcher, so a **single wildcard cert** covers them all. Add the four labels →
a route appears under the wildcard:

```yaml
  sonarr:
    # ...existing service...
    labels:
      caddy: "*.${DOMAIN}"
      caddy.@sonarr: "host sonarr.${DOMAIN}"
      caddy.handle: "@sonarr"
      caddy.handle.reverse_proxy: "{{upstreams 8989}}"
```

`caddy: "*.${DOMAIN}"` puts the service in the shared wildcard site; the
`@sonarr` matcher routes `sonarr.${DOMAIN}` to it; `{{upstreams 8989}}` means
"proxy to this container on port 8989." New service later? Copy the four labels,
swap the name + port, push — it's routed under the same wildcard cert. The config
lives in the compose file, so it's in git (GitOps-friendly).

## Automatic HTTPS (internal + external, one wildcard cert)

Caddy obtains **one wildcard cert `*.${DOMAIN}`** via the Cloudflare **DNS-01**
challenge, so issuance needs **no inbound ports** and works even for
**internal-only** names that aren't reachable from the internet. One cert covers
every service, so individual service names never appear in public Certificate
Transparency logs. It **auto-renews** and persists in the `caddy/data` volume.
The global config is set once via labels on the `caddy` service itself
(`caddy.email`, `caddy.acme_dns`).

Requirements (all already vars you have):
- `DOMAIN` — your domain
- `CLOUDFLARE_DNS_API_TOKEN` — scoped token (Zone → DNS → Edit + Zone → Read)
- `ACME_EMAIL` — for Let's Encrypt expiry notices

For **internal** names, add a single wildcard **DNS rewrite** in AdGuard
(`*.${DOMAIN}` → server LAN IP) pointing at the box; Caddy then serves every
current and future route over HTTPS with no further DNS changes.

## Turn it on

1. Set `DOMAIN`, `CLOUDFLARE_DNS_API_TOKEN`, `ACME_EMAIL` in `.env`.
2. Add `caddy` to `COMPOSE_PROFILES` (or `hs enable caddy`).
3. `hs up infrastructure` — Caddy builds (first time) and starts.
4. Add the four `caddy:` labels (wildcard-site + host matcher) to each service
   you want proxied, redeploy that stack. Routes appear under the one wildcard
   cert as you go.

## Security note

Caddy reads the Docker socket (read-only) to discover labels. To avoid giving it
socket access directly, point it at the **docker-socket-proxy** already in the
dashboard stack (set `DOCKER_HOST` / the proxy endpoint) — a hardening follow-up.

## Will this survive a move to Swarm or Kubernetes?

- **Docker Swarm: yes, unchanged.** `caddy-docker-proxy` natively supports Swarm
  — it reads **service** labels the same way. Your labels carry over as-is. Swarm
  is the natural "scale to a few nodes" step and Caddy fits it directly.
- **K3s / Kubernetes: the ingress layer changes (for any proxy, not just Caddy).**
  `caddy-docker-proxy` is Docker-socket based, so it doesn't run on K8s. There you
  use a Kubernetes **ingress controller** — note **K3s ships with Traefik as its
  default ingress**, so you'd likely just use that, or swap in the **Caddy ingress
  controller**. Either way you re-express routes as `Ingress` resources instead of
  Docker labels, and certs move to **cert-manager** (same Cloudflare DNS-01
  wildcard approach). The *concepts* transfer; the syntax changes.

**Bottom line:** Caddy-docker-proxy is the right low-hassle choice for Docker and
Swarm now. A K3s move would mean redoing the ingress layer regardless of which
proxy you pick today — so it's not a reason to choose differently now.
