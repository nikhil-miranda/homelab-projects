# homelab-projects

Personal homelab automation, configs, and runbooks managed with Claude Code.

## Repo Layout

```
homelab-projects/
├── .env.example                 # committed template, sectioned by project
├── CLAUDE.md
├── README.md
├── scripts/                     # repo-level maintenance scripts
└── mediastack/
    ├── .env                     # gitignored, created locally from .env.example
    ├── .env.example             # committed template
    ├── docker-compose.yml
    └── docs/
        ├── lxc-setup.md         # steps 1-4 CLI reference (done)
        ├── lxc-setup-ui.md      # steps 1-4 via Proxmox web UI
        ├── mediastack-setup.md  # steps 5-11 deployment runbook
        └── kingston-ssd-setup.md # SATA SSD setup & NVMe thin pool cleanup
```

## Hardware Reference

| Item | Value |
|---|---|
| Host | aegis — Intel i5-11500, 32 GB RAM, Debian 13 / Proxmox VE |
| iGPU | Intel UHD 750 (`/dev/dri/renderD128`) |
| Storage | 128 GB NVMe (boot/OS/config) + 128 GB SATA SSD (media & downloads). pve-root (~103 G LVM, after thin pool removal) hosts `/srv/config`. SATA SSD mounted at `/mnt/kingston` (ext4). |
| Host paths | `/mnt/kingston/media`, `/mnt/kingston/downloads` (SATA SSD) and `/srv/config` (NVMe) — bind-mounted into LXC 100 at `/mnt/media`, `/mnt/downloads`, `/mnt/config`, and `/mnt/kingston` (mp3, parent mount required for Docker hardlinks) |
| LXC 100 | `mediastack`, IP 192.168.0.50, privileged, 8 cores, 8 GB RAM |
| Render GID | 993 (matched between host and LXC) |

## Running the Mediastack (on LXC 100)

SSH or `pct enter 100` from aegis, then:

```bash
cd /root/homelab-projects/mediastack
docker compose up -d
docker compose ps
docker compose logs -f <service>
```

`.env` lives directly in `/root/homelab-projects/mediastack/` (gitignored, not committed).

Update the stack:

```bash
git pull && docker compose pull && docker compose up -d
```

## Conventions

- Secrets live in each project's own `.env` (gitignored), co-located with `docker-compose.yml`.
- `.env.example` lives alongside `docker-compose.yml` in each project directory — copy it to `.env` and fill in real values.
- New projects get a top-level folder + `docs/` with a setup runbook.
- Bind mounts: `/mnt/kingston/{media,downloads}` (SATA SSD) and `/srv/config` (NVMe) on aegis → `/mnt/{media,downloads,config,kingston}` in LXC 100. Config persisted on host, not in containers.
- `DATA_PATH=/mnt/kingston` in `.env` — Radarr and Sonarr mount this as `/data` so both `/data/media` and `/data/downloads` share one filesystem mount, enabling hardlinks on import.
