# LXC Setup (Steps 1–4)

Run on the Proxmox host (aegis). Covers host prep, LXC creation, iGPU passthrough, and inside-LXC baseline. Follow `mediastack-setup.md` after this.

**Prerequisite:** Complete `kingston-ssd-setup.md` first (thin pool removal, SATA SSD mount, directory creation) so `/mnt/kingston` is ready before creating the LXC.

## Before you start

If you are recreating an existing LXC, destroy it first:

```bash
pct stop 100
pct destroy 100
```

Verify the bind-mount source directories on the host survived (they live outside the LXC):

```bash
ls /srv/config         # config stays on NVMe (pve-root)
ls /mnt/kingston/      # media and downloads on Kingston SSD
# Expected: media  downloads
```

If missing, recreate before proceeding:

```bash
mkdir -p /srv/config
mkdir -p /mnt/kingston/media/{tv,movies}
mkdir -p /mnt/kingston/downloads/{incomplete,complete}
```

Check which Debian 13 template is available locally (the exact filename changes with point releases):

```bash
pveam list local | grep debian-13
```

If no result, fetch the latest:

```bash
pveam update
pveam download local $(pveam available --section system | awk '/debian-13/{print $2; exit}')
```

Use the filename shown in your `pveam list local` output in the `pct create` command below — replace `debian-13-standard_13.0-1_amd64.tar.zst` if it differs.

## 1. Host (aegis) baseline

Debian 13 trixie with Proxmox VE. Storage: 128 GB NVMe (boot/OS/config) + Kingston SSD mounted at `/mnt/kingston` (ext4, media & downloads). Config is bind-mounted from `/srv/config` on pve-root; media and downloads from the Kingston SSD.

iGPU drivers on host:

```bash
apt install -y intel-media-va-driver vainfo
vainfo  # confirm /dev/dri/renderD128 is usable on host
```

Render group GID on host:

```bash
getent group render
# render:x:993:
```

### LVM layout

The default Proxmox install allocates 8 GB to swap and only ~644 MB to `pve/srv` (mounted at `/srv`). Service configs live under `/srv/config`; Jellyfin requires at least 2 GB free there to start. With 32 GB RAM, 2 GB swap is sufficient — reclaim the rest for `pve/srv`:

```bash
swapoff /dev/mapper/pve-swap
wipefs -a /dev/mapper/pve-swap   # wipe signature so LVM doesn't block the resize
lvreduce -L 2G /dev/pve/swap
mkswap /dev/mapper/pve-swap
swapon /dev/mapper/pve-swap

lvextend -L +6G /dev/pve/srv
resize2fs /dev/mapper/pve-srv

df -h /srv
# /dev/mapper/pve-srv  6.6G   22M  6.3G   1% /srv
```

## 2. Create LXC 100 (mediastack)

```bash
pct create 100 local:vztmpl/debian-13-standard_13.0-1_amd64.tar.zst \
  --hostname mediastack \
  --cores 8 \
  --memory 8192 \
  --rootfs local:16 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.0.50/24,gw=192.168.0.1 \
  --features nesting=1,keyctl=1 \
  --unprivileged 0 \
  --onboot 1
```

## 3. iGPU passthrough, TUN device, and bind mounts

Edit `/etc/pve/lxc/100.conf` on the host. Append:

```
# iGPU passthrough
lxc.cgroup2.devices.allow: c 226:0 rwm
lxc.cgroup2.devices.allow: c 226:128 rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir

# TUN device — required for gluetun VPN container
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file

# Bind mounts — media & downloads from Kingston SSD, config from NVMe
mp0: /mnt/kingston/media,mp=/mnt/media
mp1: /mnt/kingston/downloads,mp=/mnt/downloads
mp2: /srv/config,mp=/mnt/config
mp3: /mnt/kingston,mp=/mnt/kingston
```

Start the container:

```bash
pct start 100
```

## 4. Inside LXC: render group alignment, locale, vainfo

```bash
pct enter 100

# Update and upgrade first
apt update && apt upgrade -y

# Render group must match host GID 993
groupadd -g 993 render || groupmod -g 993 render
# If this fails with "GID '993' already exists", see the GID conflict note below

# Locale fix
apt install -y locales
sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

# iGPU userspace tools
apt install -y intel-media-va-driver vainfo
vainfo
# Expect: iHD driver 25.2.3, profiles for H.264, HEVC, VP9, AV1

# Cap OS logs to avoid filling the root disk
echo "SystemMaxUse=200M" >> /etc/systemd/journald.conf
systemctl restart systemd-journald
```

### GID conflict: "GID '993' already exists"

Debian 13 assigns system group GIDs dynamically during package installation. The LXC template may place a different group (commonly `kvm`) at 993, leaving `render` at 992. Since this is a privileged container (1:1 GID mapping), `renderD128` will show the wrong group name inside the LXC until the conflict is resolved.

Find the conflict and cascade the blocking groups into a free slot:

```bash
# Identify which groups sit at the conflicting GIDs
grep ':993:' /etc/group   # e.g. kvm:x:993:
grep ':994:' /etc/group   # e.g. clock:x:994:

# Find a free GID in the gap below 989 (or scan manually):
for gid in $(seq 985 999); do grep -q ":${gid}:" /etc/group || echo "free: $gid"; done

# Cascade example (substitute actual group names and free GID from your output):
groupmod -g <free_gid> clock   # move group at 994 to the free slot
groupmod -g 994 kvm            # move group at 993 to 994
groupmod -g 993 render         # render can now take 993
```

After the cascade `ls -la /dev/dri` should show `root:render` for `renderD128` without restarting the container.

## Verification

```bash
ls -la /dev/dri
# crw-rw---- 1 root render 226, 128 ... renderD128

cat /etc/group | grep render
# render:x:993:

ls -la /dev/net/tun
# crw-rw-rw- 1 root root 10, 200 ... /dev/net/tun

mount | grep mnt
# /mnt/kingston/media on /mnt/media type none (rw,bind)
# /mnt/kingston/downloads on /mnt/downloads type none (rw,bind)
# /srv/config on /mnt/config type none (rw,bind)
# /mnt/kingston on /mnt/kingston type none (rw,bind)
```

All four steps complete before moving to `mediastack-setup.md`.
