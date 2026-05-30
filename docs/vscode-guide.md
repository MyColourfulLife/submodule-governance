# VS Code 集成教程

本文面向希望在 VS Code 中直接运行子模块治理命令的开发者。目标很简单：把常用的 `check`、`fix`、`sync` 和 `reinstall hooks` 做成工作区任务，直接从命令面板点击运行。

## 1. 适用场景

- 日常主要在 VS Code 里开发。
- 希望不用记治理脚本命令路径。
- 希望把交互修复放在 VS Code 内置终端中完成。

## 2. 前提

先在目标仓库本地安装治理脚本：

```bash
/path/to/submodule-governance-template/bootstrap.sh /path/to/main-repo
```

安装完成后，目标仓库中会有：

```text
.git/submodule-governance/
```

VS Code task 只是这些本地脚本的图形化入口，不会替代安装步骤。

## 3. 文件位置

VS Code 工作区任务文件应放在：

```text
.vscode/tasks.json
```

这两个点最好固定：

- 文件名建议不要改。VS Code 工作区任务默认只识别 `.vscode/tasks.json`。
- `version` 这里不是项目版本号，而是 VS Code task schema 版本，当前应使用 `2.0.0`，不要改成 `1.0.0`。

也就是说，这种写法是正确的：

```json
{
  "version": "2.0.0"
}
```

## 4. 最小可用配置

把下面的内容放进 `.vscode/tasks.json`：

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Submodule: Check",
      "type": "shell",
      "command": ".git/submodule-governance/submodule-check.sh",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "shared",
        "clear": true
      }
    },
    {
      "label": "Submodule: Fix",
      "type": "shell",
      "command": ".git/submodule-governance/submodule-fix.sh",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "shared",
        "clear": true,
        "focus": true
      }
    },
    {
      "label": "Submodule: Sync",
      "type": "shell",
      "command": ".git/submodule-governance/submodule-sync.sh",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "shared",
        "clear": true
      }
    },
    {
      "label": "Submodule: Reinstall Hooks",
      "type": "shell",
      "command": ".git/submodule-governance/install-hooks.sh",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "shared",
        "clear": true
      }
    }
  ]
}
```

## 5. 如何使用

在 VS Code 中：

1. 打开目标仓库根目录。
2. 按 `Cmd+Shift+P`。
3. 输入 `Tasks: Run Task`。
4. 选择你要运行的任务。

常用任务说明：

- `Submodule: Check`：只读检查当前子模块状态。
- `Submodule: Fix`：打开交互修复流程，在底部终端中逐项处理问题。
- `Submodule: Sync`：把子模块同步到主仓库已记录的 commit。
- `Submodule: Reinstall Hooks`：本地 hook 丢失时重新安装。

## 6. 推荐使用节奏

推荐在 VS Code 里这样用：

1. 先执行 `Submodule: Check`
2. 有异常时执行 `Submodule: Fix` 或 `Submodule: Sync`
3. 确认状态无误后，手动执行 `git push`

不建议把修复和 push 完全绑死成一个自动动作。修复负责整理状态，push 仍然是发布动作，手动执行会更稳，也更容易理解这次到底推送了什么。

## 7. 常见问题

### 为什么看不到任务

先执行：

1. `Cmd+Shift+P`
2. 选择 `Tasks: Run Task`
3. 回车后，才会进入真正的任务列表

很多时候看到的是“命令列表”，不是任务列表。


### 为什么 `Submodule: Fix` 适合终端，而不是纯 GUI

因为它本身是交互式脚本，会在终端里逐项询问你要更新主仓库指针、恢复子模块，还是承担本次风险。VS Code task 只是帮你更方便地进入这段交互。
