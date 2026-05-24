# Mediastack Setup (Steps 5–11)

Run inside LXC 100 (`pct enter 100` from aegis, or SSH to 192.168.0.50). Assumes steps 1–4 are complete — follow either `lxc-setup.md` (CLI) or `lxc-setup-ui.md` (Proxmox web UI) first.

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

Configure log rotation before starting any containers:

```bash
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
systemctl restart docker
```

This caps each container at 30 MB of logs (3 × 10 MB), ~240 MB total across the stack.

Verify:

```bash
docker info | grep -E "Storage Driver|Cgroup Version"
docker run --rm hello-world
```

| Field | Required value | If different |
|---|---|---|
| Storage Driver | `overlay2` | Stop. Add `features: nesting=1,keyctl=1` to LXC config, restart. |
| Cgroup Version | `2` | Stop. Host must use cgroup v2 (Debian 13 default). |

## 6. Clone repo

```bash
cd /root
git clone https://github.com/nikhil-miranda/homelab-projects.git
cd /root/homelab-projects/mediastack
```

`git pull` from `/root/homelab-projects/mediastack` updates the running config in place.

Create config and data directories on the bind mounts:

```bash
mkdir -p /mnt/config/{gluetun,qbittorrent,prowlarr,sonarr,radarr,bazarr,jellyfin,flaresolverr,tailscale-jellyfin}
mkdir -p /mnt/kingston/media/{tv,movies}
mkdir -p /mnt/kingston/downloads/{incomplete,complete}
```

## 7. Create local `.env`

```bash
cp .env.example .env
chmod 600 .env
nano .env
```

The `.env.example` has `DATA_PATH=/mnt/kingston` — this single path covers both media and downloads inside containers and is required for hardlinks to work (see Known pitfalls).

Fill in from your ProtonVPN WireGuard config (`.conf` file from account.protonvpn.com → Downloads → WireGuard):

| Field | Source |
|---|---|
| `WIREGUARD_PRIVATE_KEY` | `PrivateKey =` line under `[Interface]` |
| `WIREGUARD_ADDRESSES` | `Address =` line under `[Interface]` (IPv4 only, e.g. `10.2.0.2/32`) |
| `WIREGUARD_PRESHARED_KEY` | Leave blank — ProtonVPN does not use this |
| `SERVER_COUNTRIES` | Country you want the exit node in (e.g. `Netherlands`) |

## 8. Bring up the stack

```bash
cd /root/homelab-projects/mediastack
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
| FlareSolverr | http://192.168.0.50:8191 | no auth — internal only |

### Inter-service URLs (use these in settings, not the LAN IP)

| From | To | URL | Where to enter |
|---|---|---|---|
| Sonarr | qBittorrent | `http://gluetun:8080` | Settings → Download Clients → qBittorrent |
| Radarr | qBittorrent | `http://gluetun:8080` | Settings → Download Clients → qBittorrent |
| Prowlarr | Sonarr | `http://sonarr:8989` | Settings → Apps → Sonarr |
| Prowlarr | Radarr | `http://radarr:7878` | Settings → Apps → Radarr |
| Prowlarr | FlareSolverr | `http://192.168.0.50:8191` | Settings → Indexers → Add Indexer Proxy → FlareSolverr |
| Bazarr | Sonarr | `http://sonarr:8989` | Settings → Sonarr |
| Bazarr | Radarr | `http://radarr:7878` | Settings → Radarr |

API keys: Settings → General → Security in each `*arr` app.

### Root folders

| Service | Path inside container |
|---|---|
| Sonarr root folder | `/data/media/tv` |
| Radarr root folder | `/data/media/movies` |
| qBittorrent default save | `/downloads/complete` |
| qBittorrent incomplete keep | `/downloads/incomplete` |

> **Critical:** Radarr's only movie root folder must be `/data/media/movies`, and Sonarr's only root must be `/data/media/tv`. **Never add `/data/downloads` (or `/data/downloads/complete`) as a root folder.** If a downloads path is registered as a root folder, movies get stored back inside the downloads tree instead of `/data/media/movies` — and Jellyfin, which only scans `/media/movies`, never sees them. Verify under Settings → Media Management → Root Folders that no downloads path is listed.

### qBittorrent extra settings

| Setting | Value | Reason |
|---|---|---|
| WebUI → Authentication → Bypass for LAN | Enable, `192.168.0.0/24` | Saves repeated login |
| Downloads → Default Save Path | `/downloads/complete` | Final destination for finished torrents |
| Downloads → Keep incomplete torrents in (checkbox) | Enable, `/downloads/incomplete` | Temp location while downloading |
| Connection → Listening port | `6881` | Matches gluetun port forward |

> **Note:** Newer qBittorrent versions (5.x) removed the separate "Completed move to" option. Set **Default Save Path** to `/downloads/complete` and enable the **"Keep incomplete torrents in"** checkbox with `/downloads/incomplete` to get the same behaviour.

### Radarr: remote path mapping (required for auto-import)

qBittorrent reports completed downloads using its internal path (`/downloads/complete/...`), but Radarr's container sees the same directory at `/data/downloads/complete/...`. Without this mapping, auto-import silently fails every time.

Radarr → Settings → Download Clients → Remote Path Mappings → **+**

| Field | Value |
|---|---|
| Host | `gluetun` |
| Remote Path | `/downloads` |
| Local Path | `/data/downloads` |

Repeat in Sonarr → Settings → Download Clients → Remote Path Mappings with the same values.

### Radarr: quality profile

Radarr ships with a default **Any** profile that accepts all quality tiers. If you want finer control:

Settings → Quality → edit the profile → check which tiers to allow (e.g. `Bluray-1080p`, `WEB-1080p`, `Bluray-2160p`, `WEB-2160p`). The **Cutoff** sets the minimum quality Radarr will keep; tiers below it get auto-upgraded when a better copy is found.

Custom format scoring (Dolby Vision, HDR10+, x265, Atmos) lives under Settings → Custom Formats. The defaults score everything at 0 — edit only if you want Radarr to prefer or reject specific encodings.

### Radarr/Sonarr: import lists

Import lists (TMDb Popular, StevenLu, Trakt, etc.) auto-populate the library with many titles — often hundreds of unreleased "popular" movies that clutter the library. For a personal setup they are usually best left **disabled** (Settings → Import Lists). If you do enable one, its **Root Folder must be `/data/media/movies`** (Sonarr: `/data/media/tv`) — every movie a list adds inherits that list's root-folder setting. A list pointed at `/data/downloads/complete` silently routes every added movie into the downloads tree, where Jellyfin never sees it.

### Adding movies and importing

**Normal workflow — Radarr manages the full pipeline:**

1. Movies → Add New → search for the title → choose a quality profile → **Add Movie**
2. On the movie's detail page click **Search Now** — Radarr finds a torrent via Prowlarr, sends it to qBittorrent, monitors the download, then auto-imports and renames the file when complete.

**Manual import — file already sits in `/downloads/complete`:**

1. Movies → Add New → add the movie to the library (leave "Start search" unchecked)
2. Open that movie's detail page → click the folder icon (Manual Import)
3. Navigate to `/data/downloads/complete/[movie folder]` → confirm the match → Import

**Library Import vs Manual Import:**

| Screen | What it does |
|---|---|
| Movies → Library Import | Scans `/data/media/movies` for files not yet linked to a library entry. An **Existing** badge means the file is already associated — no action needed; the checkbox will be disabled. |
| Movie detail → folder icon | Manual Import — lets you point Radarr at any file on disk and link it to that specific library entry. Use this for files stuck in downloads. |

### Radarr/Sonarr → Jellyfin: instant library updates

By default Jellyfin only notices new files on its scheduled scan, so a freshly imported movie can take a while to appear (and may look like it "sometimes shows, sometimes doesn't"). To make it instant, have Radarr/Sonarr refresh Jellyfin on import.

Radarr → Settings → Connect → **+** → **Emby / Jellyfin** (this connection type works for Jellyfin):

| Field | Value |
|---|---|
| URL / Host | `http://tailscale-jellyfin:8096` (Jellyfin shares that container's network namespace) |
| API Key | Jellyfin → Dashboard → API Keys → **+** to create one |
| Triggers | On Import, On Upgrade, On Rename |
| Update Library | Enabled |

Repeat in Sonarr → Settings → Connect with the same Jellyfin host and API key. Use **Test** to confirm reachability before saving.

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
cd /root/homelab-projects/mediastack
git pull
docker compose pull
docker compose up -d

# Logs for one service
docker compose logs -f sonarr

# Check disk usage on aegis
df -h /              # pve-root: Proxmox OS + Docker logs (capped at ~240MB total)
df -h /mnt/kingston  # SATA SSD: all media and downloads
```

## 12. Tailscale remote access

Jellyfin is exposed on the tailnet via a Tailscale sidecar container that shares Jellyfin's network namespace (same pattern as gluetun → qBittorrent).

### Generate an auth key

1. Go to https://login.tailscale.com/admin/settings/keys
2. Click **Generate auth key**
3. Set **Reusable** ✓ and **Expiry** to your preference (or never)
4. Copy the key (`tskey-auth-…`)

### Add to `.env`

```bash
nano /root/homelab-projects/mediastack/.env
```

Fill in:

```
TAILSCALE_AUTHKEY=tskey-auth-...
TS_HOSTNAME=jellyfin        # appears as this name in Tailscale admin
```

### Create the config directory and bring up

```bash
mkdir -p /mnt/config/tailscale-jellyfin
docker compose up -d tailscale-jellyfin
docker compose up -d jellyfin
```

### Verify

```bash
# Confirm tailscale-jellyfin joined the tailnet
docker exec tailscale-jellyfin tailscale status

# Should show the node name and tailnet IP (100.x.x.x)
```

### Access URLs

| Network | URL |
|---|---|
| LAN | http://192.168.0.50:8096 (unchanged) |
| Tailnet (MagicDNS off) | http://100.x.x.x:8096 |
| Tailnet (MagicDNS on) | http://jellyfin:8096 or http://jellyfin.\<tailnet\>.ts.net:8096 |

## Reset / Start fresh

To tear down the entire stack and return LXC 100 to a clean state, run the reset script from inside the LXC:

```bash
# Interactive (prompts for each destructive step)
bash /root/homelab-projects/scripts/reset-mediastack.sh

# Non-interactive (skips all prompts — use carefully)
bash /root/homelab-projects/scripts/reset-mediastack.sh -y
```

**What gets wiped:**

| Resource | Action |
|---|---|
| Docker containers, images, volumes, networks, build cache | Fully removed (`docker system prune -af --volumes`) |
| Service config dirs under `/mnt/config` | Removed and recreated empty |
| `.env` (secrets) | Removed |
| `/mnt/kingston/downloads` | Optional — prompted separately |
| `/mnt/kingston/media` | **Never touched** |
| Repo at `/root/homelab-projects` | **Never touched** |

After the reset, follow steps 6–11 above to bring the stack back up.

## Known pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| gluetun never goes healthy | Wrong WireGuard key or country | Re-check `.env`, regenerate config from ProtonVPN |
| qBittorrent stuck in `created` | gluetun unhealthy, `depends_on` blocking | Fix gluetun first |
| Prowlarr: SSL connection could not be established | Indexer behind Cloudflare DDoS protection | Add FlareSolverr proxy (see inter-service URLs above) and tag affected indexers |
| FlareSolverr stuck in `created` | gluetun unhealthy, `depends_on` blocking | Fix gluetun first (FlareSolverr shares gluetun network) |
| Storage driver `vfs` not `overlay2` | LXC features missing | Add `features: nesting=1,keyctl=1` to LXC conf, restart |
| Jellyfin transcode falls back to software | GID mismatch | `docker exec jellyfin id`, confirm 993 present |
| Radarr/Sonarr auto-import silently fails after download completes | Path mismatch — qBittorrent reports paths as `/downloads/...` but Radarr/Sonarr see the same folder at `/data/downloads/...` | Add a Remote Path Mapping in Radarr and Sonarr: Settings → Download Clients → Remote Path Mappings → Host: `gluetun`, Remote Path: `/downloads`, Local Path: `/data/downloads` |
| Movie/episode downloads and imports but never appears in Jellyfin | The item's folder path is under `/data/downloads`, not `/data/media/...` — caused by a downloads path registered as a Radarr/Sonarr root folder and/or an import list whose Root Folder points at downloads | Remove the downloads root folder (Settings → Media Management → Root Folders), set every import list's Root Folder to `/data/media/movies` (or `/data/media/tv`), then re-root affected items (Movie/Series Editor → Root Folder → Move Files) so files land under `/data/media/...`. Confirm in Settings → Media Management that only the media roots remain. |
| Radarr/Sonarr copies downloads instead of hardlinking — `du` shows double the movie size | Separate Docker volume mounts (`/media` and `/downloads`) appear as different filesystems; `link()` fails with EXDEV so the app falls back to copy | `DATA_PATH=/mnt/kingston` and the single `/data` mount in compose puts both paths on the same filesystem inside the container. Verify: `ls -i /mnt/kingston/downloads/complete/<file> /mnt/kingston/media/movies/<movie>/<file>` — inode numbers must match |
| LAN devices cannot reach qBittorrent WebUI | gluetun firewall | Confirm `LAN_SUBNET=192.168.0.0/24` in `.env` |
| Any service: `AppFolder /config is not writable` | Config dir owned by wrong user | On aegis: `chown -R ${PUID}:${PGID} /srv/config/<service>`, then `docker compose restart <service>` |
| Any service: `No space left on device` on SATA SSD | SATA SSD full — media or downloads filling `/mnt/kingston` | On aegis: `df -h /mnt/kingston`. Remove unwanted media or stale completed downloads. |
| Jellyfin: `The path /config/data/data has insufficient free space. Required: 2GiB` | `pve/srv` LV is too small (default ~644 MB); Jellyfin refuses to start with less than 2 GB free | On aegis: shrink swap and extend `pve/srv` — see LVM layout section in `lxc-setup.md` |
| Any service: `No space left on device` on pve-root (NVMe) | Rare — Docker logs are capped at 10 MB × 3 files per service (~240 MB total). If it happens, check with `du -sh /var/lib/docker/containers/` inside LXC | Run `docker compose down && docker compose up -d` to rotate logs; check for other consumers with `du -sh /var/lib/docker/*` |
| `failed to mount … no space left on device` on `docker compose up` | rootfs (LXC disk) is full — images alone are ~15 GB on a 16 GB root | On aegis: `pct resize 100 rootfs +8G`. Inside LXC: `resize2fs /dev/loop0`. Then repull with `docker compose pull && docker compose up -d` |
