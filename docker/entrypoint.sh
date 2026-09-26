#!/bin/sh
# One container, two processes. GOWA only listens on loopback, so the phone can
# reach the adapter and nothing else; the adapter reaches GOWA over localhost.
set -eu

gowa_bin="${GOWA_BIN:-/usr/local/bin/whatsapp}"
gowa_port="${GOWA_PORT:-3000}"
gowa_host="${GOWA_HOST:-127.0.0.1}"

# The credentials are optional, so keep the empty case out of the argument list.
if [ -n "${GOWA_USER:-}" ]; then
  auth="--basic-auth=${GOWA_USER}:${GOWA_PASS:-}"
else
  auth=""
fi

# GOWA writes storages/ and statics/ under its working directory.
cd /data

echo "[entrypoint] GOWA ${GOWA_VERSION:-} on ${gowa_host}:${gowa_port}"
# `auth` is either empty or a single argument: the shell splits it on purpose.
# shellcheck disable=SC2086
"$gowa_bin" rest \
  "--port=${gowa_port}" \
  "--host=${gowa_host}" \
  "--ui-enabled=${GOWA_UI:-false}" \
  $auth &

gowa_pid=$!
adapter_pid=""

shutdown() {
  echo "[entrypoint] stopping"
  [ -n "$adapter_pid" ] && kill "$adapter_pid" 2>/dev/null || true
  kill "$gowa_pid" 2>/dev/null || true
  wait 2>/dev/null || true
  exit 0
}
trap shutdown TERM INT

echo "[entrypoint] adapter on port ${BRIDGE_PORT:-8585}"
node /opt/adapter/server.js &
adapter_pid=$!

# If either one dies the other must not stay up alone: an adapter without GOWA
# answers every request with an error, and a running container that does not
# work is worse than a stopped one.
while kill -0 "$gowa_pid" 2>/dev/null && kill -0 "$adapter_pid" 2>/dev/null; do
  sleep 1
done

if ! kill -0 "$adapter_pid" 2>/dev/null; then
  echo "[entrypoint] the adapter exited: stopping GOWA"
  kill "$gowa_pid" 2>/dev/null || true
else
  echo "[entrypoint] GOWA exited: stopping the adapter"
  kill "$adapter_pid" 2>/dev/null || true
fi

wait 2>/dev/null || true
exit 1
