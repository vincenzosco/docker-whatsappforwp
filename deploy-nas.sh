#!/bin/sh
# Deploy the shared WhatsApp-for-WP8 server on a NAS, and print the address to
# publish.
#
# Run it on the NAS, from the directory that holds docker-compose.yaml and your
# .env. It starts the container and the bore tunnel, then reads the port bore
# was given and prints the exact command to run where the endpoint repository
# is cloned.
#
# It does NOT touch any credential: the SSH password and the tokens stay where
# you keep them.
#
# Usage:
#   ./deploy-nas.sh            # start, and print the public address
#   ./deploy-nas.sh logs       # follow the bore log
#   ./deploy-nas.sh down       # stop
set -eu

COMPOSE="docker compose -f docker-compose.yaml -f docker-compose.nas.yaml"

case "${1:-up}" in
  down)
    $COMPOSE down
    exit 0
    ;;
  logs)
    docker logs -f whatsapp-bore
    exit 0
    ;;
esac

if [ ! -f .env ]; then
  cp .env.example .env
  echo "[deploy] wrote .env from .env.example - review it before the first real run"
fi

$COMPOSE up -d

# bore prints its address once, on startup: "Listening on bore.pub:12345".
# Give it a moment, then read the last one.
sleep 8
port=$(docker logs whatsapp-bore 2>&1 | sed -n 's/.*bore\.pub:\([0-9][0-9]*\).*/\1/p' | tail -1)

echo
echo "[deploy] container:   $(docker ps --filter name=whatsapp-for-wp8 --format '{{.Status}}')"
echo "[deploy] tunnel:      $(docker ps --filter name=whatsapp-bore --format '{{.Status}}')"

if [ -z "${port:-}" ]; then
  echo "[deploy] the tunnel has not printed an address yet: ./deploy-nas.sh logs"
  exit 0
fi

echo "[deploy] public:      bore.pub:${port}"
echo
echo "[deploy] now publish it, from the machine that has the endpoint repository:"
echo "         node publish.js --host bore.pub --port ${port} --commit"
echo
echo "[deploy] or run the GitHub Action 'endpoint' with host=bore.pub port=${port}"
