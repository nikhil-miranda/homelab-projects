# homelab-projects

Personal homelab automation, configs, and runbooks.

## Projects

| Name | Description | Status |
|---|---|---|
| `vesper` | Single-LXC Docker Compose media stack on Proxmox: gluetun + qBittorrent + Prowlarr + Sonarr + Radarr + Bazarr + Jellyfin with Intel iGPU transcode | Deploying |

## Conventions

- Secrets live in `.env` (gitignored). See `.env.example` for the template.
- Bind mounts: `/mnt/kingston/{media,downloads}` (Kingston SSD) and `/srv/config` (NVMe) on aegis → `/mnt/{media,downloads,config}` inside LXC 100.
- Service config persisted on `/srv/config` on the host, not inside containers.

## Layout

```
homelab-projects/
├── .env                    # gitignored, all secrets
├── .env.example            # committed template, sectioned by project
├── .gitignore
├── CLAUDE.md
├── README.md
├── scripts/                # repo-level maintenance scripts
└── vesper/
    ├── docker-compose.yml
    └── docs/
        ├── lxc-setup.md
        ├── lxc-setup-ui.md
        └── mediastack-setup.md
```
