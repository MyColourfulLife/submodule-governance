# 本地 MCP 服务接入教程

本文面向希望由 Agent 检查或协助处理 submodule 状态的开发者。治理架构采用“CLI 核心 + MCP 薄适配层”：MCP 不自行实现 Git 规则，而是调用与 hook、终端工具相同的状态采集和执行脚本。

## 1. 为什么使用 MCP 接入

CLI 适合开发者和自动化脚本直接调用；MCP 适合 Agent 以明确工具语义调用能力：

- Agent 可以先只读获取状态，而不是猜测 `git status` 输出。
- 写操作通过工具 schema 表达风险，并要求显式确认。
- MCP 不暴露自动 push，避免 Agent 未经允许把提交发送到远端。
- hook、SourceTree、Agent 复用同一套规则，结果一致。

## 2. 安装目标仓库的本地服务

MCP server 会被安装在目标主仓库的本地 `.git` 目录中。先执行：

```bash
/path/to/submodule-governance-template/bootstrap.sh /path/to/main-repo
```

安装后的 server 路径：

```text
/path/to/main-repo/.git/submodule-governance/cli/submodule-governance-mcp.mjs
```

该文件属于本地安装产物，不需要提交到业务仓库；团队共享的治理规则应维护在 `.submodule-governance.config` 中。

前置要求：

- 本机可执行 `node`。
- MCP server 的工作目录必须是需要治理的主仓库根目录。
- 每个需要由 Agent 治理的主仓库分别安装脚本，并配置一个对应的 MCP server。

## 3. 启动前自检

先通过 CLI 验证安装与仓库状态：

```bash
cd /path/to/main-repo
node .git/submodule-governance/cli/submodule-governance.mjs status --json
node .git/submodule-governance/cli/submodule-governance.mjs check
```

也可以手工验证 MCP server 能响应协议请求：

```bash
cd /path/to/main-repo
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"manual-test","version":"0.1"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' |
node .git/submodule-governance/cli/submodule-governance-mcp.mjs
```

输出中应包含 server 名称 `submodule-governance` 以及四个工具。

## 4. 配置支持 stdio MCP 的客户端

在支持本地 stdio MCP server 的 Agent 客户端中，添加类似以下配置。必须将路径替换为本机目标主仓库的绝对路径：

```json
{
  "mcpServers": {
    "submodule-governance-main-repo": {
      "command": "node",
      "args": [
        "/path/to/main-repo/.git/submodule-governance/cli/submodule-governance-mcp.mjs"
      ],
      "cwd": "/path/to/main-repo"
    }
  }
}
```

关键点：

| 配置项 | 说明 |
| --- | --- |
| `command` | 使用本地 Node.js 启动服务 |
| `args` | 指向该主仓库安装出的 MCP server 绝对路径 |
| `cwd` | 必须指向同一个主仓库根目录；工具操作的仓库由此确定 |
| server 名称 | 建议包含项目名，避免同时接入多个仓库时调用错误 |

客户端配置文件的具体位置由所使用的 Agent 产品决定，但 server 的命令、参数及工作目录要求不变。

## 5. 提供的 MCP Tools

| Tool | 是否写入仓库 | 参数 | 用途 |
| --- | --- | --- | --- |
| `get_submodule_status` | 否 | 无 | 返回结构化状态，包括 dirty、pointer mismatch、branch mismatch 等 |
| `check_submodules` | 否 | 无 | 执行与 `pre-push` 相同的只读策略检查 |
| `accept_current_pointers` | 是 | `{"confirm": true}` | 接受全部符合策略的当前子模块指针，并创建一条主仓库 commit |
| `sync_recorded_pointers` | 是 | `{"confirm": true}` | 将子模块 checkout 到主仓库记录的 commit |

`accept_current_pointers` 和 `sync_recorded_pointers` 在缺少 `confirm: true` 时会返回错误，不会修改仓库。

MCP 当前有意不暴露下列能力：

- 交互式 `fix`：选项需要开发者在终端理解风险后作出判断。
- 自动 `push`：向远端发送提交属于独立决策，应由开发者确认后执行。
- 强制绕过检查：避免 Agent 将风险确认简化为无感操作。

## 6. 推荐 Agent 工作流

### 只读诊断

向 Agent 发出类似请求：

```text
请使用 submodule-governance-main-repo 的 get_submodule_status 检查当前子模块状态，只报告问题，不修改仓库。
```

Agent 应先调用 `get_submodule_status`，需要验证是否允许 push 时再调用 `check_submodules`。

### 接受明确的新子模块版本

推荐交互步骤：

1. Agent 调用 `get_submodule_status` 并说明有哪些 pointer mismatch。
2. Agent 告知接受指针会创建主仓库 commit 以及对应子模块 SHA 变化。
3. 开发者明确同意更新。
4. Agent 调用 `accept_current_pointers`，传入 `{"confirm": true}`。
5. Agent 再调用 `check_submodules`，报告修复结果。
6. 开发者自行决定何时执行 `git push`。

### 将本地子模块恢复到主仓库记录状态

推荐交互步骤：

1. Agent 调用 `get_submodule_status`。
2. Agent 明确提示同步动作会改变子模块 checkout，并确认是否存在需保留的工作内容。
3. 开发者同意后，Agent 调用 `sync_recorded_pointers`，传入 `{"confirm": true}`。
4. Agent 调用 `check_submodules` 验证结果。

## 7. 安全边界

- MCP server 仅操作其启动 `cwd` 所属的主仓库；配置错 `cwd` 会操作错误项目，因此必须使用绝对路径并清晰命名 server。
- 写操作只在显式确认后执行，但确认前 Agent 仍应向用户展示将修改什么。
- 非严格模式下接受 pointer 时，子模块未提交文件不会进入主仓库 commit；Agent 应在状态中发现 `dirty` 后提醒用户。
- 严格模式下，dirty 子模块或未推送 upstream 的子模块 commit 会阻止自动接受。
- MCP 生成的主仓库 commit 仍会经过仓库本身的 commit hooks，例如 commitlint。

## 8. 更新与排查

治理模板更新后，重新安装即可更新目标仓库中的 CLI 与 MCP server：

```bash
/path/to/submodule-governance-template/bootstrap.sh /path/to/main-repo
```

常用诊断：

```bash
cd /path/to/main-repo

# 确认 server 文件存在。
ls -l .git/submodule-governance/cli/submodule-governance-mcp.mjs

# 确认 CLI 可以读取治理状态。
node .git/submodule-governance/cli/submodule-governance.mjs status --json

# 确认配置文件语法可由 Git 读取。
git config --file .submodule-governance.config --list
```

若 Agent 报告找不到工具，优先检查 MCP 客户端配置中的 `args` 与 `cwd` 是否指向同一个、已经安装治理脚本的主仓库。
