# homelab-projects

Personal homelab automation, configs, and runbooks.

## Projects

| Name | Description | Status |
|---|---|---|
| `proxmox-mediastack` | Single-LXC Docker Compose media stack on Proxmox: gluetun + qBittorrent + Prowlarr + Sonarr + Radarr + Bazarr + Jellyfin with Intel iGPU transcode | Deploying |

## Conventions

- Secrets live in `.env` (gitignored). See `.env.example` for the template.
- Bind mounts from `/tank/{media,downloads,config}` on pve-root into `/mnt/` inside LXCs.
- Service config persisted on `/tank/config` on the host, not inside containers.

## Layout

```
homelab-projects/
├── .env                    # gitignored, all secrets
├── .env.example            # committed template, sectioned by project
├── .gitignore
├── CLAUDE.md
├── README.md
└── proxmox-mediastack/
    ├── docker-compose.yml
    └── docs/
        ├── lxc-setup.md
        └── mediastack-setup.md
```
