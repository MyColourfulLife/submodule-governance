# SourceTree 使用教程

SourceTree 接入也统一使用 Node。Custom Action 调用模板仓库里的 `sourcetree.mjs`，它会根据 SourceTree 传入的仓库路径找到该仓库本地安装的治理 CLI。

## 前置安装

先对目标主仓库安装治理工具：

```bash
node /path/to/submodule-governance-template/bootstrap.mjs /path/to/main-repo
```

确认命令可用：

```bash
cd /path/to/main-repo
node .submodule-governance/cli/submodule-governance.mjs check
```

## Custom Actions

在 SourceTree 的 Custom Actions 中添加动作。`Script to run` 填写 `node`，`Parameters` 填写模板脚本、仓库变量和动作名。

| 动作 | Script to run | Parameters |
| --- | --- | --- |
| Submodule - Check | `node` | `/path/to/submodule-governance-template/sourcetree.mjs $REPO check` |
| Submodule - Accept Current Pointers | `node` | `/path/to/submodule-governance-template/sourcetree.mjs $REPO accept-pointers` |
| Submodule - Sync Recorded Pointers | `node` | `/path/to/submodule-governance-template/sourcetree.mjs $REPO sync` |
| Submodule - Reinstall Hook | `node` | `/path/to/submodule-governance-template/sourcetree.mjs $REPO reinstall-hooks` |

不同 SourceTree 版本的仓库路径变量可能不同；若 `$REPO` 不可用，请替换为该版本提供的当前仓库路径变量或绝对仓库路径。

## 使用建议

- 普通提交前运行 `Submodule - Check`。
- 子模块已有新 commit 且需要主仓库接受时，运行 `Submodule - Accept Current Pointers`。
- 切换主仓库分支后，运行 `Submodule - Sync Recorded Pointers`。
- 需要逐项选择“更新指针、恢复指针、承担风险”时，回到终端执行：

```bash
node .submodule-governance/cli/submodule-governance.mjs fix
```

或：

```bash
node .submodule-governance/cli/submodule-governance.mjs push
```

## 排查

- 报找不到治理 CLI：先对当前仓库重新运行 `bootstrap.mjs`。
- Push 没有触发检查：运行 `Submodule - Reinstall Hook`。
- Custom Action 没有输出：确认 SourceTree 动作勾选了显示命令输出的选项。
