# CLI 使用教程

本文面向希望通过稳定命令入口或结构化 JSON 使用子模块治理能力的开发者。它和“命令行交互使用”不是一回事：命令行交互脚本更适合人直接操作，CLI 更适合脚本、CI、编辑器任务和 Agent 适配层调用。

## 1. CLI 是什么

安装后，CLI 位于目标仓库本地 Git 元数据目录：

```text
.git/submodule-governance/cli/submodule-governance.mjs
```

CLI 不重新实现治理规则，它复用与 hook、SourceTree、VS Code 任务相同的底层脚本。

## 2. 安装

先在目标主仓库执行：

```bash
/path/to/submodule-governance-template/bootstrap.sh /path/to/main-repo
```

进入目标仓库后验证：

```bash
cd /path/to/main-repo
node .git/submodule-governance/cli/submodule-governance.mjs status
```

## 3. 命令参考

| 命令 | 是否修改仓库 | 用途 |
| --- | --- | --- |
| `status` | 否 | 输出人类可读的状态摘要 |
| `status --json` | 否 | 输出结构化 JSON，适合脚本和 Agent 读取 |
| `check` | 否 | 执行与 `pre-push` 一致的只读检查 |
| `accept-pointers` | 是 | 接受当前子模块指针并生成主仓库 commit |
| `sync` | 是 | 将子模块 checkout 到主仓库记录的 commit |
| `fix` | 可能 | 调用交互修复脚本 |
| `push` | 可能 | 调用交互修复后再 push 的封装流程 |

推荐自动化优先使用 `status --json` 和 `check`；涉及写入的命令应由用户确认后再执行。

## 4. 常用示例

只读查看摘要：

```bash
node .git/submodule-governance/cli/submodule-governance.mjs status
```

获取 JSON：

```bash
node .git/submodule-governance/cli/submodule-governance.mjs status --json
```

执行 hook 同款检查：

```bash
node .git/submodule-governance/cli/submodule-governance.mjs check
```

接受当前指针：

```bash
node .git/submodule-governance/cli/submodule-governance.mjs accept-pointers
```

同步到主仓库记录指针：

```bash
node .git/submodule-governance/cli/submodule-governance.mjs sync
```

## 5. JSON 输出结构

`status --json` 会返回类似结构：

```json
{
  "requirePushed": false,
  "configFile": ".submodule-governance.config",
  "configErrors": [],
  "submodules": ["ios", "android", "libs"],
  "missing": [],
  "dirty": ["android"],
  "noUpstream": ["ios"],
  "unpushed": [],
  "stagedPointers": [],
  "mismatches": [
    {
      "path": "ios",
      "recorded": "0af5c1d0...",
      "current": "36fe975..."
    }
  ],
  "branchMismatches": []
}
```

字段含义：

| 字段 | 含义 |
| --- | --- |
| `requirePushed` | 是否启用严格模式 |
| `configErrors` | 配置读取或校验问题 |
| `missing` | 未初始化或目录缺失的子模块 |
| `dirty` | 子模块内部存在未提交内容 |
| `noUpstream` | 子模块当前分支未配置 upstream |
| `unpushed` | 子模块 HEAD 尚未推送到 upstream |
| `stagedPointers` | 主仓库中已暂存但未提交的子模块指针 |
| `mismatches` | 子模块当前 HEAD 与主仓库记录不一致 |
| `branchMismatches` | 当前分支与配置分支不一致 |

## 6. 建议用法

脚本或 Agent 外壳建议按这个顺序：

1. 先运行 `status --json` 获取状态。
2. 只读判断可继续运行 `check`。
3. 写操作前向用户展示将修改的内容。
4. 用户确认后再执行 `accept-pointers` 或 `sync`。
5. 不建议自动执行 `push`；推送仍由开发者手动确认。

## 7. CLI 与其他入口的关系

| 入口 | 面向对象 | 特点 |
| --- | --- | --- |
| shell 脚本 | 开发者 | 中文提示、交互菜单、最适合终端手动操作 |
| CLI | 脚本和自动化 | 稳定命令入口、支持 JSON 状态 |
| MCP | Agent | 通过工具 schema 暴露能力，并要求写操作显式确认 |

CLI 是 MCP 的基础能力之一，但 CLI 本身不等于 Agent 接入。
