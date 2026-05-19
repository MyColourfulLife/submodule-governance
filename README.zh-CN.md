# 子模块治理模板（Submodule Governance Template）

这是一个可复用模板，用于给现有主仓库快速接入本地 Git Submodule 治理能力。执行 `bootstrap.sh` 后，会默认安装 `pre-push` hook；日常开发者正常使用 `git push` 即可，hook 会在 push 前自动检查子模块状态。

## 项目背景

很多业务项目由一个主仓库和多个 Git Submodule 子仓库组成。例如 `rn_module` 主仓库下面挂载 `ios` 和 `android` 两个子模块。

随着业务变多，feature 分支也会变多，常见问题是：主仓库切到了某个业务分支，但本地子模块没有同步到主仓库记录的 commit；或者子模块已经提交了新 commit，但主仓库忘记提交子模块指针，导致其他人拉主仓库后拿不到正确版本。

Git Submodule 的本质是：主仓库记录的是子模块的某个具体 commit，而不是“自动跟随某个分支”。所以子模块治理的核心是保证主仓库记录的子模块 commit、开发者本地子模块 checkout 状态、子模块远端可获取状态三者一致。

## 为什么需要治理

只依赖人肉流程，通常会有这些弊端：

- 开发者容易在切换主仓库分支后忘记执行 `git submodule update --init --recursive`。
- 子模块已经提交，但主仓库忘记执行 `git add <submodule>` 并提交指针变化。
- 主仓库可能引用了别人拉不到的子模块 commit。
- 合并 feature 分支时，子模块指针变化不明显，容易被忽略。
- 问题经常到别人拉代码、CI 构建或联调时才暴露，修复成本更高。

这个模板的目标不是替代 Git Submodule，而是把关键检查前置到本地 `git push` 之前，把容易遗漏的人肉步骤变成自动检查和明确提示。

## 兼容性说明

- 已在 macOS/Linux 的 shell 环境中验证。
- 尚未在 Windows 环境中验证。

## 核心功能

- `git push` 前自动检查：安装后默认写入 `.git/hooks/pre-push`，开发者日常不需要手动执行检查脚本。
- 子模块未初始化或目录缺失时阻止 push，并提示执行 `.git/submodule-governance/submodule-sync.sh` 自动同步。
- 子模块有未提交改动时阻止 push，避免本地脏状态混入主仓库判断。
- 子模块 HEAD 和主仓库记录的 gitlink commit 不一致时弹出中文修复菜单，可选择更新主仓库指针、恢复子模块或跳过。
- 主仓库已经 `git add <submodule>` 但还没 commit 时阻止 push。
- 子模块 commit 未推送到上游时，默认只警告；开启严格模式后会阻止 push。
- 提供 `.git/submodule-governance/submodule-sync.sh`，用于一键执行 `git submodule sync --recursive` 和 `git submodule update --init --recursive`。

## 模板会安装哪些文件

- `.git/submodule-governance/submodule-check.sh`
- `.git/submodule-governance/submodule-sync.sh`
- `.git/submodule-governance/pre-push-hook.sh`
- `.git/submodule-governance/install-hooks.sh`
- `.submodule-governance.env`
- `.git/hooks/pre-push`（由脚本自动安装）

默认不会在目标主仓库生成 `scripts/` 目录，也不会覆盖目标仓库已有的 `scripts/` 文件。

## 是否需要纳入主项目 Git 管理

默认不需要把治理脚本纳入目标主仓库的 Git 管理。治理脚本会安装到 `.git/submodule-governance/`，这个目录属于本地 Git 元数据，不会被业务仓库提交。

建议纳入目标主仓库 Git 管理的是 `.submodule-governance.env`，因为它决定团队是否启用严格模式。这样团队成员拿到主仓库后，执行一次 `bootstrap.sh` 即可得到一致的本地 hook 行为。

## 推荐接入方式

建议把本仓库作为独立的治理模板仓库维护。其他项目需要接入时，先拉取本仓库，然后对目标主仓库执行 `bootstrap.sh`。

## 安装到当前仓库

在目标主仓库中执行：

```bash
/path/to/submodule-governance-template/bootstrap.sh .
```

## 安装到另一个已有仓库路径

```bash
/path/to/submodule-governance-template/bootstrap.sh /path/to/target-repo
```

安装完成后，目标仓库已经具备 push 前自动检查能力。

## 严格模式

安装时开启严格模式：

```bash
/path/to/submodule-governance-template/bootstrap.sh /path/to/target-repo --strict
```

安装后也可以通过修改 `.submodule-governance.env` 切换：

```bash
SUBMODULE_REQUIRE_PUSHED=1
```

如果希望非严格模式：

```bash
SUBMODULE_REQUIRE_PUSHED=0
```

## 目标仓库中的日常使用

正常情况下，开发者不需要手动执行检查脚本。只要正常 `git push`，`pre-push` hook 会自动运行检查。

如果切分支、拉取代码后发现子模块未同步，或 hook 提示子模块未初始化/目录缺失，可以执行：

```bash
.git/submodule-governance/submodule-sync.sh
```

它会自动同步子模块 URL 和主仓库记录的子模块 commit。

如果想在 push 前主动检查，也可以手动执行：

```bash
.git/submodule-governance/submodule-check.sh
```

如果 hook 丢失，可重新安装：

```bash
.git/submodule-governance/install-hooks.sh
```

## 关键防护场景

当子模块已经有新的 commit，但主仓库没有更新子模块指针时，
主仓库执行 `git push` 会弹出修复菜单：

```text
当前子模块 'ios' 与主仓库记录不一致：
  子模块当前 commit：<current_commit>
  主仓库记录 commit：<recorded_commit>

请选择修复方式：
  [1] 将主仓库指针更新到当前 'ios' commit
  [2] 将 'ios' 恢复到主仓库记录的 commit
  [3] 我已了解风险，继续 push
```

选择 `[1]` 会自动执行 `git add <submodule_path>` 并生成主仓库 commit，用于更新子模块指针。修复完成后会提示：

```text
已修复：主仓库子模块指针已更新并生成 commit（<commit_sha> Update <submodule_path> submodule pointer，<submodule_path>: <old_commit> -> <new_commit>）。
问题已修复：
  [y] 自动 push
  [n] 手动 push
请输入选项 [y/n]:
```

选择 `[y]` 会自动执行 `git push --no-verify`，避免 hook 递归触发；选择 `[n]` 会停止本次 push，开发者确认后手动执行 `git push`。

选择 `[2]` 会将子模块 checkout 回主仓库记录的 commit，适用于本地子模块误切到其他 commit 的情况。修复完成后同样会询问自动 push 或手动 push。

选择 `[3]` 不做修改，并继续本次 push。此时主仓库远端仍然记录旧的子模块 commit，其他人拉取主仓库后不会自动拿到你本地当前的子模块 commit。

也就是说，正确流程是：先在子模块仓库提交并推送代码，再回到主仓库提交子模块指针变化。这个模板会帮助开发者在忘记第二步时及时发现，并给出可选择的修复动作。

如果脚本运行在非交互环境（例如 CI 或管道），不会弹菜单，会直接输出中文错误并阻止。
