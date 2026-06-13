#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const templateRoot = dirname(fileURLToPath(import.meta.url));
const cli = join(templateRoot, 'template', 'submodule-governance', 'cli', 'submodule-governance.mjs');
const args = process.argv.slice(2);

if (args.includes('-h') || args.includes('--help') || args.length === 0) {
  console.log(`Usage:
  node uninstall.mjs <target_repo_path> [--remove-config]`);
  process.exit(args.length === 0 ? 2 : 0);
}

const result = spawnSync(process.execPath, [cli, 'uninstall', ...args], {
  cwd: process.cwd(),
  stdio: 'inherit',
  env: process.env,
});

process.exit(result.status ?? 1);
