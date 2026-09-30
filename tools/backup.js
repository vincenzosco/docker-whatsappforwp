#!/usr/bin/env node
'use strict';

/**
 * tools/backup.js
 *
 * Export and restore the two things that make a container *that* container:
 *
 *   - /data/storages  the linked WhatsApp session: the keys and the device
 *                     registration. Restoring these is what lets a phone move to
 *                     another machine without scanning the QR code again.
 *   - /data/users.json the tokens of the shared service, hashed.
 *
 * Both live inside the container volume, so the archive is built by the
 * container itself (`docker compose exec ... tar`) and piped out, and put back
 * the same way. Nothing on the host needs to know where Docker keeps the volume.
 *
 * Usage:
 *   node tools/backup.js export backup.tar
 *   node tools/backup.js restore backup.tar
 *   node tools/backup.js export backup.tar --file docker-compose.yaml --file docker-compose.nas.yaml
 *
 * The gate does not run by itself: restore over a running container copies files
 * under a live process. Stop it first (`docker compose stop server`), restore,
 * then start it again.
 */

const fs = require('fs');
const { spawnSync } = require('child_process');

const SERVICE = 'server';
const DATA_DIR = '/data';
const ITEMS = ['storages', 'users.json'];
const DEFAULT_COMPOSE = ['docker-compose.yaml'];

function usage() {
  return [
    'Usage:',
    '  node tools/backup.js export <archive.tar> [--file <compose.yaml>]...',
    '  node tools/backup.js restore <archive.tar> [--file <compose.yaml>]...',
    '',
    'export   copies /data/storages and /data/users.json out of the container',
    'restore  puts them back into a container that mounts the same /data'
  ].join('\n');
}

/**
 * Gli argomenti della riga di comando, in una forma sola.
 *
 * Il file compose predefinito e' quello di base: un NAS che aggiunge un
 * override lo dichiara con un secondo `--file`, e l'ordine e' quello che deve
 * avere (Docker applica gli override da sinistra a destra).
 */
function parseArgs(argv) {
  const args = Array.isArray(argv) ? argv.slice() : [];
  const command = args.shift();
  if (command !== 'export' && command !== 'restore') {
    throw new Error('unknown command: ' + (command || '(none)') + '\n' + usage());
  }

  let archive = '';
  const files = [];
  while (args.length) {
    const token = args.shift();
    if (token === '--file') {
      const value = args.shift();
      if (!value) throw new Error('--file wants a compose file');
      files.push(value);
    } else if (!archive) {
      archive = token;
    } else {
      throw new Error('unexpected argument: ' + token);
    }
  }

  if (!archive) throw new Error('missing the archive path\n' + usage());
  return { command, archive, files: files.length ? files : DEFAULT_COMPOSE.slice() };
}

/**
 * Il comando Docker completo, senza eseguirlo: e' quello che rende la scelta
 * verificabile senza un demone Docker acceso.
 *
 * `--ignore-failed-read` perche' users.json puo' non esserci (istanza privata):
 * l'archivio della sessione deve uscire lo stesso, con un avviso invece di un
 * errore.
 */
function dockerArgs(mode, files) {
  const compose = [];
  for (const file of files) compose.push('-f', file);

  const tar = mode === 'export'
    ? ['tar', '-C', DATA_DIR, '--ignore-failed-read', '-cf', '-', ...ITEMS]
    : ['tar', '-C', DATA_DIR, '-xf', '-'];

  return { command: 'docker', args: ['compose', ...compose, 'exec', '-T', SERVICE, ...tar] };
}

function run(mode, archive, files) {
  const { command, args } = dockerArgs(mode, files);
  console.log(`[backup] ${mode}: docker ${args.join(' ')}`);

  const output = fs.openSync(archive, mode === 'export' ? 'w' : 'r');
  let result;
  try {
    result = spawnSync(command, args, {
      stdio: mode === 'export' ? ['ignore', output, 'inherit'] : [output, 'inherit', 'inherit']
    });
  } finally {
    fs.closeSync(output);
  }

  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error('docker compose exited with ' + result.status + (mode === 'export' ? '' : ' (is the archive valid?)'));
  }
  if (mode === 'export') {
    const size = fs.statSync(archive).size;
    if (size === 0) throw new Error('the archive is empty: is the container running?');
    console.log(`[backup] wrote ${archive} (${size} bytes)`);
    console.log('[backup] restore it on the new machine, then start the container: the link is kept.');
  } else {
    console.log(`[backup] restored ${archive} into ${SERVICE}`);
    console.log('[backup] start the container: the WhatsApp session does not ask for the QR code again.');
  }
}

function main(argv) {
  const opts = parseArgs(argv);
  run(opts.command, opts.archive, opts.files);
}

if (require.main === module) {
  try {
    main(process.argv.slice(2));
  } catch (err) {
    console.error('[backup] ' + err.message);
    process.exit(1);
  }
}

module.exports = { parseArgs, dockerArgs, usage, SERVICE, DATA_DIR, ITEMS, DEFAULT_COMPOSE };
