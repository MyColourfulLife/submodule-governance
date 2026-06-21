# VS Code 集成教程

VS Code 不需要专用扩展，使用 tasks 直接调用本仓库安装出的 Node CLI 即可。

## 前置安装

```bash
node /path/to/submodule-governance-template/bootstrap.mjs /path/to/main-repo
```

然后在目标主仓库中确认：

```bash
node .submodule-governance/cli/submodule-governance.mjs check
```

## tasks.json 示例

在目标主仓库创建或更新 `.vscode/tasks.json`：

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

## 使用建议

- 日常先运行 `Submodule: Check`。
- 有交互选择时运行 `Submodule: Fix`，并让任务在终端面板中显示。
- 需要结构化状态时运行 `Submodule: Status JSON`。
- 如果团队共享 `.vscode/tasks.json`，请确保仓库 onboarding 文档包含一次 `bootstrap.mjs` 安装步骤。
