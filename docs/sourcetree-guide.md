# SourceTree Guide

SourceTree integration also uses Node. A Custom Action calls `sourcetree.mjs` from this template repository, and the script uses the repository path provided by SourceTree to find the local governance CLI installed in that repository.

## Prerequisite Installation

Install the governance tool into the target parent repository:

```bash
node /path/to/submodule-governance-template/bootstrap.mjs /path/to/main-repo
```

Confirm that the command works:

```bash
cd /path/to/main-repo
node .submodule-governance/cli/submodule-governance.mjs check
```

## Custom Actions

Add actions in SourceTree Custom Actions. Set `Script to run` to `node`. Set `Parameters` to the template script, the repository variable, and the action name.

| Action | Script to run | Parameters |
| --- | --- | --- |
| Submodule - Check | `node` | `/path/to/submodule-governance-template/sourcetree.mjs $REPO check` |
| Submodule - Accept Current Pointers | `node` | `/path/to/submodule-governance-template/sourcetree.mjs $REPO accept-pointers` |
| Submodule - Sync Recorded Pointers | `node` | `/path/to/submodule-governance-template/sourcetree.mjs $REPO sync` |
| Submodule - Reinstall Hook | `node` | `/path/to/submodule-governance-template/sourcetree.mjs $REPO reinstall-hooks` |

Repository path variables may differ between SourceTree versions. If `$REPO` is unavailable, replace it with the current repository path variable provided by your version or with an absolute repository path.

## Usage Notes

- Run `Submodule - Check` before normal commits.
- Run `Submodule - Accept Current Pointers` when a submodule has new commits and the parent repository should accept them.
- Run `Submodule - Sync Recorded Pointers` after switching the parent repository branch.
- Return to the terminal when you need to choose between updating pointers, restoring pointers, or accepting risk item by item:

```bash
node .submodule-governance/cli/submodule-governance.mjs fix
```

or:

```bash
node .submodule-governance/cli/submodule-governance.mjs push
```

## Troubleshooting

- Governance CLI not found: rerun `bootstrap.mjs` for the current repository.
- Push does not trigger checks: run `Submodule - Reinstall Hook`.
- Custom Action has no output: confirm that SourceTree is configured to show command output for the action.
