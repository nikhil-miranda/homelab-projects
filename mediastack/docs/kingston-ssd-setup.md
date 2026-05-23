# SATA SSD Setup & NVMe Cleanup

One-time guide. Run on the Proxmox host (aegis). Reclaims NVMe space from the default thin pool and mounts the SATA SSD at `/mnt/kingston`. After this, follow `lxc-setup.md` (CLI) or `lxc-setup-ui.md` (web UI) → `mediastack-setup.md`.

## Before

```
NVMe (nvme0n1, 119.2G)
├── pve-root   ~36G   /           ← OS + Proxmox
├── pve-swap    8.0G  [SWAP]
└── pve-data   ~73G  thin pool    ← reclaim this

SATA SSD (sda, 111.8G) — ext4, not yet mounted
```

## After

```
NVMe (nvme0n1, 119.2G)
├── pve-root   ~103G  /           ← expanded
└── pve-swap     8.0G [SWAP]

SATA SSD (sda, 111.8G)
└── sda1       111.8G  /mnt/kingston
    ├── media/{tv,movies}
    └── downloads/{incomplete,complete}
```

---

## Phase 1: Remove thin pool, expand pve-root

Verify the thin pool is empty (no CTs or VMs should exist on a clean install):

```bash
pct list
qm list
# Both should be empty
```

Remove the thin pool:

```bash
lvremove -f /dev/pve/data
```

Remove the Proxmox storage entry:

```bash
pvesm status | grep local-lvm
# If present:
pvesm remove local-lvm
```

Expand pve-root to use all freed space:

```bash
lvextend -l +100%FREE /dev/pve/root
resize2fs /dev/pve/root
```

Verify:

```bash
df -h /
# pve-root should show ~103G
```

## Phase 2: Mount SATA SSD

Find the partition name and UUID:

```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
# Look for the ext4 partition — typically sda1

blkid /dev/sda1
# /dev/sda1: UUID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" TYPE="ext4"
```

Create mount point:

```bash
mkdir -p /mnt/kingston
```

Add to `/etc/fstab` (use the UUID from blkid above):

```
UUID=<your-uuid>  /mnt/kingston  ext4  defaults,noatime  0  2
```

Mount and verify:

```bash
mount /mnt/kingston
df -h /mnt/kingston
# Should show ~111G
```

## Phase 3: Directory structure

```bash
mkdir -p /mnt/kingston/media/{tv,movies}
mkdir -p /mnt/kingston/downloads/{incomplete,complete}
ls /mnt/kingston/
# Expected: downloads  media
```

## Phase 4: Config directory on NVMe

```bash
mkdir -p /srv/config
ls /srv/
# Expected: config
```

## Verify and reboot

```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
df -h / /mnt/kingston
```

Reboot to confirm fstab survives:

```bash
reboot
# After reboot:
df -h / /mnt/kingston
```

---

## Next steps

1. Follow `lxc-setup.md` (CLI) or `lxc-setup-ui.md` (web UI) — creates CT 100 with SATA SSD bind mounts + iGPU passthrough
2. Follow `mediastack-setup.md` — Docker install, repo clone, stack deploy
