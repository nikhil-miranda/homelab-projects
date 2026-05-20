# Mediastack Setup (Steps 5–10)

Run inside LXC 100 (`pct enter 100` from aegis, or SSH to 192.168.0.50). Assumes `lxc-setup.md` is complete.

## 5. Install Docker CE

```bash
apt update
apt install -y ca-certificates curl gnupg git
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  > /etc/apt/sources.list.d/docker.list
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
```

Verify:

```bash
docker info | grep -E "Storage Driver|Cgroup Version"
docker run --rm hello-world
```

| Field | Required value | If different |
|---|---|---|
| Storage Driver | `overlay2` | Stop. Add `features: nesting=1,keyctl=1` to LXC config, restart. |
| Cgroup Version | `2` | Stop. Host must use cgroup v2 (Debian 13 default). |

## 6. Clone repo and stage `/root/mediastack`

```bash
cd /root
git clone https://github.com/nikhil-miranda/homelab-projects.git
ln -s /root/homelab-projects/proxmox-mediastack /root/mediastack
ln -s /root/homelab-projects/.env /root/mediastack/.env
cd /root/mediastack
```

The first symlink keeps the conventional `/root/mediastack` path while files live in the git working tree. `git pull` updates the running config in place.

The second symlink lets `docker compose` auto-discover the root `.env` without any flags.

Create config and data directories on the bind mounts:

```bash
mkdir -p /mnt/config/{gluetun,qbittorrent,prowlarr,sonarr,radarr,bazarr,jellyfin}
mkdir -p /mnt/media/{tv,movies}
mkdir -p /mnt/downloads/{incomplete,complete}
```

## 7. Create local `.env`

```bash
cp /root/homelab-projects/.env.example /root/homelab-projects/.env
chmod 600 /root/homelab-projects/.env
nano /root/homelab-projects/.env
```

Fill in from your ProtonVPN WireGuard config (`.conf` file from account.protonvpn.com → Downloads → WireGuard):

| Field | Source |
|---|---|
| `WIREGUARD_PRIVATE_KEY` | `PrivateKey =` line under `[Interface]` |
| `WIREGUARD_ADDRESSES` | `Address =` line under `[Interface]` (IPv4 only, e.g. `10.2.0.2/32`) |
| `WIREGUARD_PRESHARED_KEY` | Leave blank — ProtonVPN does not use this |
| `SERVER_COUNTRIES` | Country you want the exit node in (e.g. `Netherlands`) |

## 8. Bring up the stack

```bash
cd /root/mediastack
docker compose pull
docker compose up -d
docker compose ps
docker compose logs -f gluetun
```

Wait for gluetun to report `healthy`. Ctrl-C out of logs.

**VPN kill-switch verification (mandatory before any torrent traffic):**

```bash
# Both should return VPN endpoint IP, not your ISP IP
docker exec gluetun wget -qO- https://ipinfo.io/ip
docker exec qbittorrent wget -qO- https://ipinfo.io/ip

# Kill-switch test
docker stop gluetun
docker exec qbittorrent wget -qO- --timeout=5 https://ipinfo.io/ip || echo "PASS: no leak"
docker start gluetun
```

If qBittorrent's IP matches your ISP, stop. Do not torrent until the kill-switch passes.

Get qBittorrent temporary password:

```bash
docker logs qbittorrent 2>&1 | grep -i "temporary password"
```

## 9. Web UI configuration

### Access URLs

| Service | URL | First-run credentials |
|---|---|---|
| qBittorrent | http://192.168.0.50:8080 | admin / (temp from logs above) |
| Prowlarr | http://192.168.0.50:9696 | set on first load |
| Sonarr | http://192.168.0.50:8989 | set on first load |
| Radarr | http://192.168.0.50:7878 | set on first load |
| Bazarr | http://192.168.0.50:6767 | set on first load |
| Jellyfin | http://192.168.0.50:8096 | wizard on first load |

### Inter-service URLs (use these in settings, not the LAN IP)

| From | To | URL | Where to enter |
|---|---|---|---|
| Sonarr | qBittorrent | `http://gluetun:8080` | Settings → Download Clients → qBittorrent |
| Radarr | qBittorrent | `http://gluetun:8080` | Settings → Download Clients → qBittorrent |
| Prowlarr | Sonarr | `http://sonarr:8989` | Settings → Apps → Sonarr |
| Prowlarr | Radarr | `http://radarr:7878` | Settings → Apps → Radarr |
| Bazarr | Sonarr | `http://sonarr:8989` | Settings → Sonarr |
| Bazarr | Radarr | `http://radarr:7878` | Settings → Radarr |

API keys: Settings → General → Security in each `*arr` app.

### Root folders

| Service | Path inside container |
|---|---|
| Sonarr root folder | `/media/tv` |
| Radarr root folder | `/media/movies` |
| qBittorrent default save | `/downloads/incomplete` |
| qBittorrent completed move to | `/downloads/complete` |

### qBittorrent extra settings

| Setting | Value | Reason |
|---|---|---|
| WebUI → Authentication → Bypass for LAN | Enable, `192.168.0.0/24` | Saves repeated login |
| Downloads → Default Save Path | `/downloads/incomplete` | |
| Downloads → Keep incomplete in | `/downloads/incomplete` | |
| Downloads → Completed move to | `/downloads/complete` | |
| Connection → Listening port | `6881` | Matches gluetun port forward |

## 10. Jellyfin hardware acceleration

Dashboard → Playback → Transcoding:

| Setting | Value |
|---|---|
| Hardware acceleration | Intel QuickSync (QSV) |
| QSV device | (leave blank, auto-detects renderD128) |
| Enable hardware decoding | H.264, HEVC, VP9, AV1 |
| Enable hardware encoding | H.264, HEVC |
| Enable HEVC encoding | Yes |
| Enable VPP tone mapping | Yes |
| Enable tone mapping | Yes |

Verify after saving:

```bash
# Play any 4K HEVC file first, then:
docker exec jellyfin ps -ef | grep ffmpeg
# Look for: -hwaccel qsv -init_hw_device qsv

docker exec jellyfin id
# Confirm 993 (render) in supplementary groups
```

## 11. Ongoing maintenance

```bash
# Update stack
cd /root/mediastack
git pull
docker compose pull
docker compose up -d

# Logs for one service
docker compose logs -f sonarr

# Check disk usage on aegis (pve-root must not fill up — /tank/ lives there)
df -h /   # run on aegis host, not in LXC
```

## Known pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| gluetun never goes healthy | Wrong WireGuard key or country | Re-check `.env`, regenerate config from ProtonVPN |
| qBittorrent stuck in `created` | gluetun unhealthy, `depends_on` blocking | Fix gluetun first |
| Storage driver `vfs` not `overlay2` | LXC features missing | Add `features: nesting=1,keyctl=1` to LXC conf, restart |
| Jellyfin transcode falls back to software | GID mismatch | `docker exec jellyfin id`, confirm 993 present |
| Sonarr cannot import from qBittorrent | Path mismatch | Both use `/downloads` — no remote path mapping needed with this compose |
| LAN devices cannot reach qBittorrent WebUI | gluetun firewall | Confirm `LAN_SUBNET=192.168.0.0/24` in `.env` |
| Any service: `AppFolder /config is not writable` | Config dir owned by wrong user | On aegis: `chown -R ${PUID}:${PGID} /tank/config/<service>`, then `docker compose restart <service>` |
| Any service: `No space left on device` or `insufficient free space` | pve-root full — `/tank/` is on pve-root (no dedicated storage disk) | On aegis: `df -h /`. If 100%, check for stale data hidden under bind mounts: `mkdir /mnt/pveroot-check && mount --bind / /mnt/pveroot-check && du -sh /mnt/pveroot-check/tank/*`. Delete stale contents, then `umount /mnt/pveroot-check`. |
