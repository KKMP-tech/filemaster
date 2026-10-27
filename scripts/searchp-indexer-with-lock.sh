#!/bin/sh
# Serialize full-index and delta-index across the long-running searchp-server
# (ofelia exec) and one-off `docker compose run` containers via a shared flock.
set -eu

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 full-index|delta-index [indexer-arg ...]" >&2
  exit 2
fi

mode=$1
shift
lock_path=${SEARCHP_INDEXER_LOCK_PATH:-/indexer_lock/searchp-indexer.lock}
flock_bin=${SEARCHP_INDEXER_FLOCK_BIN:-flock}

case "$mode" in
  full-index)
    # Wait for an in-flight delta, then hold the lock for the whole full-index.
    exec "$flock_bin" "$lock_path" ./searchp-indexer full-index "$@"
    ;;
  delta-index)
    # Skip quietly when full-index (or another delta) holds the lock.
    # flock -E 75: busy is distinct from indexer failures (which often exit 1).
    set +e
    "$flock_bin" -n -E 75 "$lock_path" ./searchp-indexer delta-index "$@"
    ec=$?
    set -e
    if [ "$ec" -eq 75 ]; then
      echo "searchp delta-index skipped: indexer lock held" >&2
      exit 0
    fi
    exit "$ec"
    ;;
  *)
    echo "Usage: $0 full-index|delta-index [indexer-arg ...]" >&2
    exit 2
    ;;
esac
