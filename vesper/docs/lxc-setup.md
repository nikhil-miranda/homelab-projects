# LXC Setup (Steps 1–4)

Run on the Proxmox host (aegis). Covers host prep, LXC creation, iGPU passthrough, and inside-LXC baseline. Follow `mediastack-setup.md` after this.

**Prerequisite:** Complete `kingston-ssd-setup.md` steps 1–4 first (format, mount, fstab, create directories) so `/mnt/kingston` is ready before creating the LXC.

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

## 3. iGPU passthrough and bind mounts

Edit `/etc/pve/lxc/100.conf` on the host. Append:

```
# iGPU passthrough
lxc.cgroup2.devices.allow: c 226:0 rwm
lxc.cgroup2.devices.allow: c 226:128 rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir

# Bind mounts — media & downloads from Kingston SSD, config from NVMe
mp0: /mnt/kingston/media,mp=/mnt/media
mp1: /mnt/kingston/downloads,mp=/mnt/downloads
mp2: /srv/config,mp=/mnt/config
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

# Locale fix
apt install -y locales
sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

# iGPU userspace tools
apt install -y intel-media-va-driver vainfo
vainfo
# Expect: iHD driver 25.2.3, profiles for H.264, HEVC, VP9, AV1
```

## Verification

```bash
ls -la /dev/dri
# crw-rw---- 1 root render 226, 128 ... renderD128

cat /etc/group | grep render
# render:x:993:

mount | grep mnt
# /mnt/kingston/media on /mnt/media type none (rw,bind)
# /mnt/kingston/downloads on /mnt/downloads type none (rw,bind)
# /srv/config on /mnt/config type none (rw,bind)
```

All four steps complete before moving to `mediastack-setup.md`.
