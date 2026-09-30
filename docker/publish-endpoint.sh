#!/bin/sh
# Publishes the tunnel's public address to the endpoint repository, so the phone
# keeps finding the service after the port changes.
#
# Why it lives in the tunnel container: the public address only exists there. It
# is bore.pub that chooses it, once, when the tunnel comes up, and a machine that
# has to be told the address cannot republish it by itself.
#
# The GitHub CLI does the write, authenticated by GH_TOKEN. A token with no
# write access to the repository is the same as no token at all, so a missing or
# rejected one is reported and the tunnel is left alone: the address stays
# usable, it is just not republished, and the log repeats the command that does
# it by hand.
#
# Usage (inside the container, the entrypoint calls it):
#   publish-endpoint.sh <port>
set -eu

PORT="${1:-}"
HOST="${TUNNEL_SERVER:-bore.pub}"
REPO="${ENDPOINT_REPO:-vincenzosco/whatsappforwp-endpoint}"
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

if [ -z "${PORT}" ]; then
  echo "[publish] no port given" >&2
  exit 1
fi

manual() {
  echo "[publish] publish it by hand, where the endpoint repository is cloned:"
  echo "[publish]   node publish.js --host ${HOST} --port ${PORT} --commit"
}

if [ -z "${TOKEN}" ]; then
  echo "[publish] GH_TOKEN is not set: the address ${HOST}:${PORT} is not published automatically"
  manual
  exit 0
fi

export GH_TOKEN="${TOKEN}"

# The current file, so the script can tell whether there is anything to do and
# can hand GitHub the version it is replacing. Both are needed for an update.
current="$(gh api -H 'Accept: application/vnd.github.raw' "repos/${REPO}/contents/endpoint.json" 2>/dev/null || true)"
if [ -n "${current}" ]; then
  current_host="$(printf '%s' "${current}" | sed -n 's/.*"host"[^"]*"\([^"]*\)".*/\1/p')"
  current_port="$(printf '%s' "${current}" | sed -n 's/.*"port"[^0-9]*\([0-9][0-9]*\).*/\1/p')"
  if [ "${current_host}" = "${HOST}" ] && [ "${current_port}" = "${PORT}" ]; then
    echo "[publish] ${HOST}:${PORT} is already published"
    exit 0
  fi
fi

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

json="$(printf '{\n  "updatedAt": "%s",\n  "host": "%s",\n  "port": %s,\n  "tls": false,\n  "fingerprint": ""\n}\n' "${now}" "${HOST}" "${PORT}")"
md="$(printf '# Current endpoint\n\nThe app reads `endpoint.json`; this file is for people.\n\n- Updated: %s\n- Host: %s\n- Port: %s\n- TLS: no\n- Certificate fingerprint: (none)\n\nThe address changes whenever the tunnel is restarted, so it is written by\n`publish.js` and never by hand.\n' "${now}" "${HOST}" "${PORT}")"

put() {
  file="$1"
  body="$2"
  sha="$(gh api "repos/${REPO}/contents/${file}" --jq '.sha' 2>/dev/null || true)"
  content="$(printf '%s' "${body}" | base64 | tr -d '\n')"
  if [ -n "${sha}" ]; then
    gh api --method PUT "repos/${REPO}/contents/${file}" \
      -f message="Publish the endpoint ${HOST}:${PORT}" \
      -f content="${content}" \
      -f sha="${sha}" > /dev/null
  else
    gh api --method PUT "repos/${REPO}/contents/${file}" \
      -f message="Publish the endpoint ${HOST}:${PORT}" \
      -f content="${content}" > /dev/null
  fi
  echo "[publish] updated ${file}"
}

if put endpoint.json "${json}" && put endpoint.md "${md}"; then
  echo "[publish] ${HOST}:${PORT} is live in ${REPO}"
else
  echo "[publish] could not update ${REPO} (token missing write access, or GitHub unreachable)"
  manual
fi
