#!/usr/bin/env bash
# On-demand cleanup for aegis (Proxmox VE / Debian 13)
# Usage: cleanup.sh [-y]   (-y skips confirmation prompt)
set -euo pipefail

AUTOYES=0
[[ "${1:-}" == "-y" ]] && AUTOYES=1

hr() { printf '%s\n' "──────────────────────────────────────"; }

header() {
  hr
  echo "  aegis cleanup — $(date '+%Y-%m-%d %H:%M:%S')"
  hr
}

section() { echo; echo "▸ $*"; }

confirm() {
  [[ $AUTOYES -eq 1 ]] && return 0
  read -rp "Proceed? [y/N] " ans
  [[ "${ans,,}" == "y" ]]
}

disk_usage() {
  df -h / | awk 'NR==2 { printf "  /              %s used of %s (%s)\n", $3, $2, $5 }'
  df -h /var | awk 'NR==2 { printf "  /var           %s used of %s (%s)\n", $3, $2, $5 }' 2>/dev/null || true
  df -h /mnt/kingston | awk 'NR==2 { printf "  /mnt/kingston  %s used of %s (%s)\n", $3, $2, $5 }' 2>/dev/null || true
}

header
echo "Disk before:"
disk_usage

# ── 1. apt cache ────────────────────────────────────────────────────────────
section "apt: clean cache + autoremove"
apt-get clean -q
apt-get autoremove -y -q
echo "  done"

# ── 2. journal logs ─────────────────────────────────────────────────────────
section "journald: vacuum to 200 MB / 14 days"
journalctl --vacuum-size=200M --vacuum-time=14d 2>&1 | grep -v "^$" | sed 's/^/  /'

# ── 3. old /var/log files ───────────────────────────────────────────────────
section "log files: remove rotated .gz older than 14 days"
find /var/log -name "*.gz" -mtime +14 -delete -print | sed 's/^/  removed: /'
find /var/log -name "*.log.[0-9]*" -mtime +14 -delete -print | sed 's/^/  removed: /' || true

# ── 4. Proxmox task log (keeps last 1000 entries) ───────────────────────────
section "Proxmox task log: trim to last 1000 entries"
TASK_LOG=/var/log/pve/tasks/index
if [[ -f "$TASK_LOG" ]]; then
  LINES=$(wc -l < "$TASK_LOG")
  if (( LINES > 1000 )); then
    tail -1000 "$TASK_LOG" > "${TASK_LOG}.tmp" && mv "${TASK_LOG}.tmp" "$TASK_LOG"
    echo "  trimmed $LINES → 1000 entries"
  else
    echo "  $LINES entries, no trim needed"
  fi
else
  echo "  not found, skipping"
fi

# ── 5. Proxmox vzdump backups older than 7 days ─────────────────────────────
DUMP_DIR=/var/lib/vz/dump
section "vzdump backups in $DUMP_DIR older than 7 days"
OLD_DUMPS=$(find "$DUMP_DIR" -maxdepth 1 \( -name "*.tar.zst" -o -name "*.tar.gz" -o -name "*.vma.zst" \) -mtime +7 2>/dev/null || true)
if [[ -n "$OLD_DUMPS" ]]; then
  echo "$OLD_DUMPS" | sed 's/^/  found: /'
  echo
  confirm && echo "$OLD_DUMPS" | xargs rm -v | sed 's/^/  removed: /' || echo "  skipped"
else
  echo "  none found"
fi

# ── 6. /tmp ──────────────────────────────────────────────────────────────────
section "/tmp: files older than 3 days"
find /tmp -mindepth 1 -mtime +3 -delete -print 2>/dev/null | head -20 | sed 's/^/  removed: /' || true

# ── Done ─────────────────────────────────────────────────────────────────────
echo
hr
echo "Disk after:"
disk_usage
hr
echo "  cleanup complete"
