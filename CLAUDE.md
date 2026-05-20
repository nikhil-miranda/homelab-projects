# homelab-projects

Personal homelab automation, configs, and runbooks managed with Claude Code.

## Repo Layout

```
homelab-projects/
├── .env                         # gitignored, all secrets (create locally)
├── .env.example                 # committed template, sectioned by project
├── CLAUDE.md
├── README.md
└── proxmox-mediastack/
    ├── docker-compose.yml
    └── docs/
        ├── lxc-setup.md         # steps 1-4 reference (done)
        └── mediastack-setup.md  # steps 5-10 deployment runbook
```

## Hardware Reference

| Item | Value |
|---|---|
| Host | aegis — Intel i5-11500, 32 GB RAM, Debian 13 / Proxmox VE |
| iGPU | Intel UHD 750 (`/dev/dri/renderD128`) |
| ZFS pool | `tank` → datasets `tank/media`, `tank/downloads`, `tank/config` |
| LXC 100 | `mediastack`, IP 192.168.0.50, privileged, 8 cores, 8 GB RAM |
| Render GID | 993 (matched between host and LXC) |

## Running the Mediastack (on LXC 100)

SSH or `pct enter 100` from aegis, then:

```bash
cd /root/mediastack   # symlink → /root/homelab-projects/proxmox-mediastack
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
- ZFS bind mounts at `/mnt/` inside LXCs. Config persisted on ZFS, not in containers.
