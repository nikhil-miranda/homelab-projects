# homelab-projects

Personal homelab automation, configs, and runbooks.

## Projects

| Name | Description | Status |
|---|---|---|
| `mediastack` | Single-LXC Docker Compose media stack on Proxmox: gluetun + qBittorrent + Prowlarr + Sonarr + Radarr + Bazarr + Jellyfin with Intel iGPU transcode | Deploying |

## Conventions

- Secrets live in each project's own `.env` (gitignored), co-located with `docker-compose.yml`. Copy `.env.example` (same directory) to `.env` and fill in real values.
- Bind mounts: `/mnt/kingston/{media,downloads}` (Kingston SSD) and `/srv/config` (NVMe) on aegis → `/mnt/{media,downloads,config}` inside LXC 100.
- Service config persisted on `/srv/config` on the host, not inside containers.

## Layout

```
homelab-projects/
├── .env                    # gitignored, all secrets
├── .gitignore
├── CLAUDE.md
├── README.md
├── scripts/                # repo-level maintenance scripts
└── mediastack/
    ├── .env.example            # committed template
    ├── docker-compose.yml
    └── docs/
        ├── lxc-setup.md
        ├── lxc-setup-ui.md
        ├── mediastack-setup.md
        └── kingston-ssd-setup.md
```
