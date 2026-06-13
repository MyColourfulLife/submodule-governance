# Agent MCP 接入教程

MCP server 是治理 CLI 的薄适配层，适合让 Agent 只读检查子模块状态，或在用户确认后执行受控写操作。首发版统一使用 Node.js 18+。

## 安装

```bash
node /path/to/submodule-governance-template/bootstrap.mjs /path/to/main-repo
```

确认本地 CLI 和 MCP server 可用：

```bash
cd /path/to/main-repo
node .submodule-governance/cli/submodule-governance.mjs status --json
node .submodule-governance/cli/submodule-governance-mcp.mjs
```

第二条命令会等待 stdio JSON-RPC 输入；能正常启动即可用 `Ctrl+C` 退出。

## MCP 客户端配置

在支持 stdio MCP 的 Agent 客户端中配置：

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

要求：

- `args` 指向目标主仓库安装出的 MCP server。
- `cwd` 必须是同一个目标主仓库根目录。
- 多个 worktree 或多个主仓库分别配置独立 server 名称。

## Tools

| Tool | 是否修改 | 用途 |
| --- | --- | --- |
| `get_submodule_status` | 否 | 返回与 `status --json` 一致的结构化状态 |
| `check_submodules` | 否 | 执行只读检查 |
| `accept_current_pointers` | 是 | 在允许时接受当前子模块指针并创建主仓库 commit |
| `sync_recorded_pointers` | 是 | 将子模块 checkout 到主仓库记录的 commit |

写工具必须传入 `confirm: true`。没有确认时 server 会拒绝执行。

## 推荐 Agent 流程

只读诊断：

1. 调用 `get_submodule_status`。
2. 调用 `check_submodules`。
3. 向用户解释 dirty、unpushed、mismatch、branch mismatch 等风险。

接受当前子模块版本：

1. 调用 `get_submodule_status` 展示将被接受的指针。
2. 获得用户明确确认。
3. 调用 `accept_current_pointers`，参数包含 `{ "confirm": true }`。
4. 再次调用 `check_submodules` 复查。

恢复到主仓库记录版本：

1. 调用 `get_submodule_status` 确认 mismatch。
2. 获得用户明确确认。
3. 调用 `sync_recorded_pointers`，参数包含 `{ "confirm": true }`。
4. 再次调用 `check_submodules` 复查。

## 安全边界

- MCP 不暴露自动 push。
- MCP 不暴露交互式 `fix`；需要逐项选择时，让用户在终端运行 CLI。
- 严格模式下，未推送子模块 commit、dirty 子模块、分支不一致等仍会阻止写工具。
- MCP 只操作启动 `cwd` 所属仓库；配置路径必须使用绝对路径并清晰命名。
