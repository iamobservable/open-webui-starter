#!/bin/sh
set -euo pipefail
DSN_SOURCE=""
if [ -f /run/secrets/postgres_exporter_dsn ]; then
  DSN_SOURCE=/run/secrets/postgres_exporter_dsn
elif [ -f /etc/postgres_exporter_dsn.txt ]; then
  DSN_SOURCE=/etc/postgres_exporter_dsn.txt
fi

if [ -n "$DSN_SOURCE" ]; then
  DATA_SOURCE_NAME="$(tr -d '\r' < "$DSN_SOURCE")"
  export DATA_SOURCE_NAME
else
  echo "postgres-exporter entrypoint: DSN file not found" >&2
  exit 1
fi

exec /bin/postgres_exporter "$@"
