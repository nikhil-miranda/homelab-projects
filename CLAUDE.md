# homelab-projects

Personal homelab automation, configs, and runbooks managed with Claude Code.

## Repo Layout

```
homelab-projects/
├── .env                         # gitignored, all secrets (create locally)
├── .env.example                 # committed template, sectioned by project
├── CLAUDE.md
├── README.md
├── scripts/                     # repo-level maintenance scripts
└── vesper/
    ├── docker-compose.yml
    └── docs/
        ├── lxc-setup.md         # steps 1-4 CLI reference (done)
        ├── lxc-setup-ui.md      # steps 1-4 via Proxmox web UI
        └── mediastack-setup.md  # steps 5-11 deployment runbook
```

## Hardware Reference

| Item | Value |
|---|---|
| Host | aegis — Intel i5-11500, 32 GB RAM, Debian 13 / Proxmox VE |
| iGPU | Intel UHD 750 (`/dev/dri/renderD128`) |
| Storage | Single 128 GB NVMe. pve-root (39.5 G LVM) hosts `/srv/` — a plain directory, **no ZFS pool**. ~14.6 G unallocated in VG. Plan: add dedicated HDD and set up ZFS pool. |
| `/srv/` | `/srv/media`, `/srv/downloads`, `/srv/config` — bind-mounted into LXC 100 at `/mnt/media`, `/mnt/downloads`, `/mnt/config` |
| LXC 100 | `mediastack`, IP 192.168.0.50, privileged, 8 cores, 8 GB RAM |
| Render GID | 993 (matched between host and LXC) |

## Running the Mediastack (on LXC 100)

SSH or `pct enter 100` from aegis, then:

```bash
cd /root/mediastack   # symlink → /root/homelab-projects/vesper
docker compose up -d
docker compose ps
docker compose logs -f <service>
```

The `.env` is symlinked: `/root/mediastack/.env → /root/homelab-projects/.env`

Update the stack:

```bash
git pull && docker compose pull && docker compose up -d
```

## Conventions

- Secrets live in root `.env` (gitignored). Each project's vars are in a named section.
- `.env.example` is the committed template — copy it to `.env` and fill in real values.
- New projects get a top-level folder + `docs/` with a setup runbook.
- Bind mounts from `/srv/{media,downloads,config}` on aegis → `/mnt/{media,downloads,config}` in LXC 100. Config persisted on host, not in containers.
