# 子模块治理模板

这是一个给现有 Git Submodule 主仓库接入本地治理能力的模板。首发版统一使用 Node.js 18+：安装、卸载、命令行、SourceTree、VS Code 和 MCP 都走同一套 Node CLI。

## 视频教程

- [操作说明](docs/操作说明.mp4)
- [通过 MCP 使用](docs/通过MCP使用.mp4)

## 安装

```bash
node /path/to/submodule-governance-template/bootstrap.mjs /path/to/main-repo
```

严格模式会阻止包含高风险子模块状态的 push：

```bash
node /path/to/submodule-governance-template/bootstrap.mjs /path/to/main-repo --strict
```

安装后目标仓库会生成：

- `.submodule-governance/cli/submodule-governance.mjs`：日常 CLI 入口
- `.submodule-governance/cli/submodule-governance-mcp.mjs`：本地 MCP server
- `.submodule-governance.config`：团队配置文件，建议提交到主仓库
- `pre-push` hook：push 前只读检查，不会修改工作区

## 常用命令

在目标主仓库根目录执行：

```bash
node .submodule-governance/cli/submodule-governance.mjs check
node .submodule-governance/cli/submodule-governance.mjs status --json
node .submodule-governance/cli/submodule-governance.mjs fix
node .submodule-governance/cli/submodule-governance.mjs push
node .submodule-governance/cli/submodule-governance.mjs sync
node .submodule-governance/cli/submodule-governance.mjs accept-pointers
```

卸载：

```bash
node /path/to/submodule-governance-template/uninstall.mjs /path/to/main-repo
node /path/to/submodule-governance-template/uninstall.mjs /path/to/main-repo --remove-config
```

## 配置

`.submodule-governance.config` 使用 Git config 格式：

```ini
[governance]
    requirePushed = false
    # mainBranch = main

# [submodule "ios"]
#     branch = dev/v2.2.7/stable
```

- `governance.requirePushed = false`：非严格模式，只提醒风险。
- `governance.requirePushed = true`：严格模式，未推送子模块 commit、dirty 子模块、指针不一致、分支不一致等会阻止 push。
- `governance.mainBranch`：主仓库期望分支，不配置则不检查。
- `submodule "<path>".branch`：子模块期望分支，`<path>` 必须与 `.gitmodules` 中的 path 一致。

## 文档入口

- [命令行使用教程](docs/command-line-guide.md)
- [SourceTree 使用教程](docs/sourcetree-guide.md)
- [VS Code 集成教程](docs/vscode-guide.md)
- [Agent MCP 接入教程](docs/agent-mcp-guide.md)

## 安全边界

- `git push` 触发的 hook 只读检查，不创建 commit、不 checkout、不修改配置。
- `fix` 和 `push` 是交互命令，会在修改前让开发者选择处理方式。
- `accept-pointers` 会创建主仓库 commit，用于明确接受当前子模块指针。
- MCP 不暴露自动 push；写工具必须传入 `confirm: true`。
- 首发版不兼容旧入口；模板更新后重新运行 `bootstrap.mjs` 即可覆盖本地安装。

## 集成测试

```bash
node submodule-governance-template/tests/integration-submodule-governance.mjs
```

保留临时测试仓库：

```bash
KEEP_SUBMODULE_GOVERNANCE_TEST_TMP=1 node submodule-governance-template/tests/integration-submodule-governance.mjs
```
