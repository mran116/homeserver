# Caddy reverse proxy — routes that generate themselves

An **opt-in** alternative to Nginx Proxy Manager that does what you actually want:
**config-as-code, automatic HTTPS, and routes that generate themselves** from
container labels. No GUI, no per-cert clicking, no manual proxy hosts.

`COMPOSE_PROFILES=caddy` turns it on. **Caddy and NPM both bind :80/:443 — run
only one** (see the cutover below).

## How it works

`caddy-docker-proxy` watches Docker and turns **labels** on each service into
Caddy config. Add two labels → a route + a valid HTTPS cert appear automatically:

```yaml
  sonarr:
    # ...existing service...
    labels:
      caddy: sonarr.${DOMAIN}
      caddy.reverse_proxy: "{{upstreams 8989}}"
```

That's the whole per-service cost. `{{upstreams 8989}}` means "proxy to this
container on port 8989." New service later? Add the two labels, push — it's
routed and HTTPS'd. The config lives in the compose file, so it's in git
(GitOps-friendly) and travels with the service.

## Automatic HTTPS (internal + external, one wildcard cert)

Caddy issues **one wildcard cert `*.${DOMAIN}`** via Cloudflare **DNS-01**, so it
needs no inbound ports for issuance and covers **every** name — LAN and public —
with browser-trusted certs that **auto-renew**. The global config is set once via
labels on the `caddy` service itself (`caddy.email`, `caddy.acme_dns`).

Requirements (all already vars you have):
- `DOMAIN` — your domain
- `CLOUDFLARE_DNS_API_TOKEN` — scoped token (Zone → DNS → Edit)
- `ACME_EMAIL` — for Let's Encrypt expiry notices

For **internal** names, point AdGuard's DNS rewrites (`*.${DOMAIN}` → server IP)
at the box, and the same wildcard cert serves them over HTTPS.

## Turn it on / cut over from NPM

1. Set `DOMAIN`, `CLOUDFLARE_DNS_API_TOKEN`, `ACME_EMAIL` in `.env`.
2. Add `caddy` to `COMPOSE_PROFILES`.
3. **Stop NPM first** (they clash on :80/:443):
   `docker stop nginx-proxy-manager`
4. `hs up infrastructure` — Caddy builds (first time) and starts.
5. Add the two `caddy:` labels to each service you want proxied, redeploy that
   stack. Routes + certs appear as you go.

Happy with NPM? Don't enable the profile — nothing changes.

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
