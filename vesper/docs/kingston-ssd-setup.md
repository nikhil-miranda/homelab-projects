# Kingston SSD Setup & NVMe Cleanup

One-time guide. Run on the Proxmox host (aegis). Wipes all existing CTs/VMs, reclaims the NVMe thin pool, and sets up the Kingston SSD at `/mnt/kingston`. After this, follow `lxc-setup-ui.md` → `mediastack-setup.md`.

## Before cleanup

```
NVMe (nvme0n1, 119.2G)
├── pve-root   53.5G   /           ← OS + Proxmox
├── pve-swap    8.0G   [SWAP]
├── pve-data   53.9G   thin pool   ← wasted space
└── pve-srv     0.6G   /srv        ← config (too small)

Kingston SSD (sda, 111.8G)
└── sda1       111.8G  /mnt/media  ← wrong mount point
```

## After cleanup

```
NVMe (nvme0n1, 119.2G)
├── pve-root   ~103G   /           ← expanded
├── pve-swap     8.0G  [SWAP]
└── pve-srv      4.0G  /srv        ← config, expanded

Kingston SSD (sda, 111.8G)
└── sda1       111.8G  /mnt/kingston
    ├── media/{tv,movies}
    └── downloads/{incomplete,complete}
```

---

## Phase 1: Destroy all CTs and VMs

List everything:

```bash
pct list
qm list
```

Stop and destroy each one:

```bash
# For each CT (e.g. 100, 101):
pct stop <id>
pct destroy <id>

# For each VM (if any):
qm stop <id>
qm destroy <id>
```

Confirm nothing remains:

```bash
pct list
qm list
# Both should be empty
```

## Phase 2: Remove thin pool and reclaim space

Verify the thin pool is empty:

```bash
lvs -o lv_name,vg_name,lv_size,pool_lv pve
# Only pve-root, pve-swap, pve-srv should remain (no thin volumes)
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

Expand `/srv` (config) and give pve-root the rest:

```bash
lvextend -L 4G /dev/pve/srv
resize2fs /dev/pve/srv

lvextend -l +100%FREE /dev/pve/root
resize2fs /dev/pve/root
```

Verify:

```bash
df -h / /srv
# pve-root ~103G, pve-srv ~4G
```

## Phase 3: Kingston SSD

The Kingston is already formatted (ext4, sda1). Remount it at the correct path.

Unmount and rename:

```bash
umount /mnt/media
mkdir -p /mnt/kingston
rmdir /mnt/media
```

Edit `/etc/fstab` — change the Kingston mount point:

Before:

```
UUID=<kingston-uuid>  /mnt/media     ext4  defaults,noatime  0  2
```

After:

```
UUID=<kingston-uuid>  /mnt/kingston  ext4  defaults,noatime  0  2
```

Mount and verify:

```bash
mount /mnt/kingston
df -h /mnt/kingston
```

Create directory structure (remove any old data first if starting fresh):

```bash
rm -rf /mnt/kingston/*
mkdir -p /mnt/kingston/media/{tv,movies}
mkdir -p /mnt/kingston/downloads/{incomplete,complete}
```

## Phase 4: Clean up NVMe data directories

```bash
rm -rf /srv/media /srv/downloads
mkdir -p /srv/config
ls /srv/
# Expected: config
```

## Phase 5: Verify and reboot

```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
df -h / /srv /mnt/kingston
# All three should show correct sizes and mount points
```

Reboot to confirm fstab entries survive:

```bash
reboot
# After reboot:
df -h / /srv /mnt/kingston
```

---

## Next steps

1. Follow `lxc-setup-ui.md` — creates CT 100 with Kingston bind mounts + iGPU passthrough
2. Follow `mediastack-setup.md` — Docker install, repo clone, stack deploy
