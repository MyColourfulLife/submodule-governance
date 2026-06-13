#!/usr/bin/env node

import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const testDir = dirname(fileURLToPath(import.meta.url));
const templateRoot = resolve(testDir, '..');
const bootstrap = join(templateRoot, 'bootstrap.mjs');
const sourcetree = join(templateRoot, 'sourcetree.mjs');
const uninstall = join(templateRoot, 'uninstall.mjs');
const tmpRoot = mkdtempSync(join('/tmp/', 'submodule-governance-it-'));
const keepTmp = process.env.KEEP_SUBMODULE_GOVERNANCE_TEST_TMP === '1';

const results = [];

function logStep(name) {
  process.stdout.write(`\n== ${name}\n`);
}

function run(command, args = [], options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd,
    encoding: 'utf8',
    env: {
      ...process.env,
      GIT_ALLOW_PROTOCOL: 'file',
      GIT_TERMINAL_PROMPT: '0',
      NO_COLOR: '1',
      ...(options.env || {}),
    },
  });
  if (options.allowFailure) return result;
  if (result.status !== 0) {
    throw new Error(
      [
        `Command failed: ${command} ${args.join(' ')}`,
        `cwd: ${options.cwd || process.cwd()}`,
        `exit: ${result.status}`,
        result.stdout,
        result.stderr,
      ].join('\n'),
    );
  }
  return result;
}

function out(command, args = [], options = {}) {
  return run(command, args, options).stdout.trim();
}

function git(args, cwd, options = {}) {
  return run('git', args, { cwd, ...options });
}

function gitOut(args, cwd, options = {}) {
  return out('git', args, { cwd, ...options });
}

function write(file, content) {
  writeFileSync(file, content);
}

function append(file, content) {
  writeFileSync(file, content, { flag: 'a' });
}

function initRepo(path, branch = 'main') {
  mkdirSync(path, { recursive: true });
  git(['init', '-b', branch], path);
  git(['config', 'user.email', 'test@example.com'], path);
  git(['config', 'user.name', 'Submodule Governance Test'], path);
}

function commitAll(cwd, message) {
  git(['add', '.'], cwd);
  git(['commit', '-m', message], cwd);
}

function createFixture({ strict = false, husky = false } = {}) {
  const id = `${strict ? 'strict' : 'loose'}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const root = join(tmpRoot, id);
  const remotes = join(root, 'remotes');
  const work = join(root, 'work');
  const subSeed = join(work, 'sub-seed');
  const main = join(work, 'main');
  const subRemote = join(remotes, 'libs.git');
  const mainRemote = join(remotes, 'main.git');

  mkdirSync(remotes, { recursive: true });
  git(['init', '--bare', subRemote], root);
  git(['init', '--bare', mainRemote], root);

  initRepo(subSeed);
  write(join(subSeed, 'README.md'), 'libs v1\n');
  commitAll(subSeed, 'init libs');
  git(['remote', 'add', 'origin', subRemote], subSeed);
  git(['push', '-u', 'origin', 'main'], subSeed);

  initRepo(main);
  git(['remote', 'add', 'origin', mainRemote], main);
  git(['-c', 'protocol.file.allow=always', 'submodule', 'add', subRemote, 'libs'], main);
  commitAll(main, 'init main');
  git(['push', '-u', 'origin', 'main'], main);
  git(['-C', join(main, 'libs'), 'branch', '--set-upstream-to=origin/main', 'main'], root);

  if (husky) {
    mkdirSync(join(main, '.husky', '_'), { recursive: true });
    git(['config', 'core.hooksPath', '.husky/_'], main);
  }

  run('node', [bootstrap, main, ...(strict ? ['--strict'] : [])], { cwd: templateRoot });

  git(['config', '--file', '.submodule-governance.config', 'governance.mainBranch', 'main'], main);
  git(['config', '--file', '.submodule-governance.config', 'submodule.libs.branch', 'main'], main);

  return { root, remotes, work, subSeed, main, subRemote, mainRemote };
}

function tool(main, relative) {
  return join(main, '.git', 'submodule-governance', relative);
}

function launcher(main, relative) {
  return join(main, '.submodule-governance', relative);
}

function check(main, options = {}) {
  return cli(main, ['check'], options);
}

function checkLauncher(main, options = {}) {
  return cliLauncher(main, ['check'], options);
}

function state(main) {
  const text = cli(main, ['state']);
  if (text.status !== 0) throw new Error(text.stdout + text.stderr);
  const rowsText = text.stdout.trim();
  const rows = rowsText
    .split('\n')
    .filter(Boolean)
    .map((line) => line.split('\t'));
  return rows;
}

function cli(main, args, options = {}) {
  return run('node', [tool(main, 'cli/submodule-governance.mjs'), ...args], {
    cwd: main,
    allowFailure: true,
    ...options,
  });
}

function cliLauncher(main, args, options = {}) {
  return run('node', [launcher(main, 'cli/submodule-governance.mjs'), ...args], {
    cwd: main,
    allowFailure: true,
    ...options,
  });
}

function mcpViaStdin(main, calls) {
  const input = calls.map((call) => JSON.stringify(call)).join('\n') + '\n';
  const result = spawnSync('node', [tool(main, 'cli/submodule-governance-mcp.mjs')], {
    cwd: main,
    input,
    encoding: 'utf8',
    env: { ...process.env, GIT_ALLOW_PROTOCOL: 'file', NO_COLOR: '1' },
  });
  if (result.status !== 0) {
    throw new Error(`MCP failed\n${result.stdout}\n${result.stderr}`);
  }
  return result.stdout
    .trim()
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

function mcpViaLauncher(main, calls) {
  const input = calls.map((call) => JSON.stringify(call)).join('\n') + '\n';
  const result = spawnSync('node', [launcher(main, 'cli/submodule-governance-mcp.mjs')], {
    cwd: main,
    input,
    encoding: 'utf8',
    env: { ...process.env, GIT_ALLOW_PROTOCOL: 'file', NO_COLOR: '1' },
  });
  if (result.status !== 0) {
    throw new Error(`MCP launcher failed\n${result.stdout}\n${result.stderr}`);
  }
  return result.stdout
    .trim()
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

function makeSubmoduleCommit(main, { push = false } = {}) {
  const libs = join(main, 'libs');
  append(join(libs, 'README.md'), `change ${Date.now()}\n`);
  git(['add', 'README.md'], libs);
  git(['commit', '-m', 'change libs'], libs);
  if (push) git(['push'], libs);
  return gitOut(['rev-parse', 'HEAD'], libs);
}

function expectExit(name, result, code, contains = '') {
  try {
    assert.equal(result.status, code, `${name} exit code`);
    if (contains) assert.match(result.stdout + result.stderr, new RegExp(contains), `${name} output`);
    results.push({ name, ok: true });
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    results.push({ name, ok: false, error });
    throw error;
  }
}

function expectStateIncludes(name, rows, kind, path) {
  try {
    assert.ok(rows.some((row) => row[0] === kind && row[1] === path), `${name}: missing ${kind} ${path}`);
    results.push({ name, ok: true });
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    results.push({ name, ok: false, error });
    throw error;
  }
}

async function main() {
  try {
    logStep('bootstrap and hook installation');
    {
      const fixture = createFixture();
      assert.equal(gitOut(['config', '--file', '.submodule-governance.config', '--type=bool', '--get', 'governance.requirePushed'], fixture.main), 'false');
      assert.ok(existsSync(tool(fixture.main, 'cli/submodule-governance.mjs')));
      assert.ok(existsSync(launcher(fixture.main, 'cli/submodule-governance.mjs')));
      assert.ok(existsSync(join(fixture.main, '.git', 'hooks', 'pre-push')));
      assert.doesNotMatch(gitOut(['status', '--short', '--untracked-files=all'], fixture.main), /\.submodule-governance\//);
      expectExit('non-strict clean check passes', check(fixture.main), 0, '非严格模式');
      expectExit('workspace launcher check passes', checkLauncher(fixture.main), 0, '非严格模式');
    }
    {
      const fixture = createFixture({ strict: true, husky: true });
      assert.equal(gitOut(['config', '--file', '.submodule-governance.config', '--type=bool', '--get', 'governance.requirePushed'], fixture.main), 'true');
      assert.ok(existsSync(join(fixture.main, '.husky', 'pre-push')));
      expectExit('strict clean check passes', check(fixture.main), 0, '严格模式');
    }
    {
      const fixture = createFixture();
      run('node', [bootstrap, fixture.main, '--strict'], { cwd: templateRoot });
      assert.equal(gitOut(['config', '--file', '.submodule-governance.config', '--type=bool', '--get', 'governance.requirePushed'], fixture.main), 'true');
      run('node', [bootstrap, fixture.main], { cwd: templateRoot });
      assert.equal(gitOut(['config', '--file', '.submodule-governance.config', '--type=bool', '--get', 'governance.requirePushed'], fixture.main), 'false');
      results.push({ name: 'bootstrap reinstall toggles strict mode', ok: true });
      process.stdout.write('ok - bootstrap reinstall toggles strict mode\n');
    }
    {
      const fixture = createFixture();
      const linked = join(fixture.work, 'linked-worktree');
      git(['worktree', 'add', '-b', 'feature/worktree', linked, 'main'], fixture.main);
      git(['-c', 'protocol.file.allow=always', 'submodule', 'update', '--init', '--recursive'], linked);
      git(['checkout', '-B', 'main', 'origin/main'], join(linked, 'libs'));
      run('node', [bootstrap, linked], { cwd: templateRoot });
      assert.equal(gitOut(['rev-parse', '--is-inside-work-tree'], linked), 'true');
      assert.equal(existsSync(join(linked, '.git', 'submodule-governance')), false);
      assert.ok(existsSync(launcher(linked, 'cli/submodule-governance.mjs')));
      assert.doesNotMatch(gitOut(['status', '--short', '--untracked-files=all'], linked), /\.submodule-governance\//);
      expectExit('worktree workspace launcher check passes', checkLauncher(linked), 0, '非严格模式');
      expectExit('worktree workspace launcher CLI works', cliLauncher(linked, ['status']), 0, 'Mode: non-strict');
      const responses = mcpViaLauncher(linked, [
        { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'get_submodule_status', arguments: {} } },
      ]);
      assert.equal(JSON.parse(responses[0].result.content[0].text).requirePushed, false);
      results.push({ name: 'worktree workspace launcher MCP works', ok: true });
      process.stdout.write('ok - worktree workspace launcher MCP works\n');
    }

    logStep('strict vs non-strict matrix');
    {
      const fixture = createFixture();
      append(join(fixture.main, 'libs', 'README.md'), 'dirty\n');
      expectStateIncludes('state reports dirty submodule', state(fixture.main), 'dirty', 'libs');
      expectExit('non-strict dirty warns but passes', check(fixture.main), 0, '存在未提交改动');
      assert.match(check(fixture.main).stdout + check(fixture.main).stderr, /非严格模式，本次检查不会强制阻止 git push/);
      assert.match(check(fixture.main).stdout + check(fixture.main).stderr, /node \.submodule-governance\/cli\/submodule-governance\.mjs fix/);
    }
    {
      const fixture = createFixture({ strict: true });
      append(join(fixture.main, 'libs', 'README.md'), 'dirty\n');
      expectExit('strict dirty blocks', check(fixture.main), 1, '存在未提交改动');
    }
    {
      const fixture = createFixture({ strict: true });
      rmSync(join(fixture.main, 'libs'), { recursive: true, force: true });
      expectExit('strict missing submodule blocks', check(fixture.main), 1, '目录缺失或未初始化');
    }
    {
      const fixture = createFixture({ strict: true });
      git(['branch', '--unset-upstream'], join(fixture.main, 'libs'));
      expectStateIncludes('state reports no upstream', state(fixture.main), 'noUpstream', 'libs');
      expectExit('strict no-upstream blocks', check(fixture.main), 1, '未配置 upstream');
    }
    {
      const fixture = createFixture({ strict: true });
      makeSubmoduleCommit(fixture.main, { push: false });
      expectStateIncludes('state reports pointer mismatch', state(fixture.main), 'mismatch', 'libs');
      expectStateIncludes('state reports unpushed submodule', state(fixture.main), 'unpushed', 'libs');
      expectExit('strict unpushed and mismatch block', check(fixture.main), 1, '尚未推送到 upstream');
    }
    {
      const fixture = createFixture({ strict: true });
      makeSubmoduleCommit(fixture.main, { push: true });
      git(['add', 'libs'], fixture.main);
      expectStateIncludes('state reports staged pointer', state(fixture.main), 'stagedPointer', 'libs');
      expectExit('strict staged pointer blocks', check(fixture.main), 1, '已暂存但尚未提交');
    }
    {
      const fixture = createFixture({ strict: true });
      git(['checkout', '-b', 'feature/main'], fixture.main);
      expectStateIncludes('state reports main branch mismatch', state(fixture.main), 'branchMismatch', '<main>');
      expectExit('strict main branch mismatch blocks', check(fixture.main), 1, '分支');
    }
    {
      const fixture = createFixture({ strict: true });
      git(['checkout', '-b', 'feature/libs'], join(fixture.main, 'libs'));
      expectStateIncludes('state reports submodule branch mismatch', state(fixture.main), 'branchMismatch', 'libs');
      expectExit('strict submodule branch mismatch blocks', check(fixture.main), 1, '分支');
    }
    {
      const fixture = createFixture({ strict: true });
      write(join(fixture.main, '.submodule-governance.config'), '[governance\nrequirePushed = true\n');
      expectStateIncludes('state reports invalid config', state(fixture.main), 'configError', '.submodule-governance.config 不是有效的 Git config 文件。');
      expectExit('invalid config falls back to non-strict check', check(fixture.main), 0, '无法可靠读取治理配置');
    }

    logStep('CLI, SourceTree, hook access');
    {
      const fixture = createFixture();
      expectExit('CLI status works', cli(fixture.main, ['status']), 0, 'Mode: non-strict');
      expectExit('launcher CLI status works', cliLauncher(fixture.main, ['status']), 0, 'Mode: non-strict');
      const jsonResult = cli(fixture.main, ['status', '--json']);
      expectExit('CLI status --json works', jsonResult, 0);
      assert.equal(JSON.parse(jsonResult.stdout).requirePushed, false);
      expectExit('CLI check works', cli(fixture.main, ['check']), 0, '非严格模式');
      expectExit('pre-push hook works', run(join(fixture.main, '.git', 'hooks', 'pre-push'), ['origin', fixture.mainRemote], { cwd: fixture.main, allowFailure: true }), 0, '非严格模式');
      expectExit('SourceTree check works', run('node', [sourcetree, fixture.main, 'check'], { cwd: fixture.main, allowFailure: true }), 0, '非严格模式');
      expectExit('SourceTree reinstall-hooks works', run('node', [sourcetree, fixture.main, 'reinstall-hooks'], { cwd: fixture.main, allowFailure: true }), 0, 'pre-push');
      expectExit('CLI unknown command exits 2', cli(fixture.main, ['unknown']), 2, 'Usage:');
    }
    {
      const fixture = createFixture();
      const newSha = makeSubmoduleCommit(fixture.main, { push: true });
      expectStateIncludes('accept fixture has mismatch', state(fixture.main), 'mismatch', 'libs');
      expectExit('CLI accept-pointers creates commit', cli(fixture.main, ['accept-pointers']), 0, '已生成 commit');
      assert.equal(gitOut(['ls-files', '-s', 'libs'], fixture.main).split(/\s+/)[1], newSha);
      expectExit('CLI check passes after accepting pushed pointer', cli(fixture.main, ['check']), 0);
    }
    {
      const fixture = createFixture();
      const recorded = gitOut(['ls-files', '-s', 'libs'], fixture.main).split(/\s+/)[1];
      makeSubmoduleCommit(fixture.main, { push: true });
      expectExit('CLI sync restores recorded pointer', cli(fixture.main, ['sync']), 0, 'Submodules synced');
      assert.equal(gitOut(['rev-parse', 'HEAD'], join(fixture.main, 'libs')), recorded);
    }
    {
      const fixture = createFixture();
      expectExit('non-interactive fix refuses without TTY', cli(fixture.main, ['fix'], { env: { SUBMODULE_INTERACTIVE: '0' } }), 1, '交互修复需要在终端中执行');
    }

    logStep('MCP access');
    {
      const fixture = createFixture();
      const responses = mcpViaStdin(fixture.main, [
        { jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'it', version: '0' } } },
        { jsonrpc: '2.0', id: 2, method: 'tools/list', params: {} },
        { jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'get_submodule_status', arguments: {} } },
        { jsonrpc: '2.0', id: 4, method: 'tools/call', params: { name: 'check_submodules', arguments: {} } },
        { jsonrpc: '2.0', id: 5, method: 'tools/call', params: { name: 'accept_current_pointers', arguments: { confirm: false } } },
        { jsonrpc: '2.0', id: 6, method: 'tools/call', params: { name: 'sync_recorded_pointers', arguments: { confirm: false } } },
      ]);
      assert.equal(responses[0].result.serverInfo.name, 'submodule-governance');
      assert.deepEqual(
        responses[1].result.tools.map((item) => item.name),
        ['get_submodule_status', 'check_submodules', 'accept_current_pointers', 'sync_recorded_pointers'],
      );
      assert.equal(JSON.parse(responses[2].result.content[0].text).requirePushed, false);
      assert.equal(responses[4].result.isError, true);
      assert.equal(responses[5].result.isError, true);
      results.push({ name: 'MCP read and confirm guard works', ok: true });
      process.stdout.write('ok - MCP read and confirm guard works\n');
    }
    {
      const fixture = createFixture();
      const newSha = makeSubmoduleCommit(fixture.main, { push: true });
      const responses = mcpViaStdin(fixture.main, [
        { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'accept_current_pointers', arguments: { confirm: true } } },
      ]);
      assert.equal(responses[0].result.isError, false);
      assert.match(responses[0].result.content[0].text, /已生成 commit/);
      assert.equal(gitOut(['ls-files', '-s', 'libs'], fixture.main).split(/\s+/)[1], newSha);
      results.push({ name: 'MCP accept_current_pointers confirm=true works', ok: true });
      process.stdout.write('ok - MCP accept_current_pointers confirm=true works\n');
    }
    {
      const fixture = createFixture();
      const recorded = gitOut(['ls-files', '-s', 'libs'], fixture.main).split(/\s+/)[1];
      makeSubmoduleCommit(fixture.main, { push: true });
      const responses = mcpViaStdin(fixture.main, [
        { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'sync_recorded_pointers', arguments: { confirm: true } } },
      ]);
      assert.equal(responses[0].result.isError, false);
      assert.equal(gitOut(['rev-parse', 'HEAD'], join(fixture.main, 'libs')), recorded);
      results.push({ name: 'MCP sync_recorded_pointers confirm=true works', ok: true });
      process.stdout.write('ok - MCP sync_recorded_pointers confirm=true works\n');
    }
    {
      const fixture = createFixture({ strict: true });
      makeSubmoduleCommit(fixture.main, { push: false });
      const responses = mcpViaStdin(fixture.main, [
        { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'accept_current_pointers', arguments: { confirm: true } } },
      ]);
      assert.equal(responses[0].result.isError, true);
      assert.match(responses[0].result.content[0].text, /尚未推送到 upstream/);
      results.push({ name: 'MCP strict accept blocks unpushed pointer', ok: true });
      process.stdout.write('ok - MCP strict accept blocks unpushed pointer\n');
    }

    logStep('uninstall');
    {
      const fixture = createFixture();
      expectExit('uninstall keeps config by default', run('node', [uninstall, fixture.main], { cwd: fixture.main, allowFailure: true }), 0, 'Uninstall complete');
      assert.ok(existsSync(join(fixture.main, '.submodule-governance.config')));
    }
    {
      const fixture = createFixture();
      expectExit('uninstall --remove-config removes config', run('node', [uninstall, fixture.main, '--remove-config'], { cwd: fixture.main, allowFailure: true }), 0, 'Removed config file');
      assert.equal(existsSync(join(fixture.main, '.submodule-governance.config')), false);
    }

    const okCount = results.filter((result) => result.ok).length;
    process.stdout.write(`\nPASS ${okCount} integration assertions\n`);
    process.stdout.write(`tmp: ${tmpRoot}${keepTmp ? ' (kept)' : ''}\n`);
  } finally {
    if (!keepTmp) rmSync(tmpRoot, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  console.error(`tmp: ${tmpRoot}${keepTmp ? ' (kept)' : ''}`);
  process.exitCode = 1;
});
