# SourceTree 使用教程

本文面向使用 SourceTree 操作主仓库的开发者。设计原则是：SourceTree 的 Push 仍然安全地执行只读检查；明确、无需选择的处理可做成 Custom Action；需要判断风险时转到 Terminal 使用交互修复。

## 1. 使用效果

完成安装后，在 SourceTree 中点击 Push 时，Git 会触发治理 `pre-push` hook：

- 状态正常时，push 照常执行。
- 非严格模式下，子模块本地未提交文件、指针不一致、分支不一致、未推送 upstream、已暂存指针等都会显示警告，但不会中断 push。
- 严格模式要求会阻止 push；配置解析错误会按非严格模式只提醒不阻止 push。
- 被阻止时，hook 不会自动 checkout、不创建 commit，也不会在 GUI 流程中要求输入菜单。

因此 SourceTree 不会在一次 Push 操作中暗中更改主仓库历史。

## 2. 前置安装

先在 Terminal 中将治理脚本安装到需要治理的主仓库：

```bash
/path/to/submodule-governance-template/bootstrap.sh /path/to/main-repo
```

如果仓库已经使用 Husky，安装脚本会将治理入口连接到 `.husky/pre-push`；建议团队提交该 hook 文件和 `.submodule-governance.config`。重新 clone 后，每位成员仍需执行一次安装，以生成 `.git/submodule-governance/` 下的本地脚本。

验证安装：

```bash
cd /path/to/main-repo
.git/submodule-governance/submodule-check.sh
```

## 3. 配置 Custom Actions

Atlassian 当前 macOS 文档中的入口为 `SourceTree > Preferences > Custom Actions`。点击 `Add` 添加动作，并勾选显示命令输出的选项，便于查看阻断原因或生成的 commit。

下面的设置使用 SourceTree 提供的 `$REPO` 参数，因此同一组动作可作用于所有已经安装治理脚本的仓库。

### Action A：只读检查

| 设置项 | 值 |
| --- | --- |
| Menu Caption | `Submodule - Check` |
| Script to run | `/bin/bash` |
| Parameters | `-lc 'cd "$1" && exec "$(git rev-parse --git-dir)/submodule-governance/submodule-check.sh"' _ "$REPO"` |

用途：在 push 前主动检查，不修改仓库。

### Action B：接受当前子模块指针

| 设置项 | 值 |
| --- | --- |
| Menu Caption | `Submodule - Accept Current Pointers` |
| Script to run | `/bin/bash` |
| Parameters | `-lc 'cd "$1" && exec "$(git rev-parse --git-dir)/submodule-governance/submodule-accept-pointers.sh"' _ "$REPO"` |

用途：将当前所有满足策略的子模块 HEAD 记录到主仓库，并自动生成一条 conventional commit；不执行 push。该自动 commit 会使用 `--no-verify` 跳过业务仓库本地 commit hooks，避免 SourceTree 操作被项目 Node 依赖或 Husky 状态卡住。

### Action C：同步到主仓库记录的指针

| 设置项 | 值 |
| --- | --- |
| Menu Caption | `Submodule - Sync Recorded Pointers` |
| Script to run | `/bin/bash` |
| Parameters | `-lc 'cd "$1" && exec "$(git rev-parse --git-dir)/submodule-governance/submodule-sync.sh"' _ "$REPO"` |

用途：将子模块 checkout 到当前主仓库已经记录的 SHA。该动作会改变子模块 checkout，请仅在确认不需要保留子模块当前状态后运行。

> 不同 SourceTree 版本的按钮文案可能略有差异；Custom Actions 及 `$REPO` 参数用法以 Atlassian 的 [Using Git in Custom Actions](https://support.atlassian.com/sourcetree/kb/using-git-in-custom-actions/) 为准。

## 4. 日常操作流程

### 场景一：普通提交与推送

1. 在 SourceTree 中提交业务代码。
2. 点击 Push。
3. hook 检查通过后，SourceTree 完成推送。

### 场景二：子模块已有新 commit，需要主仓库接受新指针

1. 在 SourceTree 中点击 `Actions > Custom Actions > Submodule - Check` 查看问题。
2. 确认当前子模块 commit 就是要随主仓库发布的版本。
3. 运行 `Submodule - Accept Current Pointers`。
4. 查看 SourceTree 历史中新增的 `chore(submodule): update ... pointer` 或 `chore(submodule): update pointers` commit。
5. 再次点击 Push。

### 场景三：切换主仓库分支后，子模块应恢复到该分支记录的版本

1. 确认子模块中没有需要保留的未提交内容。
2. 运行 `Submodule - Sync Recorded Pointers`。
3. 运行 `Submodule - Check` 确认状态。
4. 继续日常提交或 push。

### 场景四：需要选择“更新指针还是恢复指针”

SourceTree Action 刻意不提供风险选择菜单。请从该仓库打开 Terminal，然后执行：

```bash
.git/submodule-governance/submodule-fix.sh
```

希望修复后直接推送时执行：

```bash
.git/submodule-governance/submodule-push.sh
```

## 5. 哪些问题不能在 GUI 中自动解决

以下情况 `Accept Current Pointers` 会停止，要求使用终端或先人工处理：

| 情况 | 原因 |
| --- | --- |
| 配置期望分支与当前分支不一致 | 需要判断是否应切分支或承担风险 |
| 严格模式下子模块有未提交内容 | 不能安全生成可发布指针 |
| 严格模式下子模块 commit 未推送 upstream | 远端成员可能拉不到该 commit |
| 子模块指针已经 staged 但未 commit | 严格模式下避免覆盖开发者正在组织的提交；非严格模式只提醒 |
| 子模块未初始化或目录缺失 | 需要先同步/初始化 |

## 6. 团队部署建议

- 将 `.submodule-governance.config` 纳入主仓库 Git 管理。
- 使用 Husky 的项目，将调用治理脚本的 `.husky/pre-push` 纳入 Git 管理。
- 在团队 onboarding 中加入一次 `bootstrap.sh /path/to/main-repo` 安装步骤。
- 对 SourceTree 用户统一发放上述三个 Custom Actions 的配置值。
- 不为 GUI 提供“忽略风险并强行 push”的一键动作；有风险的放行应在终端中明确确认。

## 7. 故障排查

### Custom Action 报脚本不存在

当前仓库尚未安装本地执行脚本，或重新 clone 后未重新安装。重新运行：

```bash
/path/to/submodule-governance-template/bootstrap.sh "$PWD"
```

### Push 没有执行治理检查

在 Terminal 中检查 hook：

```bash
git config --get core.hooksPath
ls -l .git/hooks/pre-push .husky/pre-push 2>/dev/null
```

然后重新执行安装脚本。若目标仓库已有其他自定义 `pre-push` hook，按照安装提示将治理入口合并进去。

### Action 创建了 commit，但仍无法 push

运行 `Submodule - Check` 查看是否仍有严格模式、分支不一致、未初始化或其他子模块问题；需要判断的问题请转入 Terminal 处理。
