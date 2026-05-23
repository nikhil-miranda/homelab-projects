# Kingston SSD Setup

Run on the Proxmox host (aegis). Covers identifying the drive, formatting, mounting, migrating data from the NVMe, and rebinding LXC 100 mount points.

## 1. Identify the SSD

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINT
```

Look for the Kingston drive — it will appear as an unmounted device (likely `/dev/sda` or `/dev/sdb`). Note the device path; all steps below use `/dev/sdX` as a placeholder.

For more detail:

```bash
fdisk -l /dev/sdX
```

## 2. Partition and format

Create a single GPT partition spanning the full disk:

```bash
parted /dev/sdX --script mklabel gpt mkpart primary ext4 0% 100%
```

Format as ext4 with a label:

```bash
mkfs.ext4 -L kingston /dev/sdX1
```

## 3. Mount and add to fstab

Create the mount point:

```bash
mkdir -p /mnt/kingston
```

Get the partition UUID:

```bash
blkid /dev/sdX1
```

Add to `/etc/fstab` (use the UUID from the command above):

```
UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  /mnt/kingston  ext4  defaults,noatime  0  2
```

Mount and verify:

```bash
mount /mnt/kingston
df -h /mnt/kingston
```

## 4. Create directory structure

```bash
mkdir -p /mnt/kingston/media/{tv,movies}
mkdir -p /mnt/kingston/downloads/{incomplete,complete}
```

## 5. Migrate data from NVMe

Stop LXC 100 to prevent writes during migration:

```bash
pct stop 100
```

Copy data preserving permissions and ownership:

```bash
rsync -avP /srv/media/ /mnt/kingston/media/
rsync -avP /srv/downloads/ /mnt/kingston/downloads/
```

Verify sizes match:

```bash
du -sh /srv/media /mnt/kingston/media
du -sh /srv/downloads /mnt/kingston/downloads
```

## 6. Update LXC 100 bind mounts

Edit `/etc/pve/lxc/100.conf` — change the mp0 and mp1 source paths. mp2 (config) stays on NVMe:

Before:

```
mp0: /srv/media,mp=/mnt/media
mp1: /srv/downloads,mp=/mnt/downloads
mp2: /srv/config,mp=/mnt/config
```

After:

```
mp0: /mnt/kingston/media,mp=/mnt/media
mp1: /mnt/kingston/downloads,mp=/mnt/downloads
mp2: /srv/config,mp=/mnt/config
```

Start LXC 100:

```bash
pct start 100
```

## 7. Verify

```bash
pct enter 100

mount | grep mnt
# /mnt/kingston/media on /mnt/media type none (rw,bind)
# /mnt/kingston/downloads on /mnt/downloads type none (rw,bind)
# /srv/config on /mnt/config type none (rw,bind)

cd /root/mediastack
docker compose up -d
docker compose ps
# All services should show "Up" or "healthy"

ls /mnt/media/tv /mnt/media/movies
ls /mnt/downloads/incomplete /mnt/downloads/complete
ls /mnt/config/
```

Open Jellyfin at http://192.168.0.50:8096 and confirm libraries still show content.

## 8. Clean up old data on NVMe

Only after verifying everything works:

```bash
# Run on aegis host, not inside LXC
rm -rf /srv/media /srv/downloads
```

`/srv/config` stays on NVMe.

## 9. Reboot test

```bash
reboot
# After reboot:
mount | grep kingston
pct list            # LXC 100 should be running (onboot=1)
pct enter 100
docker compose ps   # all services healthy
```
