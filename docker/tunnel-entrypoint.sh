#!/bin/sh
# The tunnel, started so that the public address is asked for by name.
#
# Why this exists instead of running `ekzhang/bore` directly: bore.pub grants a
# requested port when it is free and refuses it when it is not, and the pinned
# image is a static binary with no shell, so it cannot do the two things the
# deployment needs - ask for the same port every time, and fall back to a random
# one instead of exiting when that port has been taken by someone else. The
# first is what keeps the endpoint in the app's repository valid across
# restarts; the second is what keeps the phone from being left with nothing.
#
# bore says its address once, when it is up:
#
#   listening at bore.pub:12345
#
# That line is the address the phone has to be given, so it is repeated at the
# end, and - when ENDPOINT_AUTO_PUBLISH is on and a GitHub token is present -
# publish-endpoint.sh puts it in the endpoint repository without anyone asking.
set -eu

LOCAL_PORT="${BRIDGE_PORT:-8585}"
SERVER="${TUNNEL_SERVER:-bore.pub}"
PREFERRED="${TUNNEL_PORT:-0}"

LOG=/tmp/bore.log

# bore is a child of this script, and this script is the container's process 1:
# without this, `docker stop` waits for the timeout and then kills everything.
pid=""
trap 'trap - TERM INT; [ -n "${pid}" ] && kill "${pid}" 2>/dev/null; exit 0' TERM INT

address_of() {
  sed -n 's/.*[Ll]istening [ao][nt] [^:]*:\([0-9][0-9]*\).*/\1/p' "${LOG}" | tail -1
}

# Starts bore, waits for its address line, and returns 0 when it is up. Returns
# 1 when bore gave up first - which is what a taken port looks like.
attempt() {
  requested="$1"
  : > "${LOG}"
  if [ -n "${requested}" ]; then
    echo "[tunnel] asking ${SERVER} for port ${requested}"
    bore local "${LOCAL_PORT}" --to "${SERVER}" --port "${requested}" 2>&1 | tee "${LOG}" &
  else
    echo "[tunnel] letting ${SERVER} choose a port"
    bore local "${LOCAL_PORT}" --to "${SERVER}" 2>&1 | tee "${LOG}" &
  fi
  # tee is the last command of the pipeline, so this is the pid to watch: it
  # ends when bore's output ends, which is when bore has stopped.
  pid=$!

  i=0
  while [ "${i}" -lt 30 ]; do
    if [ -n "$(address_of)" ]; then
      return 0
    fi
    if ! kill -0 "${pid}" 2>/dev/null; then
      return 1
    fi
    sleep 1
    i=$((i + 1))
  done
  # No address after thirty seconds and bore still running: not a failure to
  # hide, and not a reason to start a second tunnel.
  echo "[tunnel] no address from ${SERVER} after 30 s"
  return 0
}

announce() {
  echo "[tunnel] public address: ${SERVER}:${1}"
  echo "[tunnel] publish it, from the machine that has the endpoint repository:"
  echo "[tunnel]   node publish.js --host ${SERVER} --port ${1} --commit"
}

# Republishing is not allowed to hold the tunnel up: the script runs in the
# background, once per address, and its own failures are its own to report.
publish() {
  [ "${ENDPOINT_AUTO_PUBLISH:-on}" = "on" ] || return 0
  publish-endpoint.sh "${1}" &
}

while : ; do
  started=0
  if [ "${PREFERRED}" != "0" ] && attempt "${PREFERRED}"; then
    started=1
  elif attempt ""; then
    started=1
  fi

  if [ "${started}" = "0" ]; then
    echo "[tunnel] could not open a tunnel; trying again in 10 s"
    sleep 10
    continue
  fi

  address="$(address_of)"
  if [ -n "${address}" ]; then
    announce "${address}"
    publish "${address}"
  fi

  # The tunnel stays in the foreground of this loop: when it closes - a network
  # drop, the tunnel server restarting - the whole thing starts again, and it
  # asks for the same port first.
  wait "${pid}" || true
  echo "[tunnel] the tunnel closed; reopening in 5 s"
  sleep 5
done
