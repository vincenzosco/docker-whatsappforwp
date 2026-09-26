#!/usr/bin/env node
/**
 * tools/sync.js
 *
 * Copies the adapter from a WhatsappForWP checkout into server/, and records the
 * source commit in server/SOURCE_COMMIT. The adapter's home is that repository:
 * this one only carries the copy the image needs.
 *
 *   node tools/sync.js --from ../WhatsappForWP          copy
 *   node tools/sync.js --check --from ../WhatsappForWP  verify, do not write
 *
 * --check is what CI runs against the recorded commit: if the copy drifted, the
 * build stops instead of shipping a server nobody can reproduce.
 */
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const SERVER = path.join(ROOT, 'server');
const COMMIT_FILE = path.join(SERVER, 'SOURCE_COMMIT');

// The files that make up the server. The adapter's own READMEs stay in the app
// repository: the documentation here is the deployment's.
const FILES = [
  'server.js',
  'config.js',
  'crypto-helper.js',
  'discovery.js',
  'gowa-client.js',
  'message-format.js',
  'webhook-server.js',
  'package.json'
];

function parseArgs(argv) {
  const options = { check: false, from: '' };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--check') options.check = true;
    else if (argv[i] === '--from') options.from = argv[++i] || '';
  }
  return options;
}

function sha256(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

/** The paths, relative to server/, the copy must contain. */
function wantedFiles(adapterDir) {
  const files = FILES.slice();
  const tests = path.join(adapterDir, 'test');
  for (const name of fs.readdirSync(tests).sort()) {
    if (name.endsWith('.test.js')) files.push(path.join('test', name));
  }
  return files;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (!options.from) {
    console.error('usage: node tools/sync.js [--check] --from <WhatsappForWP>');
    process.exit(1);
  }

  // Accept either the repository root or the adapter folder.
  const given = path.resolve(options.from);
  const adapterDir = fs.existsSync(path.join(given, 'server.js'))
    ? given
    : path.join(given, 'WhatsappBridge');
  if (!fs.existsSync(path.join(adapterDir, 'server.js'))) {
    console.error('no adapter found under ' + given + ' (looked for server.js)');
    process.exit(1);
  }

  const files = wantedFiles(adapterDir);
  const problems = [];
  const stale = [];

  for (const rel of files) {
    const from = path.join(adapterDir, rel);
    const to = path.join(SERVER, rel);
    if (!fs.existsSync(from)) {
      problems.push('missing in the source: ' + rel);
      continue;
    }
    const source = fs.readFileSync(from);
    if (options.check) {
      if (!fs.existsSync(to)) problems.push('not in server/: ' + rel);
      else if (sha256(source) !== sha256(fs.readFileSync(to))) problems.push('out of date: ' + rel);
    } else {
      fs.mkdirSync(path.dirname(to), { recursive: true });
      fs.writeFileSync(to, source);
    }
  }

  if (options.check) {
    // And the other direction: a file in server/ the source no longer has is
    // drift too.
    for (const rel of FILES) {
      if (!fs.existsSync(path.join(SERVER, rel))) stale.push(rel);
    }
    if (stale.length) problems.push('in server/ but not in the source list: ' + stale.join(', '));

    if (problems.length) {
      console.log(problems.join('\n'));
      console.log('\n' + problems.length + ' problem(s): run "node tools/sync.js --from <WhatsappForWP>".');
      process.exit(1);
    }
    console.log('OK: server/ matches the adapter (' + files.length + ' file(s)).');
    return;
  }

  const commit = execFileSync('git', ['-C', path.dirname(adapterDir), 'rev-parse', 'HEAD'],
    { encoding: 'utf8' }).trim();
  fs.writeFileSync(COMMIT_FILE, commit + '\n');
  console.log('copied ' + files.length + ' file(s) from ' + adapterDir);
  console.log('source commit: ' + commit);
}

main();
