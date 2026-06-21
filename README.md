# Submodule Governance Template

This template adds local governance checks to an existing Git submodule parent repository. The first release uses Node.js 18+ for installation, removal, command-line usage, SourceTree, VS Code, and MCP integration.

Chinese documentation is available in [README.zh-CN.md](README.zh-CN.md).

## Installation

```bash
node /path/to/submodule-governance-template/bootstrap.mjs /path/to/main-repo
```

Strict mode blocks pushes when high-risk submodule states are detected:

```bash
node /path/to/submodule-governance-template/bootstrap.mjs /path/to/main-repo --strict
```

After installation, the target repository contains:

- `.submodule-governance/cli/submodule-governance.mjs`: daily CLI entry point.
- `.submodule-governance/cli/submodule-governance-mcp.mjs`: local MCP server.
- `.submodule-governance.config`: team configuration file, recommended for commit to the parent repository.
- `pre-push` hook: read-only pre-push check that does not modify the working tree.

## Common Commands

Run these commands from the target parent repository root:

```bash
node .submodule-governance/cli/submodule-governance.mjs check
node .submodule-governance/cli/submodule-governance.mjs status --json
node .submodule-governance/cli/submodule-governance.mjs fix
node .submodule-governance/cli/submodule-governance.mjs push
node .submodule-governance/cli/submodule-governance.mjs sync
node .submodule-governance/cli/submodule-governance.mjs accept-pointers
```

Uninstall:

```bash
node /path/to/submodule-governance-template/uninstall.mjs /path/to/main-repo
node /path/to/submodule-governance-template/uninstall.mjs /path/to/main-repo --remove-config
```

## Configuration

`.submodule-governance.config` uses Git config syntax:

```ini
[governance]
    requirePushed = false
    # mainBranch = main

# [submodule "ios"]
#     branch = dev/v2.2.7/stable
```

- `governance.requirePushed = false`: non-strict mode, risks are reported but do not block push.
- `governance.requirePushed = true`: strict mode, unpushed submodule commits, dirty submodules, pointer mismatches, and branch mismatches block push.
- `governance.mainBranch`: expected parent repository branch. If omitted, no parent branch check is performed.
- `submodule "<path>".branch`: expected submodule branch. `<path>` must match the path in `.gitmodules`.

## Documentation

English:

- [Command-line guide](docs/command-line-guide.md)
- [SourceTree guide](docs/sourcetree-guide.md)
- [VS Code integration guide](docs/vscode-guide.md)
- [Agent MCP integration guide](docs/agent-mcp-guide.md)

Chinese:

- [Command-line guide](docs/zh-CN/command-line-guide.md)
- [SourceTree guide](docs/zh-CN/sourcetree-guide.md)
- [VS Code integration guide](docs/zh-CN/vscode-guide.md)
- [Agent MCP integration guide](docs/zh-CN/agent-mcp-guide.md)

## Safety Boundaries

- The hook triggered by `git push` is read-only. It does not create commits, checkout branches, or change configuration.
- `fix` and `push` are interactive commands. They ask the developer before applying changes.
- `accept-pointers` creates a parent repository commit to explicitly accept the current submodule pointers.
- MCP does not expose automatic push. Write tools require `confirm: true`.
- The first release is not compatible with older entry points. Re-run `bootstrap.mjs` after template updates to overwrite the local installation.

## Integration Test

```bash
node submodule-governance-template/tests/integration-submodule-governance.mjs
```

Keep temporary test repositories:

```bash
KEEP_SUBMODULE_GOVERNANCE_TEST_TMP=1 node submodule-governance-template/tests/integration-submodule-governance.mjs
```
