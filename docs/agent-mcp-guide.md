# Agent MCP Integration Guide

The MCP server is a thin adapter over the governance CLI. It is intended for agents that need read-only submodule status checks or controlled write operations after user confirmation. The first release uses Node.js 18+.

## Installation

```bash
node /path/to/submodule-governance-template/bootstrap.mjs /path/to/main-repo
```

Confirm that the local CLI and MCP server are available:

```bash
cd /path/to/main-repo
node .submodule-governance/cli/submodule-governance.mjs status --json
node .submodule-governance/cli/submodule-governance-mcp.mjs
```

The second command waits for stdio JSON-RPC input. If it starts normally, exit with `Ctrl+C`.

## MCP Client Configuration

Configure a stdio MCP-compatible agent client:

```json
{
  "mcpServers": {
    "submodule-governance-main": {
      "command": "node",
      "args": [
        "/path/to/main-repo/.submodule-governance/cli/submodule-governance-mcp.mjs"
      ],
      "cwd": "/path/to/main-repo"
    }
  }
}
```

Requirements:

- `args` points to the MCP server installed in the target parent repository.
- `cwd` must be the same target parent repository root.
- Multiple worktrees or parent repositories should use separate server names.

## Tools

| Tool | Modifies state | Purpose |
| --- | --- | --- |
| `get_submodule_status` | No | Returns the same structured status as `status --json` |
| `check_submodules` | No | Runs read-only checks |
| `accept_current_pointers` | Yes | Accepts current submodule pointers and creates a parent repository commit when allowed |
| `sync_recorded_pointers` | Yes | Checks submodules out to the commits recorded by the parent repository |

Write tools must receive `confirm: true`. The server rejects write calls without confirmation.

## Recommended Agent Flow

Read-only diagnosis:

1. Call `get_submodule_status`.
2. Call `check_submodules`.
3. Explain dirty, unpushed, mismatch, and branch mismatch risks to the user.

Accept the current submodule versions:

1. Call `get_submodule_status` and show the pointers that will be accepted.
2. Obtain explicit user confirmation.
3. Call `accept_current_pointers` with `{ "confirm": true }`.
4. Call `check_submodules` again.

Restore the versions recorded by the parent repository:

1. Call `get_submodule_status` and confirm the mismatch.
2. Obtain explicit user confirmation.
3. Call `sync_recorded_pointers` with `{ "confirm": true }`.
4. Call `check_submodules` again.

## Safety Boundaries

- MCP does not expose automatic push.
- MCP does not expose interactive `fix`; ask the user to run the CLI in a terminal when item-by-item choices are required.
- In strict mode, unpushed submodule commits, dirty submodules, branch mismatches, and similar risks still block write tools.
- MCP only operates on the repository used as its startup `cwd`; use absolute paths and clear names in client configuration.
