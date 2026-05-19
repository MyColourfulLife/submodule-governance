# Submodule Governance Template

Reusable template to add local git submodule governance to an existing main repository.
After running `bootstrap.sh`, a `pre-push` hook is installed by default. In daily work, developers usually only need to run `git push`; the hook performs submodule checks automatically before push.

Chinese documentation: [README.zh-CN.md](README.zh-CN.md)

## Background

Many business projects are composed of one main repository and several Git Submodule repositories. For example, a `rn_module` main repository may include `ios` and `android` as submodules.

As feature branches grow, teams often hit submodule drift: the main repo is on one branch, but local submodules still point to old commits; or a submodule has new commits, but the main repository forgot to commit the updated submodule pointer.

Git Submodule records a specific submodule commit in the main repository. It does not automatically follow a branch. This template helps keep the main repository pointer, local submodule checkout, and remotely available submodule commit aligned.

## Why this exists

Manual submodule workflows are easy to miss:

- Developers forget to sync submodules after branch changes.
- Submodule commits are created, but the main repository pointer is not committed.
- The main repository may reference a submodule commit that other developers cannot fetch.
- Submodule pointer changes are easy to overlook during feature branch merges.
- Problems often appear later during checkout, build, CI, or integration.

This template moves those checks to local `git push`, with clear failure messages and recovery commands.

## Compatibility

- Verified in macOS/Linux shell environments.
- Not validated on Windows yet.

## Core features

- Automatic check before `git push` through `.git/hooks/pre-push`.
- Blocks push when a submodule is missing or not initialized, and prompts `.git/submodule-governance/submodule-sync.sh`.
- Blocks push when a submodule has uncommitted changes.
- Shows an interactive Chinese repair menu when submodule HEAD differs from the commit recorded by the main repository.
- Blocks push when a submodule pointer is staged but not committed.
- Warns by default when submodule HEAD is not pushed to upstream; strict mode turns this into a blocking error.
- Provides `.git/submodule-governance/submodule-sync.sh` to run `git submodule sync --recursive` and `git submodule update --init --recursive`.

## What this template installs

- `.git/submodule-governance/submodule-check.sh`
- `.git/submodule-governance/submodule-sync.sh`
- `.git/submodule-governance/pre-push-hook.sh`
- `.git/submodule-governance/install-hooks.sh`
- `.submodule-governance.env`
- `.git/hooks/pre-push` (installed by script)

By default, this template does not create a business `scripts/` directory and does not overwrite existing project scripts.

## Git tracking policy

The installed governance scripts do not need to be tracked by the target repository. They are installed under `.git/submodule-governance/`, which is local Git metadata.

It is recommended to track `.submodule-governance.env` in the target repository, because it defines whether the team uses strict mode.

## Install into current repo

Run this command inside your target main repository:

```bash
/path/to/submodule-governance-template/bootstrap.sh .
```

## Install into another existing repo path

```bash
/path/to/submodule-governance-template/bootstrap.sh /path/to/target-repo
```

After installation, the target repository checks submodule state automatically before push.

## Strict mode

Install with strict mode:

```bash
/path/to/submodule-governance-template/bootstrap.sh /path/to/target-repo --strict
```

Switch strict mode after install by editing `.submodule-governance.env`:

```bash
SUBMODULE_REQUIRE_PUSHED=1
```

Use `SUBMODULE_REQUIRE_PUSHED=0` for non-strict mode.

## Daily usage in target repo

Usually, developers do not need to run check scripts manually. The installed `pre-push` hook runs automatically during `git push`.

If submodules are missing or out of sync, run:

```bash
.git/submodule-governance/submodule-sync.sh
```

Manual check is still available for debugging or preflight:

```bash
.git/submodule-governance/submodule-check.sh
```

Reinstall hook if needed:

```bash
.git/submodule-governance/install-hooks.sh
```

## Key protection

When a submodule has a new commit but the main repository pointer was not updated, `git push` in main repo is blocked and will prompt:

```text
当前子模块 'ios' 与主仓库记录不一致：
  子模块当前 commit：<current_commit>
  主仓库记录 commit：<recorded_commit>

请选择修复方式：
  [1] 将主仓库指针更新到当前 'ios' commit
  [2] 将 'ios' 恢复到主仓库记录的 commit
  [3] 跳过，本次阻止 push
```

Option `[1]` runs `git add <submodule_path>` and blocks the current push so the developer can commit the pointer update.

Option `[2]` checks the submodule back out to the commit recorded by the main repository.

Option `[3]` makes no change and blocks the current push.

In non-interactive environments, the script prints a Chinese error message and blocks push without showing a menu.
