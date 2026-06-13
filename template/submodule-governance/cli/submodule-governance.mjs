#!/usr/bin/env node

import { execFileSync, spawnSync } from 'node:child_process';
import {
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { dirname, isAbsolute, join, normalize } from 'node:path';
import { createInterface } from 'node:readline/promises';
import { stdin as input, stdout as output } from 'node:process';
import { fileURLToPath } from 'node:url';

const toolDir = dirname(dirname(fileURLToPath(import.meta.url)));
let captureChildOutput = false;
const cliCommand = 'node .submodule-governance/cli/submodule-governance.mjs';

const colors = (() => {
  const mode = process.env.SUBMODULE_GOVERNANCE_COLOR || 'auto';
  const enabled = !process.env.NO_COLOR && (mode === 'always' || (mode !== 'never' && process.stdout.isTTY));
  return {
    red: enabled ? '\u001b[31m' : '',
    yellow: enabled ? '\u001b[33m' : '',
    green: enabled ? '\u001b[32m' : '',
    reset: enabled ? '\u001b[0m' : '',
  };
})();

function line(message = '') {
  console.log(message);
}

function color(colorName, message) {
  console.log(`${colors[colorName]}${message}${colors.reset}`);
}

function info(message) {
  line(message);
}

function warn(message) {
  color('yellow', `警告：${message}`);
}

function errorMessage(message) {
  color('red', `错误：${message}`);
}

function success(message) {
  color('green', message);
}

function git(args, options = {}) {
  const inherit = options.inherit && !captureChildOutput;
  const result = spawnSync('git', args, {
    cwd: options.cwd,
    encoding: options.encoding === 'buffer' ? undefined : 'utf8',
    stdio: inherit ? 'inherit' : options.stdio || 'pipe',
    env: { ...process.env, ...(options.env || {}) },
  });
  if (!options.allowFailure && result.status !== 0) {
    const detail = [result.stdout, result.stderr].filter(Boolean).join('\n').trim();
    throw new Error(`git ${args.join(' ')} failed${detail ? `\n${detail}` : ''}`);
  }
  return result;
}

function gitOut(args, options = {}) {
  return (git(args, options).stdout || '').trim();
}

function repoRoot(cwd = process.cwd()) {
  return gitOut(['rev-parse', '--show-toplevel'], { cwd });
}

function absoluteFrom(root, value) {
  return isAbsolute(value) ? normalize(value) : normalize(join(root, value));
}

function gitDir(root) {
  return absoluteFrom(root, gitOut(['rev-parse', '--git-dir'], { cwd: root }));
}

function gitPath(root, value) {
  return absoluteFrom(root, gitOut(['rev-parse', '--git-path', value], { cwd: root }));
}

function pathExists(path) {
  return existsSync(path);
}

function isDirectory(path) {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

function configValue(file, key, cwd, args = []) {
  const result = git(['config', '--file', file, ...args, '--get', key], { cwd, allowFailure: true });
  if (result.status !== 0) return null;
  return result.stdout.trim();
}

function discoverSubmodules(root) {
  if (!pathExists(join(root, '.gitmodules'))) return [];
  const result = git(['config', '--file', '.gitmodules', '--get-regexp', 'path'], {
    cwd: root,
    allowFailure: true,
  });
  if (result.status !== 0) return [];
  return result.stdout
    .split(/\r?\n/)
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => entry.replace(/^[^\s]+\s+/, ''));
}

function loadGovernanceConfig(root, submodules) {
  const configFile = '.submodule-governance.config';
  const status = {
    requirePushed: false,
    configuredMainBranch: '',
    configuredSubmodules: [],
    configErrors: [],
  };
  if (!pathExists(join(root, configFile))) return status;

  const list = git(['config', '--file', configFile, '--list'], { cwd: root, allowFailure: true });
  if (list.status !== 0) {
    status.configErrors.push(`${configFile} 不是有效的 Git config 文件。`);
    return status;
  }

  const rawRequirePushed = git(['config', '--file', configFile, '--get', 'governance.requirePushed'], {
    cwd: root,
    allowFailure: true,
  });
  if (rawRequirePushed.status === 0) {
    const boolResult = git(
      ['config', '--file', configFile, '--type=bool', '--get', 'governance.requirePushed'],
      { cwd: root, allowFailure: true },
    );
    if (boolResult.status !== 0) status.configErrors.push(`${configFile} 中 governance.requirePushed 必须为布尔值。`);
    else status.requirePushed = boolResult.stdout.trim() === 'true';
  }

  const mainBranch = configValue(configFile, 'governance.mainBranch', root);
  if (mainBranch !== null) {
    if (!mainBranch) status.configErrors.push(`${configFile} 中 governance.mainBranch 不能为空。`);
    else status.configuredMainBranch = mainBranch;
  }

  const branchKeys = git(
    ['config', '--file', configFile, '--name-only', '--get-regexp', '^submodule\\..*\\.branch$'],
    { cwd: root, allowFailure: true },
  );
  if (branchKeys.status === 0) {
    for (const key of branchKeys.stdout.split(/\r?\n/).map((item) => item.trim()).filter(Boolean)) {
      const submodulePath = key.replace(/^submodule\./, '').replace(/\.branch$/, '');
      const value = configValue(configFile, key, root);
      if (!value) status.configErrors.push(`${configFile} 中 ${key} 不能为空。`);
      else if (!submodules.includes(submodulePath)) status.configErrors.push(`${configFile} 配置了不存在的子模块 '${submodulePath}'。`);
      else status.configuredSubmodules.push({ path: submodulePath, branch: value });
    }
  }

  return status;
}

function hasSubmodule(status, path) {
  return status.submodules.includes(path);
}

function collectStatus(cwd = process.cwd()) {
  const root = repoRoot(cwd);
  const submodules = discoverSubmodules(root);
  const config = loadGovernanceConfig(root, submodules);
  const status = {
    requirePushed: config.requirePushed,
    configFile: '.submodule-governance.config',
    configErrors: config.configErrors,
    submodules,
    missing: [],
    dirty: [],
    noUpstream: [],
    unpushed: [],
    stagedPointers: [],
    mismatches: [],
    branchMismatches: [],
    repoRoot: root,
    configuredMainBranch: config.configuredMainBranch,
    configuredSubmodules: config.configuredSubmodules,
  };

  if (config.configuredMainBranch) {
    const current = gitOut(['branch', '--show-current'], { cwd: root });
    if (current !== config.configuredMainBranch) {
      status.branchMismatches.push({
        path: '<main>',
        current: current || '<detached>',
        expected: config.configuredMainBranch,
      });
    }
  }

  for (const submodulePath of submodules) {
    const dotGit = join(root, submodulePath, '.git');
    if (!pathExists(dotGit)) {
      status.missing.push(submodulePath);
      continue;
    }

    if (gitOut(['-C', submodulePath, 'status', '--porcelain'], { cwd: root })) {
      status.dirty.push(submodulePath);
    }

    const lsFiles = gitOut(['ls-files', '-s', '--', submodulePath], { cwd: root });
    const indexed = lsFiles.split(/\s+/)[1] || '';
    const head = gitOut(['-C', submodulePath, 'rev-parse', 'HEAD'], { cwd: root });
    if (indexed && indexed !== head) {
      status.mismatches.push({ path: submodulePath, recorded: indexed, current: head });
    }

    const upstream = git(['-C', submodulePath, 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}'], {
      cwd: root,
      allowFailure: true,
    });
    if (upstream.status !== 0) {
      status.noUpstream.push(submodulePath);
    } else {
      const pushed = git(['-C', submodulePath, 'merge-base', '--is-ancestor', 'HEAD', '@{u}'], {
        cwd: root,
        allowFailure: true,
      });
      if (pushed.status !== 0) status.unpushed.push(submodulePath);
    }
  }

  for (const item of config.configuredSubmodules) {
    if (!pathExists(join(root, item.path, '.git'))) continue;
    const current = gitOut(['-C', item.path, 'branch', '--show-current'], { cwd: root });
    if (current !== item.branch) {
      status.branchMismatches.push({
        path: item.path,
        current: current || '<detached>',
        expected: item.branch,
      });
    }
  }

  const staged = gitOut(['diff', '--cached', '--name-only', '--diff-filter=AM'], { cwd: root });
  for (const changed of staged.split(/\r?\n/).map((item) => item.trim()).filter(Boolean)) {
    if (hasSubmodule(status, changed)) status.stagedPointers.push(changed);
  }

  return status;
}

export function getStatus(cwd) {
  const status = collectStatus(cwd);
  return {
    requirePushed: status.requirePushed,
    configFile: status.configFile,
    configErrors: status.configErrors,
    submodules: status.submodules,
    missing: status.missing,
    dirty: status.dirty,
    noUpstream: status.noUpstream,
    unpushed: status.unpushed,
    stagedPointers: status.stagedPointers,
    mismatches: status.mismatches,
    branchMismatches: status.branchMismatches,
  };
}

function printHumanStatus(status) {
  line(`Mode: ${status.requirePushed ? 'strict' : 'non-strict'}`);
  line(`Submodules: ${status.submodules.length}`);
  line(`Pointer mismatches: ${status.mismatches.length}`);
  line(`Dirty submodules: ${status.dirty.length}`);
  line(`Branch mismatches: ${status.branchMismatches.length}`);
  if (status.mismatches.length) {
    for (const item of status.mismatches) line(`  ${item.path}: ${item.recorded} -> ${item.current}`);
  }
}

function evaluateProblems(status, { bypass = false } = {}) {
  const warnings = [];
  const errors = [];
  const add = (collection, message) => collection.push(message);

  for (const message of status.configErrors) {
    if (status.requirePushed) add(errors, message);
    else {
      add(warnings, message);
      add(warnings, '无法可靠读取治理配置，本次按非严格模式仅提醒，不阻止 push。');
    }
  }
  for (const path of status.missing) {
    const message = `子模块 '${path}' 目录缺失或未初始化。请执行：${cliCommand} sync`;
    add(status.requirePushed ? errors : warnings, message);
  }
  for (const path of status.dirty) {
    const message = status.requirePushed
      ? `子模块 '${path}' 存在未提交改动。请先处理子模块中的改动。`
      : `子模块 '${path}' 存在未提交改动；这些改动不会包含在主仓库子模块指针 commit 中。`;
    add(status.requirePushed ? errors : warnings, message);
  }
  for (const path of status.noUpstream) {
    add(status.requirePushed ? errors : warnings, `子模块 '${path}' 未配置 upstream 分支，无法判断当前 HEAD 是否已推送。`);
  }
  for (const path of status.unpushed) {
    const message = status.requirePushed
      ? `子模块 '${path}' 当前 HEAD 尚未推送到 upstream。请先进入子模块执行 git push。`
      : `子模块 '${path}' 当前 HEAD 尚未推送到 upstream；他人或 CI 可能拉不到该 commit。`;
    add(status.requirePushed ? errors : warnings, message);
  }
  for (const item of status.branchMismatches) {
    if (bypass) add(warnings, `'${item.path}' 当前分支 '${item.current}' 与配置分支 '${item.expected}' 不一致；已确认本次继续。`);
    else if (status.requirePushed) add(errors, `'${item.path}' 当前分支 '${item.current}' 与配置分支 '${item.expected}' 不一致。请执行：${cliCommand} fix`);
    else add(warnings, `'${item.path}' 当前分支 '${item.current}' 与配置分支 '${item.expected}' 不一致。`);
  }
  for (const item of status.mismatches) {
    if (bypass) add(warnings, `子模块 '${item.path}' 当前 HEAD 与主仓库记录不一致；已确认本次继续。`);
    else if (status.requirePushed) add(errors, `子模块 '${item.path}' 当前 HEAD (${item.current}) 与主仓库记录的 commit (${item.recorded}) 不一致。请执行：${cliCommand} fix`);
    else add(warnings, `子模块 '${item.path}' 当前 HEAD (${item.current}) 与主仓库记录的 commit (${item.recorded}) 不一致。`);
  }
  for (const path of status.stagedPointers) {
    const message = status.requirePushed
      ? `子模块指针 '${path}' 已暂存但尚未提交。请先提交主仓库。`
      : `子模块指针 '${path}' 已暂存但尚未提交；本次 push 不会包含未提交的暂存内容。`;
    add(status.requirePushed ? errors : warnings, message);
  }
  return { warnings, errors };
}

function check({ cwd = process.cwd(), silent = false } = {}) {
  const status = collectStatus(cwd);
  if (!pathExists(join(status.repoRoot, '.gitmodules'))) {
    if (!silent) info('未发现 .gitmodules，跳过子模块检查。');
    return { ok: true, status };
  }
  if (status.submodules.length === 0) {
    if (!silent) info('.gitmodules 中未定义子模块路径。');
    return { ok: true, status };
  }

  const { warnings, errors } = evaluateProblems(status, {
    bypass: process.env.SUBMODULE_GOVERNANCE_BYPASS === '1',
  });
  if (!silent) {
    for (const message of warnings) warn(message);
    for (const message of errors) errorMessage(message);
  }

  if (errors.length) {
    if (!silent) errorMessage('子模块检查未通过，已阻止 push。');
    return { ok: false, status };
  }
  if (!silent && status.requirePushed) success('子模块检查通过（严格模式）。');
  if (!silent && !status.requirePushed) {
    if (warnings.length) {
      color(
        'red',
        `提醒：当前为非严格模式，本次检查不会强制阻止 git push，但上面的子模块警告可能导致他人或 CI 拉不到正确版本。请确认这些风险是否符合预期；如需处理，请先运行 ${cliCommand} fix，子模块缺失时运行 ${cliCommand} sync。`,
      );
    }
    success('子模块检查通过（非严格模式）。');
  }
  return { ok: true, status };
}

function mainHasNonSubmoduleChanges(status) {
  const changed = gitOut(['status', '--porcelain'], { cwd: status.repoRoot });
  for (const lineItem of changed.split(/\r?\n/).filter(Boolean)) {
    const path = lineItem.slice(3).replace(/ -> .+$/, '');
    if (!status.submodules.includes(path)) return true;
  }
  return false;
}

async function ask(question) {
  const rl = createInterface({ input, output });
  try {
    return (await rl.question(question)).trim();
  } finally {
    rl.close();
  }
}

function fatalIfWriteBlockedForAccept(status) {
  const errors = [];
  for (const message of status.configErrors) errors.push(message);
  for (const path of status.missing) errors.push(`子模块 '${path}' 目录缺失或未初始化。请先执行 submodule-sync。`);
  for (const item of status.branchMismatches) {
    errors.push(`'${item.path}' 当前分支 '${item.current}' 与配置分支 '${item.expected}' 不一致。请在终端执行 fix。`);
  }
  for (const path of status.dirty) {
    if (status.requirePushed) errors.push(`子模块 '${path}' 存在未提交改动。严格模式下不能接受当前指针。`);
    else warn(`子模块 '${path}' 存在未提交改动；这些内容不会包含在主仓库指针 commit 中。`);
  }
  for (const path of status.noUpstream) {
    if (status.requirePushed) errors.push(`子模块 '${path}' 未配置 upstream 分支。`);
    else warn(`子模块 '${path}' 未配置 upstream 分支。`);
  }
  for (const path of status.unpushed) {
    if (status.requirePushed) errors.push(`子模块 '${path}' 当前 HEAD 尚未推送到 upstream。`);
    else warn(`子模块 '${path}' 当前 HEAD 尚未推送到 upstream。`);
  }
  for (const message of errors) errorMessage(message);
  return errors.length > 0;
}

function commitPointers(root, paths) {
  const unique = [...new Set(paths)];
  if (!unique.length) return false;
  const message = unique.length > 1 ? 'chore(submodule): update pointers' : `chore(submodule): update ${unique[0]} pointer`;
  git(['commit', '--no-verify', '-m', message, '--', ...unique], { cwd: root, inherit: true });
  success(`已生成 commit：${gitOut(['rev-parse', '--short', 'HEAD'], { cwd: root })} ${message}`);
  return true;
}

function acceptPointers(cwd = process.cwd()) {
  const status = collectStatus(cwd);
  if (!pathExists(join(status.repoRoot, '.gitmodules')) || status.submodules.length === 0) {
    info('没有需要治理的子模块。');
    return 0;
  }
  if (fatalIfWriteBlockedForAccept(status)) {
    errorMessage('当前状态不适合自动接受子模块指针，请在终端中处理。');
    return 1;
  }
  const commitPaths = [...status.stagedPointers];
  for (const path of status.stagedPointers) {
    info(`提示：子模块指针 '${path}' 已暂存，将直接纳入本次治理 commit。`);
  }
  if (status.mismatches.length) {
    const paths = status.mismatches.map((item) => item.path);
    git(['add', ...paths], { cwd: status.repoRoot });
    commitPaths.push(...paths);
  }
  if (!commitPaths.length) {
    success('主仓库记录的子模块指针无需更新。');
    return 0;
  }
  commitPointers(status.repoRoot, commitPaths);
  for (const item of status.mismatches) line(`  - ${item.path}: ${item.recorded} -> ${item.current}`);
  return 0;
}

async function fix(cwd = process.cwd()) {
  if (process.env.SUBMODULE_INTERACTIVE === '0') {
    errorMessage('交互修复需要在终端中执行。');
    return 1;
  }
  let status = collectStatus(cwd);
  if (!pathExists(join(status.repoRoot, '.gitmodules')) || status.submodules.length === 0) {
    info('没有需要治理的子模块。');
    return 0;
  }

  let hasError = false;
  let riskAcknowledged = false;
  let changed = false;
  const commitPaths = [...status.stagedPointers];

  for (const message of status.configErrors) {
    errorMessage(message);
    hasError = true;
  }
  for (const path of status.missing) {
    errorMessage(`子模块 '${path}' 目录缺失或未初始化。请先执行 submodule-sync。`);
    hasError = true;
  }
  for (const path of status.stagedPointers) {
    info(`提示：子模块指针 '${path}' 已暂存，将直接纳入本次治理 commit。`);
  }
  for (const path of status.dirty) {
    if (status.requirePushed) {
      errorMessage(`子模块 '${path}' 存在未提交改动。严格模式下不能自动修复。`);
      hasError = true;
    } else {
      warn(`子模块 '${path}' 存在未提交改动；这些内容不会包含在主仓库指针 commit 中。`);
    }
  }
  for (const path of status.noUpstream) {
    if (status.requirePushed) {
      errorMessage(`子模块 '${path}' 未配置 upstream 分支。`);
      hasError = true;
    } else warn(`子模块 '${path}' 未配置 upstream 分支。`);
  }
  for (const path of status.unpushed) {
    if (status.requirePushed) {
      errorMessage(`子模块 '${path}' 当前 HEAD 尚未推送到 upstream。`);
      hasError = true;
    } else warn(`子模块 '${path}' 当前 HEAD 尚未推送到 upstream。`);
  }
  if (hasError) {
    errorMessage('存在需要先手动处理的问题，未执行修复。');
    return 1;
  }

  if (status.branchMismatches.length) {
    line();
    line('发现分支配置不一致：');
    for (const item of status.branchMismatches) line(`  - ${item.path}: ${item.current} -> ${item.expected}`);
    line('请选择处理方式：');
    line('  [1] 根据配置切换到一致分支');
    line('  [2] 保持当前分支并承担本次风险');
    line('  [3] 取消');
    const choice = await ask('请输入选项 [1/2/3]: ');
    if (choice === '1') {
      if (mainHasNonSubmoduleChanges(status)) {
        errorMessage('主仓库存在非子模块改动，无法自动切换分支。');
        return 1;
      }
      if (status.configuredMainBranch && gitOut(['branch', '--show-current'], { cwd: status.repoRoot }) !== status.configuredMainBranch) {
        git(['checkout', status.configuredMainBranch], { cwd: status.repoRoot, inherit: true });
      }
      for (const item of status.configuredSubmodules) {
        const dirty = gitOut(['-C', item.path, 'status', '--porcelain'], { cwd: status.repoRoot });
        if (dirty) {
          errorMessage(`子模块 '${item.path}' 存在改动，无法切换分支。`);
          return 1;
        }
        git(['-C', item.path, 'fetch', 'origin'], { cwd: status.repoRoot, inherit: true });
        git(['-C', item.path, 'checkout', item.branch], { cwd: status.repoRoot, inherit: true });
        git(['-C', item.path, 'pull', '--ff-only', 'origin', item.branch], { cwd: status.repoRoot, inherit: true });
      }
      success('分支已根据配置处理完成，重新检查子模块状态。');
      status = collectStatus(status.repoRoot);
    } else if (choice === '2') riskAcknowledged = true;
    else {
      errorMessage('已取消操作。');
      return 1;
    }
  }

  const restore = [];
  const update = [];
  if (status.mismatches.length) {
    line();
    line(`发现 ${status.mismatches.length} 个子模块与主仓库记录不一致：`);
    for (const item of status.mismatches) line(`  - ${item.path}: ${item.recorded} -> ${item.current}`);
    for (const item of status.mismatches) {
      line();
      line(`子模块 '${item.path}'：`);
      line('  [1] 将主仓库指针更新到当前 commit');
      line('  [2] 将子模块恢复到主仓库记录的 commit');
      line('  [3] 保持不一致并承担本次风险');
      line('  [4] 取消');
      const choice = await ask('请输入选项 [1/2/3/4]: ');
      if (choice === '1') update.push(item);
      else if (choice === '2') {
        if (gitOut(['-C', item.path, 'status', '--porcelain'], { cwd: status.repoRoot })) {
          errorMessage(`子模块 '${item.path}' 存在未提交内容，不能恢复到主仓库记录的 commit。`);
          return 1;
        }
        restore.push(item);
      } else if (choice === '3') riskAcknowledged = true;
      else {
        errorMessage('已取消操作。');
        return 1;
      }
    }
  }

  for (const item of restore) {
    git(['-C', item.path, 'checkout', item.recorded], { cwd: status.repoRoot, inherit: true });
    success(`已恢复：'${item.path}' 已 checkout 到 ${item.recorded}。`);
    changed = true;
  }
  if (update.length) {
    const paths = update.map((item) => item.path);
    git(['add', ...paths], { cwd: status.repoRoot });
    commitPaths.push(...paths);
  }
  if (commitPaths.length) {
    commitPointers(status.repoRoot, commitPaths);
    changed = true;
  }
  if (changed) success('子模块修复完成。');
  else info('未修改工作区。');
  return riskAcknowledged ? 10 : 0;
}

function syncSubmodules(cwd = process.cwd()) {
  const root = repoRoot(cwd);
  if (!pathExists(join(root, '.gitmodules'))) {
    info('No .gitmodules found. Nothing to sync.');
    return 0;
  }
  git(['submodule', 'sync', '--recursive'], { cwd: root, inherit: true });
  git(['submodule', 'update', '--init', '--recursive'], { cwd: root, inherit: true });
  success('Submodules synced to commits recorded by main repository.');
  return 0;
}

async function push(args, cwd = process.cwd()) {
  const fixExit = await fix(cwd);
  if (fixExit === 0) {
    git(['push', ...args], { cwd: repoRoot(cwd), inherit: true });
    return 0;
  }
  if (fixExit === 10) {
    warn('本次 push 将带着已确认的分支或指针风险继续。');
    git(['push', ...args], {
      cwd: repoRoot(cwd),
      inherit: true,
      env: { SUBMODULE_GOVERNANCE_BYPASS: '1' },
    });
    return 0;
  }
  return fixExit;
}

function hookScript() {
  return `#!/usr/bin/env sh
set -eu
repo_root="$(git rev-parse --show-toplevel)"
git_dir="$(git rev-parse --git-dir)"
case "$git_dir" in
  /*|[A-Za-z]:/*|[A-Za-z]:\\\\*) ;;
  *) git_dir="$repo_root/$git_dir" ;;
esac
export SUBMODULE_PUSH_REMOTE_NAME="\${1:-}"
export SUBMODULE_PUSH_REMOTE_URL="\${2:-}"
exec node "$git_dir/submodule-governance/cli/submodule-governance.mjs" check
`;
}

function installHooks(cwd = process.cwd()) {
  const root = repoRoot(cwd);
  const gdir = gitDir(root);
  const configuredHooksPath = git(['config', '--get', 'core.hooksPath'], { cwd: root, allowFailure: true }).stdout.trim();
  let hooksDir = configuredHooksPath ? absoluteFrom(root, configuredHooksPath) : join(gdir, 'hooks');
  let hookFile = join(hooksDir, 'pre-push');
  const useHuskyWrapper = normalize(hooksDir) === normalize(join(root, '.husky', '_'));
  if (useHuskyWrapper) hookFile = join(root, '.husky', 'pre-push');

  if (pathExists(hookFile)) {
    const existing = readFileSync(hookFile, 'utf8');
    if (existing.includes('submodule-governance/cli/submodule-governance.mjs') || existing.includes('submodule-governance/pre-push-hook.sh')) {
      writeFileSync(hookFile, hookScript());
      chmodSync(hookFile, 0o755);
      success(`Updated pre-push hook at ${hookFile}`);
      return 0;
    }
    warn(`Existing pre-push hook was not overwritten: ${hookFile}`);
    info('Add this command to that hook, then run installation again:');
    info(`  ${cliCommand} check`);
    return 1;
  }

  mkdirSync(dirname(hookFile), { recursive: true });
  writeFileSync(hookFile, hookScript());
  chmodSync(hookFile, 0o755);
  success(`Installed pre-push hook to ${hookFile}`);
  return 0;
}

function uninstall({ removeConfig = false, cwd = process.cwd() } = {}) {
  const root = repoRoot(cwd);
  const gdir = gitDir(root);
  const configuredHooksPath = git(['config', '--get', 'core.hooksPath'], { cwd: root, allowFailure: true }).stdout.trim();
  let hooksDir = configuredHooksPath ? absoluteFrom(root, configuredHooksPath) : join(gdir, 'hooks');
  let hookFile = join(hooksDir, 'pre-push');
  if (normalize(hooksDir) === normalize(join(root, '.husky', '_'))) hookFile = join(root, '.husky', 'pre-push');

  if (pathExists(hookFile)) {
    const content = readFileSync(hookFile, 'utf8');
    if (content.includes('submodule-governance/cli/submodule-governance.mjs') || content.includes('submodule-governance/pre-push-hook.sh')) {
      rmSync(hookFile, { force: true });
      success(`Removed generated pre-push hook: ${hookFile}`);
    } else warn(`Existing pre-push hook was not modified: ${hookFile}`);
  }

  const entryDir = join(root, '.submodule-governance');
  if (pathExists(join(entryDir, '.generated-by-submodule-governance'))) {
    rmSync(entryDir, { recursive: true, force: true });
    success(`Removed launcher directory: ${entryDir}`);
  } else if (pathExists(entryDir)) warn(`Launcher path exists but was not generated by submodule governance: ${entryDir}`);

  const installedToolDir = join(gdir, 'submodule-governance');
  if (isDirectory(installedToolDir)) {
    rmSync(installedToolDir, { recursive: true, force: true });
    success(`Removed tool directory: ${installedToolDir}`);
  }

  const config = join(root, '.submodule-governance.config');
  if (removeConfig && pathExists(config)) {
    rmSync(config, { force: true });
    success(`Removed config file: ${config}`);
  } else if (!removeConfig) info(`Kept config file: ${config}`);
  success('Uninstall complete.');
  return 0;
}

export function runCaptured(command, cwd) {
  const commands = {
    check: () => check({ cwd, silent: false }).ok ? 0 : 1,
    'accept-pointers': () => acceptPointers(cwd),
    sync: () => syncSubmodules(cwd),
  };
  if (!commands[command]) return { ok: false, exitCode: 2, stdout: '', stderr: `Unknown command: ${command}` };

  const oldLog = console.log;
  const chunks = [];
  console.log = (value = '') => chunks.push(`${value}\n`);
  captureChildOutput = true;
  try {
    const code = commands[command]();
    const stdout = chunks.join('');
    return { ok: code === 0, exitCode: code, stdout, stderr: '' };
  } catch (error) {
    return { ok: false, exitCode: 1, stdout: chunks.join(''), stderr: `${error.message || error}\n` };
  } finally {
    captureChildOutput = false;
    console.log = oldLog;
  }
}

function stateTsv(cwd = process.cwd()) {
  const status = collectStatus(cwd);
  line(`meta\trequirePushed\t${status.requirePushed ? 1 : 0}`);
  line(`meta\tconfigFile\t${status.configFile}`);
  for (const message of status.configErrors) line(`configError\t${message}`);
  for (const path of status.submodules) line(`submodule\t${path}`);
  for (const path of status.missing) line(`missing\t${path}`);
  for (const path of status.dirty) line(`dirty\t${path}`);
  for (const path of status.noUpstream) line(`noUpstream\t${path}`);
  for (const path of status.unpushed) line(`unpushed\t${path}`);
  for (const path of status.stagedPointers) line(`stagedPointer\t${path}`);
  for (const item of status.mismatches) line(`mismatch\t${item.path}\t${item.recorded}\t${item.current}`);
  for (const item of status.branchMismatches) line(`branchMismatch\t${item.path}\t${item.current}\t${item.expected}`);
  return 0;
}

function usage() {
  console.log('Usage: submodule-governance <status|state|check|accept-pointers|sync|fix|push|install-hooks|uninstall> [--json]');
}

async function main() {
  const [command, ...args] = process.argv.slice(2);
  try {
    if (command === 'status') {
      const status = getStatus();
      if (args.includes('--json')) console.log(JSON.stringify(status, null, 2));
      else printHumanStatus(status);
      return;
    }
    if (command === 'state') {
      process.exitCode = stateTsv();
      return;
    }
    if (command === 'check') {
      process.exitCode = check().ok ? 0 : 1;
      return;
    }
    if (command === 'accept-pointers') {
      process.exitCode = acceptPointers();
      return;
    }
    if (command === 'sync') {
      process.exitCode = syncSubmodules();
      return;
    }
    if (command === 'fix') {
      process.exitCode = await fix();
      return;
    }
    if (command === 'push') {
      process.exitCode = await push(args);
      return;
    }
    if (command === 'install-hooks') {
      process.exitCode = installHooks();
      return;
    }
    if (command === 'uninstall') {
      const target = args.find((arg) => !arg.startsWith('-'));
      process.exitCode = uninstall({ removeConfig: args.includes('--remove-config'), cwd: target || process.cwd() });
      return;
    }
    usage();
    process.exitCode = 2;
  } catch (error) {
    errorMessage(error.message || String(error));
    process.exitCode = 1;
  }
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}
