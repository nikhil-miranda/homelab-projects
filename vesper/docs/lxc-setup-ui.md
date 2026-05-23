# LXC Setup via Proxmox Web UI (Steps 1–4)

Alternative to `lxc-setup.md` — uses the Proxmox web interface and shell console instead of `pct` CLI commands. End state is identical; choose whichever flow you prefer.

**Prerequisite:** Complete `kingston-ssd-setup.md` steps 1–4 first (format, mount, fstab, create directories) so `/mnt/kingston` is ready before creating the LXC.

## Before you start

If recreating an existing LXC, destroy it first via the UI: select CT 100 in the sidebar → **More** → **Stop**, wait for it to stop, then **More** → **Destroy**.

Verify bind-mount source directories on the host survived (SSH to aegis):

```bash
ls /srv/config         # config stays on NVMe (pve-root)
ls /mnt/kingston/      # media and downloads on Kingston SSD
# Expected: media  downloads
```

If missing:

```bash
mkdir -p /srv/config
mkdir -p /mnt/kingston/media/{tv,movies}
mkdir -p /mnt/kingston/downloads/{incomplete,complete}
```

Download the Debian 13 template via UI: **local** storage → **CT Templates** → **Templates** button → search `debian-13` → Download. Note the exact filename shown after download.

## 1. Host (aegis) baseline

SSH to aegis and install iGPU drivers:

```bash
apt install -y intel-media-va-driver vainfo
vainfo  # confirm /dev/dri/renderD128 is usable
getent group render
# render:x:993:
```

## 2. Create LXC 100 via web UI

Open `https://aegis:8006` → **Create CT** (top-right button).

| Tab | Field | Value |
|---|---|---|
| General | Node | aegis |
| General | CT ID | 100 |
| General | Hostname | mediastack |
| General | Unprivileged container | **unchecked** (privileged) |
| General | Password | (set a root password) |
| Template | Storage | local |
| Template | Template | debian-13-standard_13.x-x_amd64.tar.zst |
| Disks | Storage | local |
| Disks | Disk size | 16 GiB |
| CPU | Cores | 8 |
| Memory | Memory | 8192 MiB |
| Memory | Swap | 512 MiB |
| Network | Name | eth0 |
| Network | Bridge | vmbr0 |
| Network | IPv4 | Static |
| Network | IPv4/CIDR | 192.168.0.50/24 |
| Network | Gateway | 192.168.0.1 |
| DNS | (leave defaults) | |

**Do not start after created** — leave the checkbox unchecked on the Confirm tab.

## 3. iGPU passthrough and bind mounts

iGPU passthrough and arbitrary bind mounts cannot be configured through the web UI — they require editing the LXC config file directly on the host.

SSH to aegis and open the config:

```bash
nano /etc/pve/lxc/100.conf
```

Find or add the `features:` line and ensure it includes `nesting=1,keyctl=1`:

```
features: nesting=1,keyctl=1
```

Append at the end of the file:

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

Start the container: select CT 100 in the sidebar → **Start** button (or `pct start 100` on aegis).

## 4. Inside LXC: render group alignment, locale, vainfo

Use the **Console** tab in the web UI (select CT 100 → **Console**), or run `pct enter 100` from an aegis SSH session:

```bash
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

All four steps complete — continue with `mediastack-setup.md`.
