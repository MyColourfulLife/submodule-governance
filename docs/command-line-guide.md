# Command-line Guide

This guide is for developers who use submodule governance from a terminal, script, or CI job. The first release uses Node.js 18+, and the commands are the same on macOS and Windows.

## Installation

```bash
node /path/to/submodule-governance-template/bootstrap.mjs /path/to/main-repo
```

Enable strict mode:

```bash
node /path/to/submodule-governance-template/bootstrap.mjs /path/to/main-repo --strict
```

After installation, enter the target parent repository:

```bash
cd /path/to/main-repo
node .submodule-governance/cli/submodule-governance.mjs check
```

## Daily Workflow

Run an explicit check before push:

```bash
node .submodule-governance/cli/submodule-governance.mjs check
```

Run the interactive repair flow when action is required:

```bash
node .submodule-governance/cli/submodule-governance.mjs fix
```

Repair first, then continue with push:

```bash
node .submodule-governance/cli/submodule-governance.mjs push
```

After switching the parent repository branch, restore submodules to the commits recorded by the parent repository:

```bash
node .submodule-governance/cli/submodule-governance.mjs sync
```

Accept the current submodule HEADs as the versions to release, and create a parent repository pointer commit:

```bash
node .submodule-governance/cli/submodule-governance.mjs accept-pointers
```

## Command Reference

| Command | Modifies working tree | Purpose |
| --- | --- | --- |
| `check` | No | Runs the same read-only checks as the push hook |
| `status` | No | Prints a human-readable summary |
| `status --json` | No | Prints JSON for scripts, CI, and agents |
| `state` | No | Prints TSV status, mainly for tests or lightweight scripts |
| `fix` | Maybe | Interactively handles branch or submodule pointer mismatches |
| `push` | Maybe | Interactively handles issues, then runs `git push` |
| `sync` | Yes | Runs submodule sync/update and restores recorded commits |
| `accept-pointers` | Yes | Accepts current submodule pointers and creates a parent repository commit |
| `install-hooks` | Yes | Reinstalls the `pre-push` hook |
| `uninstall` | Yes | Removes the local governance tool and keeps the config file by default |

Full form:

```bash
node .submodule-governance/cli/submodule-governance.mjs <command>
```

## JSON Status

```bash
node .submodule-governance/cli/submodule-governance.mjs status --json
```

Main fields:

| Field | Meaning |
| --- | --- |
| `requirePushed` | Whether strict mode is enabled |
| `submodules` | Submodule paths declared in `.gitmodules` |
| `missing` | Submodules that are not initialized or whose directories are missing |
| `dirty` | Submodules with uncommitted changes |
| `unpushed` | Submodules whose current HEAD has not been pushed to upstream |
| `mismatches` | Submodule HEAD differs from the gitlink recorded by the parent repository |
| `branchMismatches` | Current branch differs from the configured branch |
| `stagedPointers` | Staged but uncommitted submodule pointers |
| `configErrors` | Configuration syntax or content errors |

## Configuration

The configuration file is stored at the target parent repository root:

```bash
.submodule-governance.config
```

Example:

```ini
[governance]
    requirePushed = true
    mainBranch = main

[submodule "ios"]
    branch = main
```

You can update it with Git:

```bash
git config --file .submodule-governance.config governance.requirePushed true
git config --file .submodule-governance.config governance.mainBranch main
git config --file .submodule-governance.config submodule.ios.branch main
```

## Uninstall

```bash
node /path/to/submodule-governance-template/uninstall.mjs /path/to/main-repo
```

Also remove the configuration file:

```bash
node /path/to/submodule-governance-template/uninstall.mjs /path/to/main-repo --remove-config
```
