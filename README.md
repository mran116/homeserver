# Homeserver Docker Stack

Private repository for all Docker Compose stacks.
No secrets committed — all sensitive values stored in Vaultwarden.

## Stack Structure

```
/opt/docker/
├── portainer/       ← Deploy FIRST via SSH — manages everything else
├── vaultwarden/     ← Deploy SECOND — stores all secrets
├── infrastructure/  ← NPM active, Tailscale/Cloudflare/Borgmatic commented
├── monitoring/      ← Uptime Kuma, Dozzle, Watchtower, Notifiarr
├── management/      ← Homepage dashboard
├── mediastack/      ← Jellyfin, Sonarr, Radarr, and all media apps
├── household/       ← Mealie, KitchenOwl, Donetick, Actual Budget
├── records/         ← Paperless, Stirling PDF, DocuSeal (commented)
├── cloud/           ← Immich, Matrix (commented)
└── automation/      ← n8n (commented)

/opt/docker/homepage/ ← Homepage config files (copy before deploying management)
/opt/docker/borgmatic/ ← Borgmatic config (copy before enabling borgmatic)
```

## Storage Paths

```
/mnt/disk1/photos      ← Immich photo/video library (temporary until Synology)
/mnt/disk1/documents   ← Paperless document storage (temporary until Synology)
/mnt/media             ← Movies, TV, music, anime, books

When Synology arrives update .env:
  PHOTOS_PATH=/mnt/photos    (NFS mount)
  DOCS_PATH=/mnt/documents   (NFS mount)
```

## Deployment Order

### Step 1 — SSH into server (one time only)

```bash
# Create shared Docker network
docker network create home

# Create required directories
sudo mkdir -p /opt/docker/portainer
sudo mkdir -p /opt/docker/homepage
sudo mkdir -p /mnt/disk1/photos
sudo mkdir -p /mnt/disk1/documents

# Clone this repo
git clone https://github.com/yourusername/homeserver.git /opt/docker/repo

# Create .env from template and fill in secrets from Vaultwarden
cp /opt/docker/repo/.env.template /opt/docker/.env
nano /opt/docker/.env

# Symlink .env to all stack folders
for dir in portainer vaultwarden infrastructure monitoring management mediastack household records cloud automation; do
  ln -sf /opt/docker/.env /opt/docker/$dir/.env
done

# Copy homepage config files
cp -r /opt/docker/repo/homepage/* /opt/docker/homepage/

# Copy borgmatic config (for when you enable it later)
mkdir -p /opt/docker/borgmatic/config
cp /opt/docker/repo/borgmatic-config/config.yaml /opt/docker/borgmatic/config/

# Start Portainer
cd /opt/docker/portainer
docker compose up -d
```

### Step 2 — Deploy via Portainer UI (http://SERVER_IP:9000)

Deploy in this order — each stack depends on the network being up:

1. **vaultwarden** — set up immediately, store all secrets here
2. **infrastructure** — NPM for SSL and local URLs
3. **monitoring** — Uptime Kuma, Dozzle, Watchtower, Notifiarr
4. **management** — Homepage dashboard
5. **mediastack** — all media apps
6. **household** — family apps
7. **records** — Paperless, Stirling PDF
8. **cloud** — Immich photo backup

### Step 3 — After each stack deploys

**Vaultwarden:**
- Create your account
- Set VAULTWARDEN_SIGNUPS_ALLOWED=false in .env
- Enable 2FA immediately
- Install Bitwarden app on all devices
- Point server URL to http://SERVER_IP:9930
- Store all secrets here

**NPM (Nginx Proxy Manager):**
- Default login: admin@example.com / changeme
- Change immediately
- Set up proxy hosts for local URLs

**Immich:**
- Create admin account
- Create accounts for each family member
- Install Immich app on all phones
- Create shared family album
- Create private shared album (you and wife only)

**Actual Budget:**
- Connect SimpleFIN at beta-bridge.simplefin.org ($15/yr)
- Add Regions Bank and Citibank

**Vaultwarden:**
- Set SIGNUPS_ALLOWED=false after setup

## Enabling Commented Services

### Tailscale (when ready):
1. Get auth key at login.tailscale.com/admin/settings/keys
2. Add TS_AUTHKEY to .env
3. Uncomment tailscale in infrastructure/docker-compose.yml
4. Redeploy infrastructure stack
5. Approve subnet route in Tailscale admin panel

### Cloudflare Tunnel (when domain purchased):
1. Buy domain at cloudflare.com (~$10/year)
2. Zero Trust → Networks → Tunnels → Create tunnel
3. Add CLOUDFLARE_TUNNEL_TOKEN to .env
4. Uncomment cloudflared in infrastructure/docker-compose.yml
5. Add routes: jellyfin/vaultwarden/navidrome.yourdomain.com
6. Redeploy infrastructure stack

### Matrix (when domain and Cloudflare ready):
1. Set MATRIX_SERVER_NAME=yourdomain.com in .env
2. Uncomment synapse in cloud/docker-compose.yml
3. Redeploy cloud stack
4. Add matrix.yourdomain.com to Cloudflare routes

### DocuSeal (when domain and SMTP ready):
1. Set up Cloudflare Email Routing for your domain
2. Configure Gmail SMTP credentials in .env
3. Uncomment docuseal in records/docker-compose.yml
4. Redeploy records stack

### Borgmatic (when Backblaze B2 ready):
1. Create Backblaze B2 account at backblaze.com
2. Update borgmatic-config/config.yaml with B2 credentials
3. Add BORG_PASSPHRASE to .env
4. Uncomment borgmatic in infrastructure/docker-compose.yml
5. Redeploy infrastructure stack

### n8n (when all other stacks are running):
1. Set N8N_USER and N8N_PASSWORD in .env
2. Uncomment n8n in automation/docker-compose.yml
3. Redeploy automation stack
4. Connect services via n8n UI

## Moving to a New Server

```bash
# On new server
curl -fsSL https://get.docker.com | bash
sudo systemctl enable docker
sudo usermod -aG docker $USER

# Create folders
sudo mkdir -p /opt/docker
sudo chown $USER:$USER /opt/docker

# Clone repo
git clone https://github.com/yourusername/homeserver.git /opt/docker/repo

# Get .env from Vaultwarden and fill in
cp /opt/docker/repo/.env.template /opt/docker/.env
nano /opt/docker/.env

# Create network and symlinks
docker network create home
for dir in portainer vaultwarden infrastructure monitoring management mediastack household records cloud automation; do
  ln -sf /opt/docker/.env /opt/docker/$dir/.env
done

# Start Portainer and deploy everything else via UI
cd /opt/docker/portainer && docker compose up -d
```

## When Synology Arrives

```bash
# Mount Synology shares
sudo apt install nfs-common
echo "SYNOLOGY_IP:/volume1/photos    /mnt/photos    nfs    defaults    0    0" | sudo tee -a /etc/fstab
echo "SYNOLOGY_IP:/volume1/documents /mnt/documents nfs    defaults    0    0" | sudo tee -a /etc/fstab
sudo mount -a

# Migrate data
sudo rsync -av /mnt/disk1/photos/ /mnt/photos/
sudo rsync -av /mnt/disk1/documents/ /mnt/documents/

# Update .env
nano /opt/docker/.env
# Change:
#   PHOTOS_PATH=/mnt/photos
#   DOCS_PATH=/mnt/documents

# Redeploy cloud and records stacks via Portainer
```

## Security Checklist

- [ ] Strong master password on Vaultwarden
- [ ] 2FA enabled on Vaultwarden
- [ ] 2FA enabled on Portainer
- [ ] 2FA enabled on Immich admin
- [ ] VAULTWARDEN_SIGNUPS_ALLOWED=false after setup
- [ ] Tailscale set up for remote access
- [ ] Cloudflare Tunnel for public services
- [ ] NPM SSL certificates for local services
- [ ] Watchtower keeping everything updated
- [ ] Uptime Kuma monitoring all services
