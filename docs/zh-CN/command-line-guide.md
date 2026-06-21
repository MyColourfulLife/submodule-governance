# 命令行使用教程

本文面向直接在终端、脚本或 CI 中使用子模块治理能力的开发者。首发版统一使用 Node.js 18+，macOS 和 Windows 命令一致。

## 安装

```bash
node /path/to/submodule-governance-template/bootstrap.mjs /path/to/main-repo
```

开启严格模式：

```bash
node /path/to/submodule-governance-template/bootstrap.mjs /path/to/main-repo --strict
```

安装完成后进入目标主仓库：

```bash
cd /path/to/main-repo
node .submodule-governance/cli/submodule-governance.mjs check
```

## 日常流程

推送前主动检查：

```bash
node .submodule-governance/cli/submodule-governance.mjs check
```

需要交互处理时：

```bash
node .submodule-governance/cli/submodule-governance.mjs fix
```

希望修复完成后继续 push：

```bash
node .submodule-governance/cli/submodule-governance.mjs push
```

切换主仓库分支后，将子模块恢复到主仓库记录的 commit：

```bash
node .submodule-governance/cli/submodule-governance.mjs sync
```

确认当前子模块 HEAD 就是要发布的版本，并生成主仓库指针 commit：

```bash
node .submodule-governance/cli/submodule-governance.mjs accept-pointers
```

## 命令参考

| 命令 | 是否修改工作区 | 用途 |
| --- | --- | --- |
| `check` | 否 | 执行与 push hook 一致的只读检查 |
| `status` | 否 | 输出人类可读摘要 |
| `status --json` | 否 | 输出适合脚本、CI、Agent 消费的 JSON |
| `state` | 否 | 输出 TSV 状态，主要用于测试或轻量脚本 |
| `fix` | 可能 | 交互处理分支或子模块指针不一致 |
| `push` | 可能 | 先交互处理，再执行 `git push` |
| `sync` | 是 | 执行 submodule sync/update，恢复到主仓库记录的 commit |
| `accept-pointers` | 是 | 接受当前子模块指针并创建主仓库 commit |
| `install-hooks` | 是 | 重新安装 `pre-push` hook |
| `uninstall` | 是 | 卸载本地治理工具，默认保留配置文件 |

完整形式：

```bash
node .submodule-governance/cli/submodule-governance.mjs <command>
```

## JSON 状态

```bash
node .submodule-governance/cli/submodule-governance.mjs status --json
```

主要字段：

| 字段 | 含义 |
| --- | --- |
| `requirePushed` | 是否严格模式 |
| `submodules` | `.gitmodules` 中声明的子模块路径 |
| `missing` | 未初始化或目录缺失的子模块 |
| `dirty` | 有未提交内容的子模块 |
| `unpushed` | 当前 HEAD 尚未推送到 upstream 的子模块 |
| `mismatches` | 子模块 HEAD 与主仓库记录的 gitlink 不一致 |
| `branchMismatches` | 当前分支与配置分支不一致 |
| `stagedPointers` | 已暂存但尚未提交的子模块指针 |
| `configErrors` | 配置文件语法或内容错误 |

## 配置

配置文件位于目标主仓库根目录：

```bash
.submodule-governance.config
```

示例：

```ini
[governance]
    requirePushed = true
    mainBranch = main

[submodule "ios"]
    branch = main
```

可以用 Git 修改：

```bash
git config --file .submodule-governance.config governance.requirePushed true
git config --file .submodule-governance.config governance.mainBranch main
git config --file .submodule-governance.config submodule.ios.branch main
```

## 卸载

```bash
node /path/to/submodule-governance-template/uninstall.mjs /path/to/main-repo
```

同时删除配置：

```bash
node /path/to/submodule-governance-template/uninstall.mjs /path/to/main-repo --remove-config
```
