# VS Code Integration Guide

VS Code does not need a dedicated extension. Use tasks to call the Node CLI installed by this template.

## Prerequisite Installation

```bash
node /path/to/submodule-governance-template/bootstrap.mjs /path/to/main-repo
```

Then verify the command in the target parent repository:

```bash
node .submodule-governance/cli/submodule-governance.mjs check
```

## tasks.json Example

Create or update `.vscode/tasks.json` in the target parent repository:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Submodule: Check",
      "type": "shell",
      "command": "node .submodule-governance/cli/submodule-governance.mjs check",
      "problemMatcher": []
    },
    {
      "label": "Submodule: Status JSON",
      "type": "shell",
      "command": "node .submodule-governance/cli/submodule-governance.mjs status --json",
      "problemMatcher": []
    },
    {
      "label": "Submodule: Fix",
      "type": "shell",
      "command": "node .submodule-governance/cli/submodule-governance.mjs fix",
      "problemMatcher": [],
      "presentation": { "reveal": "always", "panel": "dedicated" }
    },
    {
      "label": "Submodule: Sync",
      "type": "shell",
      "command": "node .submodule-governance/cli/submodule-governance.mjs sync",
      "problemMatcher": []
    },
    {
      "label": "Submodule: Accept Current Pointers",
      "type": "shell",
      "command": "node .submodule-governance/cli/submodule-governance.mjs accept-pointers",
      "problemMatcher": []
    }
  ]
}
```

## Usage Notes

- Run `Submodule: Check` during daily work.
- Run `Submodule: Fix` when an interactive choice is needed, and reveal the task in the terminal panel.
- Run `Submodule: Status JSON` when structured status is needed.
- If the team shares `.vscode/tasks.json`, make sure the repository onboarding documentation includes one `bootstrap.mjs` installation step.
