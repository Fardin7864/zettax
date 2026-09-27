import { spawn, execFileSync } from 'node:child_process';
import { watch } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(fileURLToPath(import.meta.url), '../../..');
const mobileRoot = resolve(repoRoot, 'apps/mobile');
const flutter = 'H:\\tools\\flutter\\bin\\flutter.bat';
const adb = 'C:\\Users\\Dell\\AppData\\Local\\Android\\Sdk\\platform-tools\\adb.exe';
const requestedDevice = process.argv[2];
const deviceLines = execFileSync(adb, ['devices'], { encoding: 'utf8' })
  .split(/\r?\n/)
  .map((line) => line.match(/^([^\s]+)\s+device$/)?.[1])
  .filter(Boolean);
if (requestedDevice && !deviceLines.includes(requestedDevice)) {
  throw new Error(`USB device ${requestedDevice} is not connected.`);
}
if (!requestedDevice && deviceLines.length !== 1) {
  throw new Error(`Connect exactly one authorized USB device or pass its serial. Found ${deviceLines.length}.`);
}
const device = requestedDevice ?? deviceLines[0];
if (!/^[\w.:-]+$/.test(device)) throw new Error('Invalid device serial.');

let child;
let ready = false;
let closing = false;
let restartRequested = false;
let pendingReload = false;
let changeTimer;
let pendingKind = 'reload';
const watchers = [];

function start() {
  ready = false;
  console.log(`\nStarting Zettax on ${device} (production API, debug hot reload)...`);
  const args = [
    'run', '-d', device, '--flavor', 'play',
    '--dart-define=ZETTAX_DISTRIBUTION=play',
    '--dart-define=PRIMEVEST_API_BASE_URL=https://api.zettax.app/api/v1',
  ];
  child = spawn('cmd.exe', ['/d', '/c', `${flutter} ${args.join(' ')}`], {
    cwd: mobileRoot, stdio: ['pipe', 'pipe', 'pipe'],
  });
  child.stdout.on('data', (chunk) => {
    process.stdout.write(chunk);
    if (!ready && /Flutter run key commands\.|A Dart VM Service/.test(chunk.toString())) {
      ready = true;
      if (pendingReload) {
        pendingReload = false;
        child.stdin.write('r\n');
      }
    }
  });
  child.stderr.on('data', (chunk) => process.stderr.write(chunk));
  child.on('error', (error) => {
    console.error(error);
    closing = true;
    cleanup();
    process.exitCode = 1;
  });
  child.on('exit', (code) => {
    ready = false;
    if (closing) return;
    if (restartRequested) {
      restartRequested = false;
      start();
    } else {
      console.error(`Flutter exited with code ${code}.`);
      cleanup();
      process.exitCode = code || 1;
    }
  });
}

function changed(kind) {
  if (closing) return;
  if (kind === 'restart') pendingKind = 'restart';
  clearTimeout(changeTimer);
  changeTimer = setTimeout(() => {
    const action = pendingKind;
    pendingKind = 'reload';
    if (action === 'restart') {
      console.log('\nAndroid or dependency change: rebuilding the debug app...');
      restartRequested = true;
      if (child && child.exitCode === null) child.stdin.write('q\n');
      return;
    }
    console.log('\nApp source changed: hot reloading on USB device...');
    if (ready) child.stdin.write('r\n');
    else pendingReload = true;
  }, 500);
}

for (const [path, kind] of [
  ['lib', 'reload'], ['assets', 'reload'], ['android/app/src', 'restart'],
]) {
  watchers.push(watch(resolve(mobileRoot, path), { recursive: true }, () => changed(kind)));
}
for (const path of [
  'pubspec.yaml', 'android/app/build.gradle.kts',
  'android/build.gradle.kts', 'android/settings.gradle.kts',
  'android/gradle.properties',
]) {
  watchers.push(watch(resolve(mobileRoot, path), () => changed('restart')));
}

function cleanup() {
  clearTimeout(changeTimer);
  for (const watcher of watchers) watcher.close();
  process.stdin.pause();
}
if (process.stdin.isTTY) process.stdin.setRawMode(true);
process.stdin.resume();
process.stdin.on('data', (input) => {
  for (const key of input.toString()) {
    if (key === 'q' || key === '\u0003') {
      closing = true;
      cleanup();
      if (child && child.exitCode === null) child.stdin.write('q\n');
    } else if ((key === 'r' || key === 'R') && ready) {
      child.stdin.write(key);
    }
  }
});
process.on('SIGINT', () => {
  closing = true;
  cleanup();
  if (child && child.exitCode === null) child.stdin.write('q\n');
});
process.on('SIGTERM', () => {
  closing = true;
  cleanup();
  if (child && child.exitCode === null) child.stdin.write('q\n');
});

start();
