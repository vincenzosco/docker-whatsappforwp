# syntax=docker/dockerfile:1
#
# One image, two processes: GOWA (the WhatsApp engine) and the Node adapter (the
# only thing the phone talks to). The GOWA version and its digest are the same
# ones tools/download.js uses in the WhatsappForWP repository: an archive that
# does not match is refused, not "used with a warning".

ARG GOWA_VERSION=9.5.0
ARG NODE_VERSION=22

# ── stage 1: the GOWA binary ────────────────────────────────────────────────
FROM debian:bookworm-slim AS gowa
ARG GOWA_VERSION
ARG TARGETARCH
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /gowa
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) file="whatsapp_${GOWA_VERSION}_linux_amd64.zip"; \
             sum="850a109a5127339adafeca3bd55be0bf5be5a5a3a0e7e2ffdd223536d312138c" ;; \
      arm64) file="whatsapp_${GOWA_VERSION}_linux_arm64.zip"; \
             sum="3f8530e742d6af749a0249a1e93aa3d80fdc5e132426c67fc3bdeac3c3644379" ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o gowa.zip \
      "https://github.com/aldinokemal/go-whatsapp-web-multidevice/releases/download/v${GOWA_VERSION}/${file}"; \
    echo "${sum}  gowa.zip" | sha256sum -c -; \
    unzip -q gowa.zip -d extracted; \
    ls -l extracted; \
    binary="$(find extracted -type f -printf '%s %p\n' | sort -rn | head -n1 | cut -d' ' -f2-)"; \
    echo "GOWA binary: ${binary}"; \
    mv "${binary}" whatsapp; \
    chmod +x whatsapp; \
    ./whatsapp --version || true

# ── stage 2: the runtime ────────────────────────────────────────────────────
FROM node:${NODE_VERSION}-bookworm-slim AS runtime
ARG GOWA_VERSION
LABEL org.opencontainers.image.title="whatsapp-for-wp8-server" \
      org.opencontainers.image.description="GOWA plus the WP8.1 adapter, in one container" \
      org.opencontainers.image.source="https://github.com/vincenzosco/docker-whatsappforwp" \
      org.opencontainers.image.licenses="MIT"

# GOWA writes storages/ and statics/ under its working directory: /data is the
# volume that keeps the linked WhatsApp session across restarts.
WORKDIR /data

# The adapter's only external program. A received voice note is Ogg with the
# Opus codec and WP8.1 has no Opus decoder (Opus arrived with Windows 10), so
# the adapter converts it to a small mono MP3 before sending it to the app.
# Without ffmpeg the voice note still arrives but cannot play; the image ships
# it so that it does, with no step on the host.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg \
 && rm -rf /var/lib/apt/lists/*

COPY --from=gowa /gowa/whatsapp /usr/local/bin/whatsapp
# The adapter has no dependencies: its source is copied, nothing is installed.
COPY server/ /opt/adapter/
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV NODE_ENV=production \
    GOWA_VERSION=${GOWA_VERSION} \
    GOWA_BIN=/usr/local/bin/whatsapp \
    GOWA_HOST=127.0.0.1 \
    GOWA_PORT=3000 \
    GOWA_UI=false \
    GOWA_URL=http://127.0.0.1:3000 \
    BRIDGE_PORT=8585 \
    WEBHOOK_PORT=8586 \
    WEBHOOK_PATH=/webhook \
    WEBHOOK_PUBLIC_URL=http://127.0.0.1:8586/webhook \
    DISCOVERY_PORT=8587 \
    DISCOVERY_ENABLED=on \
    POLL_INTERVAL_MS=5000

EXPOSE 8585/tcp 8586/tcp 8587/udp
VOLUME ["/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "const s=require('net').connect(Number(process.env.BRIDGE_PORT||8585),'127.0.0.1',()=>{s.end();process.exit(0)});s.on('error',()=>process.exit(1))"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
