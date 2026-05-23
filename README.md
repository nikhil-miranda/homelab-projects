# homelab-projects

Personal homelab automation, configs, and runbooks.

---

## 1. mediastack

| # | Doc | Description |
|---|-----|-------------|
| a | [introduction.md](mediastack/docs/introduction.md) | Stack overview, service map, and hardware reference |
| b | [lxc-setup.md](mediastack/docs/lxc-setup.md) | Proxmox LXC creation and iGPU passthrough (CLI) |
| c | [mediastack-setup.md](mediastack/docs/mediastack-setup.md) | Docker Compose deployment, VPN setup, and service configuration |
| d | [how-to-use.md](mediastack/docs/how-to-use.md) | Finding, downloading, and watching movies |

Additional references:

- [lxc-setup-ui.md](mediastack/docs/lxc-setup-ui.md) — LXC creation via Proxmox web UI (alternative to `b`)
- [kingston-ssd-setup.md](mediastack/docs/kingston-ssd-setup.md) — SATA SSD setup and NVMe thin pool cleanup (prerequisite)

---

<!--
## 2. <project-name>

| # | Doc | Description |
|---|-----|-------------|
| a | [introduction.md](<project>/docs/introduction.md) | ... |
| b | ... | ... |

-->

---

## Conventions

- Secrets live in each project's `.env` (gitignored), co-located with `docker-compose.yml`. Copy `.env.example` to `.env` and fill in real values.
- New projects get a top-level folder with `docs/` and at minimum an `introduction.md` and a setup runbook.
- Bind mounts: host paths → container paths documented per project in `introduction.md`.
