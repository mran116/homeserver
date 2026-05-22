#!/usr/bin/env bash
# =============================================================================
# setup-fresh.sh — one-shot setup for a BRAND-NEW Debian/Ubuntu machine.
#
# For friends / fresh boxes that don't have Docker yet. It installs the
# prerequisites the main bootstrap assumes, then hands off to ./bootstrap.sh
# (which does .env, secrets, dirs, the docker network, symlinks, and starts
# Arcane). Re-runnable.
#
#   git clone https://github.com/mran116/homeserver.git
#   cd homeserver
#   ./scripts/setup-fresh.sh
#
# What it does NOT do (you handle these):
#   - mounting your media/data disks (the script uses whatever paths you pick;
#     if your media lives on another disk/NAS, mount it first)
#   - deploying the app stacks or filling secrets — do that from Arcane after,
#     then run ./scripts/harvest-keys.sh
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

command -v apt-get >/dev/null || die "This script is for Debian/Ubuntu (apt). On other distros, install Docker + git manually, then run ./bootstrap.sh."

# ---- 1. base packages -------------------------------------------------------
if ! command -v curl >/dev/null || ! command -v git >/dev/null; then
  say "Installing base packages (curl, git, ca-certificates)"
  sudo apt-get update -y
  sudo apt-get install -y curl git ca-certificates
fi

# ---- 2. Docker engine + compose plugin --------------------------------------
if ! command -v docker >/dev/null; then
  say "Installing Docker (official convenience script)"
  curl -fsSL https://get.docker.com | sudo sh
  sudo systemctl enable --now docker
else
  say "Docker already installed: $(docker --version)"
fi

if ! docker compose version >/dev/null 2>&1; then
  die "Docker is installed but the compose plugin is missing. Install 'docker-compose-plugin' and re-run."
fi

# ---- 3. docker group for this user ------------------------------------------
if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
  say "Adding $USER to the 'docker' group"
  sudo usermod -aG docker "$USER"
fi

# ---- 4. make sure we can actually talk to docker ----------------------------
if ! docker info >/dev/null 2>&1; then
  echo
  warn "Docker is installed, but your shell isn't in the 'docker' group yet."
  warn "Log out and back in (or run:  newgrp docker ), then re-run this script:"
  warn "    ./scripts/setup-fresh.sh"
  exit 0
fi

# ---- 5. hand off to the main bootstrap --------------------------------------
say "Prerequisites ready — running ./bootstrap.sh"
echo
exec ./bootstrap.sh
