#!/usr/bin/env node

import { execFileSync, spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { pathToFileURL } from 'node:url';

const toolDir = dirname(dirname(fileURLToPath(import.meta.url)));

function repoRoot(cwd = process.cwd()) {
  return execFileSync('git', ['rev-parse', '--show-toplevel'], { cwd, encoding: 'utf8' }).trim();
}

function runScript(name, args = [], options = {}) {
  const cwd = repoRoot(options.cwd);
  return spawnSync(join(toolDir, name), args, {
    cwd,
    encoding: 'utf8',
    stdio: options.inherit ? 'inherit' : 'pipe',
    env: { ...process.env, ...(options.env || {}) },
  });
}

export function getStatus(cwd) {
  const result = runScript('submodule-state.sh', [], { cwd });
  if (result.status !== 0) {
    throw new Error(result.stderr || result.stdout || 'Unable to inspect submodules.');
  }
  const status = {
    requirePushed: false,
    configFile: '.submodule-governance.config',
    configErrors: [],
    submodules: [],
    missing: [],
    dirty: [],
    noUpstream: [],
    unpushed: [],
    stagedPointers: [],
    mismatches: [],
    branchMismatches: [],
  };
  for (const line of result.stdout.trim().split('\n')) {
    if (!line) continue;
    const [kind, ...values] = line.split('\t');
    if (kind === 'meta' && values[0] === 'requirePushed') status.requirePushed = values[1] === '1';
    if (kind === 'meta' && values[0] === 'configFile') status.configFile = values[1];
    if (kind === 'configError') status.configErrors.push(values[0]);
    if (kind === 'submodule') status.submodules.push(values[0]);
    if (kind === 'missing') status.missing.push(values[0]);
    if (kind === 'dirty') status.dirty.push(values[0]);
    if (kind === 'noUpstream') status.noUpstream.push(values[0]);
    if (kind === 'unpushed') status.unpushed.push(values[0]);
    if (kind === 'stagedPointer') status.stagedPointers.push(values[0]);
    if (kind === 'mismatch') status.mismatches.push({ path: values[0], recorded: values[1], current: values[2] });
    if (kind === 'branchMismatch') status.branchMismatches.push({ path: values[0], current: values[1], expected: values[2] });
  }
  return status;
}

export function runCaptured(command, cwd) {
  const result = runScript(command, [], { cwd });
  return {
    ok: result.status === 0,
    exitCode: result.status,
    stdout: result.stdout,
    stderr: result.stderr,
  };
}

function printHumanStatus(status) {
  console.log(`Mode: ${status.requirePushed ? 'strict' : 'non-strict'}`);
  console.log(`Submodules: ${status.submodules.length}`);
  console.log(`Pointer mismatches: ${status.mismatches.length}`);
  console.log(`Dirty submodules: ${status.dirty.length}`);
  console.log(`Branch mismatches: ${status.branchMismatches.length}`);
  if (status.mismatches.length) {
    for (const item of status.mismatches) console.log(`  ${item.path}: ${item.recorded} -> ${item.current}`);
  }
}

function usage() {
  console.log('Usage: submodule-governance <status|check|accept-pointers|sync|fix|push> [--json]');
}

function main() {
  const [command, ...args] = process.argv.slice(2);
  if (command === 'status') {
    const status = getStatus();
    if (args.includes('--json')) console.log(JSON.stringify(status, null, 2));
    else printHumanStatus(status);
    return;
  }
  const scripts = {
    check: 'submodule-check.sh',
    'accept-pointers': 'submodule-accept-pointers.sh',
    sync: 'submodule-sync.sh',
    fix: 'submodule-fix.sh',
    push: 'submodule-push.sh',
  };
  if (!scripts[command]) {
    usage();
    process.exitCode = 2;
    return;
  }
  const result = runScript(scripts[command], args, { inherit: true });
  process.exitCode = result.status ?? 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
