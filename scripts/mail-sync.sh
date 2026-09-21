#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  "") arcmac_sync_wait=false ;;
  --wait) arcmac_sync_wait=true ;;
  *) echo "Usage: mail-sync [--wait]" >&2; exit 64 ;;
esac
if [ "$#" -gt 1 ]; then
  echo "Usage: mail-sync [--wait]" >&2
  exit 64
fi

arcmac_sync_lock_dir="${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/arcmac}"
mkdir -p -- "$arcmac_sync_lock_dir"
# Keep the lock file: unlinking it can let a new process bypass a waiter.
exec 9>"$arcmac_sync_lock_dir/arcmac-mail-sync.lock"
if "$arcmac_sync_wait"; then
  echo "Waiting for mail sync lock…"
  flock 9
elif flock --nonblock --conflict-exit-code 75 9; then
  :
else
  arcmac_sync_status=$?
  if [ "$arcmac_sync_status" -eq 75 ]; then
    echo "Mail sync already running"
  fi
  exit "$arcmac_sync_status"
fi

trap 'arcmac_sync_status=$?; echo "Mail sync failed (exit $arcmac_sync_status)" >&2; exit "$arcmac_sync_status"' ERR
echo "Fetching mail…"
mbsync -a
echo "Indexing and tagging mail…"
notmuch new
echo "Pushing local changes…"
mbsync -a
echo "Mail sync done"
