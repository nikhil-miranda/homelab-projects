#!/usr/bin/env bash
# Reset the mediastack on LXC 100 to a clean state.
# Run this inside LXC 100 (pct enter 100 or SSH to 192.168.0.50).
# Usage: reset-mediastack.sh [-y]   (-y skips all confirmation prompts)
#
# What this wipes:
#   - All running Docker containers, images, volumes, networks, build cache
#   - All service config dirs under /mnt/config
#   - The .env file (secrets)
#   - /mnt/kingston/downloads (optional — prompted separately)
#
# What this keeps:
#   - /mnt/kingston/media  (your actual library — never touched)
#   - The cloned repo at /root/homelab-projects
set -euo pipefail

AUTOYES=0
[[ "${1:-}" == "-y" ]] && AUTOYES=1

REPO_DIR=/root/homelab-projects/mediastack
CONFIG_DIR=/mnt/config
DOWNLOADS_DIR=/mnt/kingston/downloads

# ── helpers ──────────────────────────────────────────────────────────────────

hr()      { printf '%s\n' "──────────────────────────────────────────────────"; }
section() { echo; echo "▸ $*"; }

confirm() {
  local prompt="${1:-Proceed?}"
  [[ $AUTOYES -eq 1 ]] && return 0
  read -rp "  ${prompt} [y/N] " ans
  [[ "${ans,,}" == "y" ]]
}

warn() { echo "  ! $*"; }

# ── pre-flight ───────────────────────────────────────────────────────────────

hr
echo "  mediastack reset — $(date '+%Y-%m-%d %H:%M:%S')"
hr

if [[ $EUID -ne 0 ]]; then
  echo "Error: run as root (or via sudo)." >&2
  exit 1
fi

if ! command -v docker &>/dev/null; then
  echo "Error: docker not found. Is this LXC 100?" >&2
  exit 1
fi

echo
echo "This will permanently destroy:"
echo "  • All Docker containers, images, volumes, networks, and build cache"
echo "  • All service config dirs under ${CONFIG_DIR}"
echo "  • The .env file at ${REPO_DIR}/.env"
echo
warn "Your media library at /mnt/kingston/media will NOT be touched."
warn "Downloads at ${DOWNLOADS_DIR} will be prompted separately."
echo

confirm "Wipe Docker state and service configs?" || { echo "Aborted."; exit 0; }

# ── 1. bring down compose stack ──────────────────────────────────────────────

section "Stopping compose stack"
if [[ -f "${REPO_DIR}/docker-compose.yml" ]]; then
  docker compose -f "${REPO_DIR}/docker-compose.yml" down --remove-orphans --volumes 2>&1 | sed 's/^/  /' || true
else
  warn "docker-compose.yml not found at ${REPO_DIR} — skipping compose down"
fi

# ── 2. prune all Docker resources ────────────────────────────────────────────

section "Pruning all Docker resources (containers, images, volumes, networks, build cache)"
docker system prune -af --volumes 2>&1 | sed 's/^/  /'

# ── 3. wipe service config dirs ──────────────────────────────────────────────

section "Wiping service config dirs under ${CONFIG_DIR}"
SERVICE_DIRS=(gluetun qbittorrent prowlarr sonarr radarr bazarr jellyfin flaresolverr tailscale-jellyfin)
for svc in "${SERVICE_DIRS[@]}"; do
  target="${CONFIG_DIR}/${svc}"
  if [[ -d "$target" ]]; then
    rm -rf "$target"
    echo "  removed: ${target}"
  fi
done
# Recreate empty dirs so bind mounts work on next compose up
mkdir -p "${CONFIG_DIR}"/{gluetun,qbittorrent,prowlarr,sonarr,radarr,bazarr,jellyfin,flaresolverr,tailscale-jellyfin}
echo "  recreated empty dirs"

# ── 4. remove .env ───────────────────────────────────────────────────────────

section "Removing .env (secrets)"
if [[ -f "${REPO_DIR}/.env" ]]; then
  rm "${REPO_DIR}/.env"
  echo "  removed: ${REPO_DIR}/.env"
else
  echo "  not found, skipping"
fi

# ── 5. optionally wipe downloads ─────────────────────────────────────────────

section "Downloads directory: ${DOWNLOADS_DIR}"
if [[ -d "$DOWNLOADS_DIR" ]]; then
  DL_SIZE=$(du -sh "$DOWNLOADS_DIR" 2>/dev/null | cut -f1)
  echo "  current size: ${DL_SIZE}"
  if confirm "Wipe all downloads (incomplete + complete)?"; then
    rm -rf "${DOWNLOADS_DIR:?}"/{incomplete,complete}
    mkdir -p "${DOWNLOADS_DIR}"/{incomplete,complete}
    echo "  wiped and recreated"
  else
    echo "  skipped — downloads left intact"
  fi
else
  echo "  not found, skipping"
fi

# ── done ─────────────────────────────────────────────────────────────────────

echo
hr
echo "  Reset complete. LXC is back to a clean state."
echo
echo "  Next steps:"
echo "    cd ${REPO_DIR}"
echo "    git pull"
echo "    cp .env.example .env && chmod 600 .env && nano .env"
echo "    docker compose pull && docker compose up -d"
echo
echo "  See mediastack/docs/mediastack-setup.md for the full setup walkthrough."
hr
