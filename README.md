[Italiano](README.it.md)

# WhatsApp for Windows Phone 8.1 - server

## What this is

One container running the two halves of the server that the Windows Phone 8.1 app
talks to:

- **GOWA** (go-whatsapp-web-multidevice), the engine that owns the WhatsApp
  connection;
- the **Node.js adapter**, whose encrypted TCP protocol is the only thing the
  phone speaks.

The phone app itself is **not** here: it lives in
[vincenzosco/WhatsappForWP](https://github.com/vincenzosco/WhatsappForWP), which
is also where the adapter's source of truth is. `server/` in this repository is a
copy of it, recorded with the commit it came from, and CI refuses to build if the
copy has drifted.

You do not need to know any of that to use it: pick one of the two ways below.

## Quick start (Docker)

```bash
git clone https://github.com/vincenzosco/docker-whatsappforwp
cd docker-whatsappforwp
cp .env.example .env      # edit it if you need to; the defaults work
docker compose up -d
docker logs -f whatsapp-for-wp8
```

Then, on the phone: open the app. If it finds the server by itself it connects and
shows a QR code; if it does not, type the address of this machine and port `8585`
in the settings page and press connect. Scan the QR code with WhatsApp (Linked
devices, Link a device) and the session is linked.

**On a Linux NAS** (Synology, QNAP, a mini PC) use the host-networking file
instead, so that the app can find the server by itself:

```bash
docker compose -f docker-compose.host.yaml up -d
```

The session lives in the `whatsapp-data` volume: restarting the container or
updating the image does not ask you to scan again.

## Configuration

Everything is read from `.env` (see `.env.example` for the full list):

| Variable | Default | When to change it |
| --- | --- | --- |
| `BRIDGE_PORT` | `8585` | The port the phone connects to. Change it if something else holds 8585. |
| `BRIDGE_KEY` | `WhatsAppCommunityWP8-2026` | Never, unless you rebuilt the app with a different passphrase. It is compiled into the app; a mismatch shows as a decryption error. |
| `BRIDGE_ENCRYPTION` | `on` | Only set `off` while debugging the protocol itself. |
| `DISCOVERY_ENABLED` | `on` | Set `off` if you do not want the UDP beacon and prefer typing the address. |
| `DISCOVERY_PORT` | `8587` | If the UDP port is taken. |
| `DISCOVERY_NAME` | host name | To label this server in the app's list. |
| `GOWA_URL` | `http://127.0.0.1:3000` | Only if you move GOWA out of the container. |
| `GOWA_PORT` | `3000` | If 3000 is taken inside the container. |
| `GOWA_HOST` | `127.0.0.1` | Do **not** bind GOWA to the LAN without setting `GOWA_USER`/`GOWA_PASS`: that API can send messages as your account. |
| `GOWA_UI` | `false` | `true` only together with credentials and `GOWA_HOST`, to use GOWA's own web UI. |
| `GOWA_USER`, `GOWA_PASS` | empty | When you expose GOWA's API. |
| `GOWA_DEVICE_ID` | empty | To use a specific device in a multi-device setup. |
| `WEBHOOK_PORT`, `WEBHOOK_PATH` | `8586`, `/webhook` | If you need different ones. Both GOWA and the adapter are in this container, so the public URL stays on loopback. |
| `WEBHOOK_SECRET` | empty | To match a `--webhook-secret` set on GOWA. |
| `POLL_INTERVAL_MS` | `5000` | To poll WhatsApp's status more or less often. |
| `CHATS_LIMIT` | `25` | To load fewer or more conversations in the app. |
| `CHATS_AVATARS` | `on` | Set `off` to skip the one request per chat that downloads profile pictures, groups included. |
| `MESSAGES_LIMIT` | `50` | To load fewer or more messages when opening a chat. |
| `CALLS_CHAT_LIMIT`, `CALLS_MESSAGES_PER_CHAT`, `CALLS_LIMIT` | `25`, `100`, `50` | To make the call-history scan read more or fewer chats, messages and records. It costs one request per chat. |
| `FFMPEG_ENABLED` | `on` | Keep it on: a voice note arrives as Ogg/Opus and WP8.1 cannot decode Opus, so the image converts it to MP3. `off` sends the original bytes, which the phone cannot play. |
| `FFMPEG_PATH` | `ffmpeg` | Only if you replaced the ffmpeg in the image with a build kept elsewhere. |

The one variable people get wrong is `BRIDGE_KEY`: it must equal the passphrase
compiled into the app. If you never rebuilt the app, do not touch it.

## Which one should you use

**Docker for anything that stays on.** A NAS or an always-on PC: one image, one
container, `restart: unless-stopped`, a named volume for the session, and no Node
and no Go installed on the host. That is the recommended deployment.

**Plain Node.js for a development machine**, or the first time you pair the
phone: nothing to install but Node, and the log is right in front of you. Both
paths read the same variables, so switching is `docker compose down` plus
`npm start`.

## Run it with Node.js instead

This is exactly what the container does, by hand:

```bash
# 1. the GOWA binary (pick the archive for your architecture and system)
curl -LO https://github.com/aldinokemal/go-whatsapp-web-multidevice/releases/download/v9.5.0/whatsapp_9.5.0_linux_amd64.zip
unzip whatsapp_9.5.0_linux_amd64.zip
./whatsapp rest --port=3000 --host=127.0.0.1 --ui-enabled=false &

# 2. the adapter (no dependencies to install)
cd server
GOWA_URL=http://127.0.0.1:3000 node server.js
```

On a bare host, install `ffmpeg` from your package manager as well, or voice
notes arrive and cannot play. The image already has it.

On Linux everything above is the same with `linux_arm64` on a 64-bit ARM box
(many NAS boxes) and `linux_armv7` on a 32-bit one.

If you also have the app repository checked out, its
`tools/start-login.js` does all of this for you - it downloads GOWA, verifies the
SHA-256, starts both processes and draws the login QR code in the terminal:

```bash
node tools/start-login.js
```

## The ports

| Port | What | Reachable from |
| --- | --- | --- |
| `8585/tcp` | the encrypted protocol the WP8.1 app speaks | the LAN |
| `8586/tcp` | the webhook GOWA calls for incoming messages | the container itself |
| `8587/udp` | the discovery beacon, so the app finds the server | the LAN, only with host networking |
| `3000/tcp` | GOWA's own REST API | loopback inside the container |

## Updating

```bash
docker compose pull
docker compose up -d
```

The linked session is in the `whatsapp-data` volume and survives. To start over
from a fresh pairing, remove it deliberately:

```bash
docker compose down -v
```

That deletes the session, and the next start asks for a new QR code.

## How the image is built

Two stages. The first downloads the pinned GOWA release archive for the target
architecture and verifies its SHA-256 - the same digests `tools/download.js` in
the app repository uses. The second is `node:bookworm-slim` with that binary, the
adapter's source (no `npm install`: it has no dependencies), `ffmpeg` - the
adapter's only external program, which turns a received voice note into an MP3 -
and `docker/entrypoint.sh`, which starts both processes, keeps GOWA on loopback
and stops everything if either one dies.

`server/` is filled by `tools/sync.js` from a checkout of the app repository, and
`server/SOURCE_COMMIT` records which commit it came from:

```bash
node tools/sync.js --from ../WhatsappForWP
node tools/sync.js --check --from ../WhatsappForWP
```

The `sync` job of the CI workflow checks out that exact commit of the app
repository, runs `--check`, and fails the build if the copy no longer matches.
A successful build publishes to GHCR as
`ghcr.io/vincenzosco/docker-whatsappforwp:latest` (plus `:sha-...` and
`:app-<commit>`).

## Encryption at rest

GOWA keeps the linked WhatsApp session as files, and the adapter keeps the
token hashes in `users.json`. Neither can encrypt itself, so the honest answer
is a full-volume encryption on the host, and the files stay plain inside the
container:

```bash
# one time
fallocate -l 4G /var/lib/whatsapp.luks
cryptsetup luksFormat /var/lib/whatsapp.luks
cryptsetup open /var/lib/whatsapp.luks whatsapp-data
mkfs.ext4 /dev/mapper/whatsapp-data
mount /dev/mapper/whatsapp-data /var/lib/whatsapp-data

# every boot, before docker compose up
cryptsetup open /var/lib/whatsapp.luks whatsapp-data
mount /dev/mapper/whatsapp-data /var/lib/whatsapp-data

DATA_DIR=/var/lib/whatsapp-data docker compose \
  -f docker-compose.yaml -f docker-compose.secure.yaml up -d
```

`docker-compose.secure.yaml` is commented with the same commands. The tokens
are already stored only as scrypt hashes, so the volume encryption protects the
WhatsApp session itself, which is the part that cannot be re-derived.

## Migration without pairing again

The session and the user tokens are what make a container *that* container.
Moving them to another machine is one export and one restore; the phone does
not scan the QR code again:

```bash
# old machine
node tools/backup.js export whatsapp-backup.tar

# new machine: same .env, then
node tools/backup.js restore whatsapp-backup.tar
docker compose up -d
```

The archive holds `/data/storages` (the session) and `/data/users.json` (the
token hashes). It is built by the container, so it does not matter where Docker
keeps the volume. Stop the container before a restore: unpacking files under a
live process is asking for trouble.

## Sharing the server

One container can host more than one account: every user gets a GOWA device of
their own, created on the first handshake, and the token is what decides which
one is theirs. Set `AUTH_REQUIRED=on` and give each phone its token
(`docker exec whatsapp-for-wp8 node /opt/adapter/create-user.js <name>`); with
the switch off, nothing changes and the instance stays private.

Two things stay true and are worth saying: the operator can technically reach
the sessions on the machine, so the token separates users, not the operator's
access; and the transport is encrypted by the app-level cipher with the
passphrase compiled into the app, which is what protects the traffic on a
public tunnel.

## Disclosure

This is an unofficial client. It is not affiliated with, endorsed by or connected
to WhatsApp or Meta. It is open source, maintainers are welcome, and it was
written with the help of an AI agent. Use an account you are willing to lose:
nobody here takes responsibility for the account you use it with.
