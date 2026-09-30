'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { parseArgs, dockerArgs } = require('./backup');

test('parseArgs prende il comando e l archivio', () => {
  const opts = parseArgs(['export', 'backup.tar']);
  assert.strictEqual(opts.command, 'export');
  assert.strictEqual(opts.archive, 'backup.tar');
  assert.deepStrictEqual(opts.files, ['docker-compose.yaml']);
});

test('parseArgs accetta un override compose, nell ordine dato', () => {
  const opts = parseArgs(['restore', 'b.tar', '--file', 'docker-compose.yaml', '--file', 'docker-compose.nas.yaml']);
  assert.deepStrictEqual(opts.files, ['docker-compose.yaml', 'docker-compose.nas.yaml']);
});

test('parseArgs rifiuta un comando sconosciuto o un archivio mancante', () => {
  assert.throws(() => parseArgs(['send', 'x.tar']), /unknown command/);
  assert.throws(() => parseArgs(['export']), /missing the archive/);
  assert.throws(() => parseArgs(['export', 'x.tar', '--file']), /--file wants/);
});

test('dockerArgs costruisce il tar del container per l export', () => {
  const { command, args } = dockerArgs('export', ['docker-compose.yaml']);
  assert.strictEqual(command, 'docker');
  assert.deepStrictEqual(args, [
    'compose', '-f', 'docker-compose.yaml', 'exec', '-T', 'server',
    'tar', '-C', '/data', '--ignore-failed-read', '-cf', '-', 'storages', 'users.json'
  ]);
});

test('dockerArgs estrae per il restore, senza la lettura tollerante', () => {
  const { args } = dockerArgs('restore', ['docker-compose.yaml']);
  assert.deepStrictEqual(args.slice(-5), ['tar', '-C', '/data', '-xf', '-']);
});

test('l archivio copre la sessione e gli utenti, nient altro', () => {
  const { args } = dockerArgs('export', ['docker-compose.yaml']);
  assert.ok(args.includes('storages'), 'senza storages non c e sessione da riusare');
  assert.ok(args.includes('users.json'), 'senza users.json i token non si ritrovano');
});
