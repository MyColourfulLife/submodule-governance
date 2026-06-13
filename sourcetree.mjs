#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { isAbsolute, join, normalize } from 'node:path';

function usage() {
  console.log(`Usage:
  node sourcetree.mjs <repo_path> <check|accept-pointers|sync|fix|push|reinstall-hooks>`);
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd,
    encoding: 'utf8',
    stdio: options.inherit ? 'inherit' : 'pipe',
    env: process.env,
  });
  if (!options.allowFailure && result.status !== 0) {
    const detail = [result.stdout, result.stderr].filter(Boolean).join('\n').trim();
    throw new Error(`${command} ${args.join(' ')} failed${detail ? `\n${detail}` : ''}`);
  }
  return result;
}

function out(command, args, options = {}) {
  return (run(command, args, options).stdout || '').trim();
}

function absoluteFrom(root, value) {
  return isAbsolute(value) ? normalize(value) : normalize(join(root, value));
}

const [repoArg, action] = process.argv.slice(2);
if (!repoArg || !action || action === '-h' || action === '--help') {
  usage();
  process.exit(action ? 0 : 2);
}

try {
  const repoRoot = out('git', ['-C', repoArg, 'rev-parse', '--show-toplevel']);
  const gitDir = absoluteFrom(repoRoot, out('git', ['-C', repoRoot, 'rev-parse', '--git-dir']));
  const cli = join(gitDir, 'submodule-governance', 'cli', 'submodule-governance.mjs');
  if (!existsSync(cli)) {
    throw new Error(`未检测到本地治理 CLI，请先执行：node /path/to/submodule-governance-template/bootstrap.mjs "${repoRoot}"`);
  }

  const command = action === 'reinstall-hooks' ? 'install-hooks' : action;
  const allowed = new Set(['check', 'accept-pointers', 'sync', 'fix', 'push', 'install-hooks']);
  if (!allowed.has(command)) throw new Error(`Unknown command: ${action}`);

  const result = spawnSync(process.execPath, [cli, command], {
    cwd: repoRoot,
    stdio: 'inherit',
    env: process.env,
  });
  process.exit(result.status ?? 1);
} catch (error) {
  console.error(error.message || String(error));
  process.exitCode = 1;
}
