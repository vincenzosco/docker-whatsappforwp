[English](README.md)

# WhatsApp per Windows Phone 8.1 - server

## Cos'e' questo

Un container che esegue le due meta' del server con cui parla l'app Windows Phone
8.1:

- **GOWA** (go-whatsapp-web-multidevice), il motore che possiede la connessione
  WhatsApp;
- l'**adapter Node.js**, il cui protocollo TCP cifrato e' l'unica cosa che il
  telefono parla.

L'app del telefono **non** e' qui: sta in
[vincenzosco/WhatsappForWP](https://github.com/vincenzosco/WhatsappForWP), che e'
anche il posto in cui vive il sorgente dell'adapter. `server/` in questo repository
ne e' una copia, con annotato il commit da cui arriva, e la CI si rifiuta di
costruire se la copia si e' allontanata.

Non serve sapere niente di tutto questo per usarlo: scegli una delle due strade
qui sotto.

## Avvio rapido (Docker)

```bash
git clone https://github.com/vincenzosco/docker-whatsappforwp
cd docker-whatsappforwp
cp .env.example .env      # modificalo se serve; i valori predefiniti vanno bene
docker compose up -d
docker logs -f whatsapp-for-wp8
```

Poi, sul telefono: apri l'app. Se trova il server da sola si collega e mostra un
codice QR; se non lo trova, nella pagina delle impostazioni scrivi l'indirizzo di
questa macchina e la porta `8585` e premi connetti. Inquadra il codice con WhatsApp
(Dispositivi collegati, Collega un dispositivo) e la sessione e' collegata.

**Su un NAS Linux** (Synology, QNAP, un mini PC) usa invece il file con host
networking, cosi' l'app trova il server da sola:

```bash
docker compose -f docker-compose.host.yaml up -d
```

La sessione vive nel volume `whatsapp-data`: riavviare il container o aggiornare
l'immagine non ti fa riscansionare il codice.

## Configurazione

Tutto si legge da `.env` (l'elenco completo e' in `.env.example`):

| Variabile | Predefinito | Quando cambiarla |
| --- | --- | --- |
| `BRIDGE_PORT` | `8585` | La porta a cui si collega il telefono. Cambiala se qualcos'altro occupa la 8585. |
| `BRIDGE_KEY` | `WhatsAppCommunityWP8-2026` | Mai, a meno che tu non abbia ricompilato l'app con un'altra passphrase. E' compilata dentro l'app: se non combacia si vede un errore di decifratura. |
| `BRIDGE_ENCRYPTION` | `on` | Metti `off` solo mentre si debugga il protocollo stesso. |
| `DISCOVERY_ENABLED` | `on` | `off` se non vuoi il beacon UDP e preferisci scrivere l'indirizzo. |
| `DISCOVERY_PORT` | `8587` | Se la porta UDP e' occupata. |
| `DISCOVERY_NAME` | nome host | Per dare un'etichetta a questo server nella lista dell'app. |
| `GOWA_URL` | `http://127.0.0.1:3000` | Solo se sposti GOWA fuori dal container. |
| `GOWA_PORT` | `3000` | Se la 3000 e' occupata dentro il container. |
| `GOWA_HOST` | `127.0.0.1` | **Non** esporre GOWA sulla LAN senza impostare `GOWA_USER`/`GOWA_PASS`: quell'API puo' inviare messaggi come il tuo account. |
| `GOWA_UI` | `false` | `true` solo insieme alle credenziali e a `GOWA_HOST`, per usare la web UI di GOWA. |
| `GOWA_USER`, `GOWA_PASS` | vuote | Quando esponi l'API di GOWA. |
| `GOWA_DEVICE_ID` | vuota | Per usare un device specifico in una configurazione multi-device. |
| `WEBHOOK_PORT`, `WEBHOOK_PATH` | `8586`, `/webhook` | Se ti servono diversi. GOWA e l'adapter sono nello stesso container, quindi l'URL pubblico resta su loopback. |
| `WEBHOOK_SECRET` | vuota | Per combaciare con un `--webhook-secret` impostato su GOWA. |
| `POLL_INTERVAL_MS` | `5000` | Per interrogare lo stato WhatsApp piu' o meno spesso. |
| `CHATS_LIMIT` | `25` | Per caricare meno o piu' conversazioni nell'app. |
| `CHATS_AVATARS` | `on` | Metti `off` per saltare la richiesta per chat che scarica le immagini del profilo, gruppi compresi. |
| `MESSAGES_LIMIT` | `50` | Per caricare meno o piu' messaggi aprendo una chat. |
| `CALLS_CHAT_LIMIT`, `CALLS_MESSAGES_PER_CHAT`, `CALLS_LIMIT` | `25`, `100`, `50` | Per far leggere alla scansione delle chiamate piu' o meno chat, messaggi e voci. Costa una richiesta per chat. |
| `FFMPEG_ENABLED` | `on` | Lascialo attivo: un vocale arriva come Ogg/Opus e WP8.1 non decodifica Opus, quindi l'immagine lo converte in MP3. `off` manda i byte originali, che il telefono non sa leggere. |
| `FFMPEG_PATH` | `ffmpeg` | Solo se hai sostituito l'ffmpeg dell'immagine con una build tenuta altrove. |

L'unica variabile che si sbaglia e' `BRIDGE_KEY`: deve essere uguale alla
passphrase compilata nell'app. Se non hai mai ricompilato l'app, non toccarla.

## Quale dei due usare

**Docker per tutto cio' che resta acceso.** Un NAS o un PC sempre acceso:
un'immagine, un container, `restart: unless-stopped`, un volume con un nome per la
sessione, e nessun Node e nessun Go installato sull'host. E' il deployment
consigliato.

**Node.js liscio per una macchina di sviluppo**, o la prima volta che si collega il
telefono: niente da installare tranne Node, e il log ce l'hai davanti. Le due
strade leggono le stesse variabili, quindi si passa dall'una all'altra con
`docker compose down` e `npm start`.

## Eseguirlo con Node.js invece

Questo e' esattamente quello che fa il container, a mano:

```bash
# 1. il binario GOWA (scegli l'archivio per la tua architettura e il tuo sistema)
curl -LO https://github.com/aldinokemal/go-whatsapp-web-multidevice/releases/download/v9.5.0/whatsapp_9.5.0_linux_amd64.zip
unzip whatsapp_9.5.0_linux_amd64.zip
./whatsapp rest --port=3000 --host=127.0.0.1 --ui-enabled=false &

# 2. l'adapter (niente dipendenze da installare)
cd server
GOWA_URL=http://127.0.0.1:3000 node server.js
```

Su un host nudo installa anche `ffmpeg` dal gestore di pacchetti, altrimenti i
vocali arrivano e non si possono riprodurre. L'immagine ce l'ha gia'.

Su Linux tutto quanto sopra e' identico con `linux_arm64` su una macchina ARM a
64 bit (molti NAS) e `linux_armv7` su una a 32 bit.

Se hai anche il repository dell'app, il suo `tools/start-login.js` fa tutto questo
per te - scarica GOWA, verifica lo SHA-256, avvia i due processi e disegna il
codice QR di login nel terminale:

```bash
node tools/start-login.js
```

## Le porte

| Porta | Cosa | Raggiungibile da |
| --- | --- | --- |
| `8585/tcp` | il protocollo cifrato che parla l'app WP8.1 | la LAN |
| `8586/tcp` | il webhook che GOWA chiama per i messaggi in arrivo | il container stesso |
| `8587/udp` | il beacon di scoperta, cosi' l'app trova il server | la LAN, solo con host networking |
| `3000/tcp` | l'API REST di GOWA | loopback dentro il container |

## Aggiornare

```bash
docker compose pull
docker compose up -d
```

La sessione collegata sta nel volume `whatsapp-data` e sopravvive. Per ricominciare
da un abbinamento nuovo, rimuovila di proposito:

```bash
docker compose down -v
```

Cancella la sessione, e al prossimo avvio serve un nuovo codice QR.

## Quando il ciclo di login dice `reconnect error`

GOWA dialoga con `https://web.whatsapp.com/ws/chat` in TLS. Senza un archivio di
certificati dentro il container quella chiamata fallisce con `x509: certificate
signed by unknown authority`, il ciclo di login risponde `reconnect error` e ogni
connessione dal telefono viene chiusa appena si apre. L'immagine installa
`ca-certificates` proprio per questo; una build che l'ha perso e' la prima cosa da
controllare:

```bash
docker exec whatsapp-for-wp8 ls -l /etc/ssl/certs/ca-certificates.crt
docker logs whatsapp-for-wp8 | grep -i "certificate signed by unknown authority"
```

Da sapere: GOWA cancella la sessione di un dispositivo che non riesce a usare.
Dopo una lunga serie di questi errori la sessione WhatsApp non c'e' piu' e al
prossimo avvio serve un nuovo codice QR, che e' quello che serve la schermata QR
dell'app.

## Come viene costruita l'immagine

Due stadi. Il primo scarica l'archivio della release GOWA bloccata per
l'architettura di destinazione e ne verifica lo SHA-256 - gli stessi digest che usa
`tools/download.js` nel repository dell'app. Il secondo e' `node:bookworm-slim`
con quel binario, il sorgente dell'adapter (nessun `npm install`: non ha
dipendenze), `ffmpeg` - l'unico programma esterno dell'adapter, che trasforma un
vocale ricevuto in un MP3 - e `docker/entrypoint.sh`, che avvia i due processi,
tiene GOWA su loopback e ferma tutto se uno dei due muore.

`server/` viene riempita da `tools/sync.js` a partire da un checkout del repository
dell'app, e `server/SOURCE_COMMIT` annota da quale commit arriva:

```bash
node tools/sync.js --from ../WhatsappForWP
node tools/sync.js --check --from ../WhatsappForWP
```

Il job `sync` della CI fa il checkout di quel commit esatto del repository dell'app,
lancia `--check` e ferma la build se la copia non combacia piu'. Una build riuscita
pubblica su GHCR come `ghcr.io/vincenzosco/docker-whatsappforwp:latest` (piu'
`:sha-...` e `:app-<commit>`). Un secondo job indipendente costruisce
`Dockerfile.tunnel` e lo pubblica come
`ghcr.io/vincenzosco/docker-whatsappforwp-tunnel:latest` (vedi "Il tunnel verso
bore.pub" qui sotto).

## Cifratura a riposo

GOWA tiene la sessione WhatsApp collegata come file, e l'adapter tiene gli hash
dei token in `users.json`. Nessuno dei due sa cifrarsi da solo, quindi la
risposta onesta e' la cifratura dell'intero volume sull'host, mentre i file
restano in chiaro dentro il container:

```bash
# una volta sola
fallocate -l 4G /var/lib/whatsapp.luks
cryptsetup luksFormat /var/lib/whatsapp.luks
cryptsetup open /var/lib/whatsapp.luks whatsapp-data
mkfs.ext4 /dev/mapper/whatsapp-data
mount /dev/mapper/whatsapp-data /var/lib/whatsapp-data

# a ogni avvio, prima di docker compose up
cryptsetup open /var/lib/whatsapp.luks whatsapp-data
mount /dev/mapper/whatsapp-data /var/lib/whatsapp-data

DATA_DIR=/var/lib/whatsapp-data docker compose \
  -f docker-compose.yaml -f docker-compose.secure.yaml up -d
```

`docker-compose.secure.yaml` ha gli stessi comandi nei commenti. I token sono
gia' salvati solo come hash scrypt, quindi la cifratura del volume protegge la
sessione WhatsApp, che e' la parte che non si puo' rigenerare.

## Migrare senza riabbinare

La sessione e i token degli utenti sono cio' che rende un container *quel*
container. Spostarli su un'altra macchina e' un export e un restore: il telefono
non riscanna il codice QR.

```bash
# macchina vecchia
node tools/backup.js export whatsapp-backup.tar

# macchina nuova: stesso .env, poi
node tools/backup.js restore whatsapp-backup.tar
docker compose up -d
```

L'archivio contiene `/data/storages` (la sessione) e `/data/users.json` (gli hash
dei token). Lo costruisce il container, quindi non importa dove Docker tiene il
volume. Ferma il container prima del restore: scompattare file sotto un processo
acceso e' chiedere guai.

## Il tunnel verso bore.pub

`docker-compose.nas.yaml` aggiunge un secondo servizio che espone l'adapter su
`bore.pub`, per una macchina non raggiungibile dall'esterno. Non e' l'immagine
bloccata `ekzhang/bore` ma una nostra immagine piccola intorno allo stesso
binario: al tunnel va detto quale porta pubblica chiedere, e deve poter ripiegare
quando quella porta non c'e' piu'.

```bash
TUNNEL_PORT=41417
```

bore.pub concede la porta richiesta quando e' libera, quindi l'indirizzo nel
repository `whatsappforwp-endpoint` sopravvive a un riavvio del container o del
NAS e non c'e' niente da pubblicare. Quando nel frattempo la porta e' stata presa
da qualcun altro, il servizio ripiega su una casuale invece di uscire - al
telefono non resta mai un indirizzo che non risponde.

Il container pubblica poi quel nuovo indirizzo da solo, cosi' nessuno deve
accorgersi che e' cambiato. Metti un `GH_TOKEN` in `.env` con accesso in
scrittura al repository dell'endpoint e il tunnel scrive li' l'indirizzo da
dentro Docker, tramite la GitHub CLI che l'immagine porta con se':

```bash
GH_TOKEN=github_pat_...
docker logs whatsapp-bore | grep '\[publish\]'
```

Il token e' l'unica credenziale dello stack e resta in `.env`, che non e'
versionato. Lascialo vuoto e il tunnel funziona comunque: l'indirizzo
semplicemente non viene ripubblicato, e il log stampa il comando per farlo dove
e' clonato il repository dell'endpoint.

```bash
docker logs whatsapp-bore | grep 'public address'
node publish.js --host bore.pub --port <port> --commit
```

`TUNNEL_PORT=0` non chiede niente e prende quello che il server ha, che e' come
funzionava un tunnel casuale.

## Condividere il server

Un container puo' ospitare piu' di un account: ogni utente ha un device GOWA
suo, creato al primo handshake, e il token e' cio' che decide quale e' il suo.
Metti `AUTH_REQUIRED=on` e basta: con `AUTH_REGISTER=on` (il valore predefinito)
un telefono che si collega senza token ne riceve uno sul momento, quindi nell'app
non c'e' niente da digitare oltre all'interruttore. Un servizio che deve restare
chiuso mette `AUTH_REGISTER=off` e consegna i token a mano (`docker exec
whatsapp-for-wp8 node /opt/adapter/create-user.js <nome>`); con
`AUTH_REQUIRED` spento non cambia niente e l'istanza resta privata.

Due cose restano vere e vale la pena dirle: chi gestisce il server puo'
tecnicamente arrivare alle sessioni sulla macchina, quindi il token separa gli
utenti e non l'accesso di chi amministra; e il trasporto e' cifrato dal cifrario
dell'app con la passphrase compilata dentro, che e' cio' che protegge il
traffico su un tunnel pubblico.

## Disclosure

Questo e' un client non ufficiale. Non e' affiliato, approvato o collegato a
WhatsApp o Meta. E' open source, i maintainer sono benvenuti, ed e' stato scritto
con l'aiuto di un agente AI. Usa un account che sei disposto a perdere: nessuno qui
si prende la responsabilita' dell'account con cui lo usi.
