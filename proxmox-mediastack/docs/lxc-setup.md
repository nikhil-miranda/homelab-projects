# LXC Setup (Steps 1–4)

Records the host and LXC prep that precedes the Docker stack. Already complete; do not re-run on a working system.

## 1. Host (aegis) baseline

Debian 13 trixie with Proxmox VE. ZFS pool `tank` with datasets `tank/media`, `tank/downloads`, `tank/config`.

iGPU drivers on host:

```bash
apt install -y intel-media-va-driver-non-free vainfo
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
  --rootfs local-lvm:16 \
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

# ZFS bind mounts
mp0: /tank/media,mp=/mnt/media
mp1: /tank/downloads,mp=/mnt/downloads
mp2: /tank/config,mp=/mnt/config
```

Start the container:

```bash
pct start 100
```

## 4. Inside LXC: render group alignment, locale, vainfo

```bash
pct enter 100

# Render group must match host GID 993
groupadd -g 993 render || groupmod -g 993 render

# Locale fix
apt update
apt install -y locales
sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

# iGPU userspace tools
apt install -y intel-media-va-driver-non-free vainfo
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
# /tank/media on /mnt/media type zfs ...
# /tank/downloads on /mnt/downloads type zfs ...
# /tank/config on /mnt/config type zfs ...
```

All four steps complete before moving to `mediastack-setup.md`.
