# Mediastack — Introduction

A self-hosted media pipeline running as Docker Compose inside a single Proxmox LXC (LXC 100, `mediastack`, 192.168.0.50). All traffic exits through a WireGuard VPN with a kill-switch before any torrent client can reach the internet.

## Services

| Service | Port | Role |
|---|---|---|
| **Gluetun** | — | WireGuard VPN gateway + kill-switch. All download traffic is routed through it. |
| **qBittorrent** | 8080 | Torrent client. Sits behind Gluetun — cannot reach the internet if VPN drops. |
| **Prowlarr** | 9696 | Indexer aggregator. Searches torrent trackers on behalf of Sonarr/Radarr. |
| **Sonarr** | 8989 | TV show manager. Monitors RSS, sends grab requests to Prowlarr, pushes to qBittorrent. |
| **Radarr** | 7878 | Movie manager. Same as Sonarr but for films. |
| **Bazarr** | 6767 | Subtitle manager. Auto-downloads subtitles for anything Sonarr/Radarr imports. |
| **Jellyfin** | 8096 | Media server. Streams your library to any device with Intel QSV hardware transcode. |
| **FlareSolverr** | 8191 | Cloudflare bypass proxy. Used by Prowlarr for protected indexers. |

## How It All Fits Together

```
You (Radarr/Sonarr UI)
        │
        ▼
    Prowlarr  ──────────────────────► Torrent indexers
        │                               (via FlareSolverr if Cloudflare-protected)
        ▼
   qBittorrent  ◄── Gluetun (WireGuard VPN)
        │
        ▼
  /mnt/downloads/complete
        │
        ▼ (Radarr/Sonarr import)
  /mnt/media/{movies,tv}
        │
        ▼
    Jellyfin  ──► Your TV / phone / browser
```

## Hardware

| Item | Value |
|---|---|
| Host | aegis — Intel i5-11500, 32 GB RAM, Proxmox VE (Debian 13) |
| iGPU | Intel UHD 750 — used by Jellyfin for hardware transcode (QSV) |
| Storage | `/mnt/kingston` (128 GB SATA SSD) for media & downloads; `/srv/config` (NVMe) for service config |
| LXC 100 | `mediastack`, IP 192.168.0.50, privileged, 8 cores, 8 GB RAM |

## Quick Access

| Service | URL |
|---|---|
| Jellyfin | http://192.168.0.50:8096 |
| Radarr | http://192.168.0.50:7878 |
| Sonarr | http://192.168.0.50:8989 |
| qBittorrent | http://192.168.0.50:8080 |
| Prowlarr | http://192.168.0.50:9696 |
| Bazarr | http://192.168.0.50:6767 |

## Setup Order

1. [kingston-ssd-setup.md](kingston-ssd-setup.md) — storage prerequisite (run once on aegis)
2. [lxc-setup.md](lxc-setup.md) — create and configure LXC 100 on aegis
3. [mediastack-setup.md](mediastack-setup.md) — deploy the Docker Compose stack inside LXC 100
4. [how-to-use.md](how-to-use.md) — find and watch your first movie
