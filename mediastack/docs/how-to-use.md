# How to Watch Movies

End-to-end walkthrough: find a movie → download it → watch it in Jellyfin.

## Prerequisites

- Mediastack is running (`docker compose ps` shows all services healthy inside LXC 100)
- Prowlarr has at least one indexer configured
- Radarr is connected to Prowlarr and qBittorrent (see [mediastack-setup.md](mediastack-setup.md) §9)

---

## 1. Add a Movie in Radarr

Open **Radarr** at http://192.168.0.50:7878.

1. Click **+ Add Movie** (top nav → Movies → Add New).
2. Search for the film by title.
3. Select the correct result from TMDB.
4. Choose a **Quality Profile** (e.g. `HD-1080p`).
5. Set **Root Folder** to `/media/movies` (should be the default).
6. Click **Add Movie** → then **Search** to trigger an immediate grab, or let Radarr monitor and grab automatically when a release appears.

Radarr will ask Prowlarr to search all configured indexers and push the best match to qBittorrent.

---

## 2. Monitor the Download

Open **qBittorrent** at http://192.168.0.50:8080.

- The torrent appears in the list with its progress.
- **Category** will be `radarr` (set automatically).
- Files land in `/downloads/incomplete` while downloading, then move to `/downloads/complete` on finish.

Radarr polls qBittorrent and imports the file into `/media/movies/<Title (Year)>/` once the download completes and passes its quality check.

To watch Radarr's import step: **Activity → Queue** in Radarr shows pending imports.

---

## 3. Subtitles (Automatic)

Bazarr monitors Radarr imports and downloads subtitles automatically — nothing to do. To check or force a subtitle search:

1. Open **Bazarr** at http://192.168.0.50:6767.
2. Go to **Movies** → find the title → click the subtitle icon to trigger a manual search.

Default subtitle language is whatever you configured during setup (Settings → Languages in Bazarr).

---

## 4. Watch in Jellyfin

Open **Jellyfin** at http://192.168.0.50:8096 (or use the Jellyfin app on your TV, phone, or browser).

1. Your movie appears in the **Movies** library once Radarr imports it (Jellyfin scans automatically every few minutes, or you can trigger **Scan Library** manually from Dashboard → Libraries).
2. Click the movie poster → **Play**.
3. Jellyfin streams with Intel QSV hardware transcode — 4K HEVC plays without dropping frames.

### Apps

| Platform | App |
|---|---|
| iOS / Android | Jellyfin (official, free) or Infuse (paid, better UI) |
| Apple TV / Fire TV | Jellyfin (official) or Infuse |
| Browser | http://192.168.0.50:8096 (no install needed) |
| Smart TV | Jellyfin app from your TV's app store |

For Infuse, point it at `http://192.168.0.50:8096` and sign in with your Jellyfin credentials.

---

## Troubleshooting

| Symptom | Check |
|---|---|
| Radarr shows no search results | Prowlarr indexers — open Prowlarr → Indexers, test each one |
| Download stuck at 0% | qBittorrent peers — may be an unpopular torrent; try a different release in Radarr → Activity → Queue |
| Movie imported but missing from Jellyfin | Dashboard → Libraries → Scan Movies; check file landed in `/media/movies/` |
| Subtitles missing | Bazarr → Movies → manual subtitle search; confirm language profile is set |
| Jellyfin falls back to software transcode | Run `docker exec jellyfin id` inside LXC — confirm GID 993 (render) is present |
| "File not found" on playback | Check that `/mnt/kingston/media` is still mounted on aegis: `mount | grep kingston` |
