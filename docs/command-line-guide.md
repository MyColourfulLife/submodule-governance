# 命令行使用教程

本文面向在 Terminal 中开发和推送代码的成员。命令行模式提供完整的交互修复能力：先集中检查所有子模块问题，再按选择统一生成主仓库 commit，最后由你决定是否 push。

## 适用场景

- 日常开发主要通过 `git` 命令操作。
- 需要逐个判断子模块指针应当更新还是恢复。
- 需要在一次流程中处理多个子模块问题，并生成一条汇总 commit。
- 需要在明知风险的情况下，由开发者明确确认后继续 push。

## 1. 安装

在目标主仓库中执行模板的安装脚本：

```bash
/path/to/submodule-governance-template/bootstrap.sh /path/to/main-repo
```

严格模式安装：

```bash
/path/to/submodule-governance-template/bootstrap.sh /path/to/main-repo --strict
```

安装后，主仓库中可见的团队配置文件为：

```text
.submodule-governance.config
```

本地执行脚本被安装到 Git 元数据目录中：

```text
.git/submodule-governance/
```

建议将 `.submodule-governance.config` 纳入主仓库版本管理。普通 Git hook 位于本地 `.git/hooks/`，切换分支无需重新安装；若项目使用 Husky，则应将生成或接入后的 `.husky/pre-push` 纳入团队分支。

## 2. 配置治理规则

默认配置为非严格模式：

```ini
[governance]
    requirePushed = false
    # mainBranch = main

# [submodule "ios"]
#     branch = dev/v2.2.7/stable
```

常用配置命令：

```bash
cd /path/to/main-repo

# 要求子模块 commit 必须已推送到 upstream，且子模块不能有未提交改动。
git config --file .submodule-governance.config governance.requirePushed true

# 配置主仓库期望分支。
git config --file .submodule-governance.config governance.mainBranch dev/v11.0.22/stable

# 配置子模块期望分支；ios 必须是 .gitmodules 中的 path。
git config --file .submodule-governance.config submodule.ios.branch dev/v11.0.22/stable
```

不配置 `mainBranch` 或子模块 `branch` 时，不检查相应分支。配置语法损坏、`requirePushed` 不是合法布尔值、或配置了不存在的子模块路径时，`pre-push` 会按非严格模式只提醒不阻止 push。

## 3. 推荐日常流程

### 推送前主动检查

```bash
cd /path/to/main-repo
.git/submodule-governance/submodule-check.sh
```

该命令只读，不会修改分支、checkout、暂存区或 commit 历史。普通 `git push` 触发的 `pre-push` hook 运行的就是相同检查。

### 非严格模式下推送

```bash
git push
```

默认非严格模式下，子模块 dirty、未推送、指针不一致、分支不一致、已暂存指针、未初始化等都会给出提醒，但不会阻止本次 push。提醒的目的只是让你知道这次 push 不一定包含本地看到的子模块状态。

### 检查提示指针或分支不一致时

如果你希望在 push 前顺手修好这些提醒，可以运行完整终端流程：

```bash
.git/submodule-governance/submodule-push.sh
```

该命令会先进入交互修复，处理完成后再执行 `git push`。如果你只想修复而暂时不 push，执行：

```bash
.git/submodule-governance/submodule-fix.sh
```

## 4. 交互修复如何工作

当多个子模块 HEAD 与主仓库记录的 commit 不一致时，脚本会先列出全部问题，然后依次询问每个子模块：

```text
[1] 将主仓库指针更新到当前 commit
[2] 将子模块恢复到主仓库记录的 commit
[3] 保持不一致并承担本次风险
[4] 取消
```

选择含义：

| 选择 | 修改行为 | 后续结果 |
| --- | --- | --- |
| 更新主仓库指针 | 对该子模块执行 `git add` | 全部选择结束后统一创建一条 `chore(submodule): ...` commit |
| 恢复子模块 | 将干净的子模块 checkout 到主仓库记录的 SHA | 不为该恢复操作创建主仓库 pointer commit |
| 承担风险 | 不修改该不一致状态 | 仅通过 `submodule-push.sh` 才会以本次明确确认方式继续 push |
| 取消 | 不执行待应用修复 | 本次流程结束，不 push |

如果存在配置分支不一致，修复脚本会先要求选择切换到配置分支、承担本次风险或取消。自动切换分支前会保护主仓库及子模块已有改动，不能安全切换时会停止。

治理脚本自动生成的 pointer commit 会使用固定的 conventional commit message，并通过 `--no-verify` 跳过业务仓库本地 commit hooks。这样可以避免因为项目 `node_modules` 缺失、格式检查脚本不可用或 Husky 版本提示导致子模块治理流程被卡住。

如果你执行过 `git reset --soft`，子模块指针可能已经处于 staged 状态。再次运行 `submodule-fix.sh` 或 `submodule-accept-pointers.sh` 时，脚本会把这些已暂存指针直接纳入本次治理 commit，不会要求你先手动处理暂存区。

## 5. 常见状态及处理

### 子模块未初始化或目录缺失

```bash
.git/submodule-governance/submodule-sync.sh
```

该命令会执行 `git submodule sync --recursive` 与 `git submodule update --init --recursive`，使本地子模块回到主仓库已记录的 commit。

非严格模式下，这类问题只提醒不阻止 push；严格模式下会阻止。

### 子模块有未提交内容

- 非严格模式：检查只警告。更新主仓库指针时，子模块工作区内尚未 commit 的文件不会被包含进去。
- 严格模式：检查阻止 push 和自动接受指针，请先在子模块中提交、暂存方案外处理或还原改动。

### 子模块有新 commit，但主仓库尚未记录

执行：

```bash
.git/submodule-governance/submodule-push.sh
```

在菜单中选择更新主仓库指针。多个子模块同时更新时，只生成一条汇总 commit。

### 子模块 commit 尚未推送到 upstream

- 非严格模式：输出警告，可以继续处理和推送主仓库。
- 严格模式：先进入对应子模块完成 `git push`，主仓库检查才会通过。

### 已经暂存子模块指针但尚未 commit

非严格模式下只提醒，不阻止 push。运行 `submodule-fix.sh` 或 `submodule-accept-pointers.sh` 时，已暂存的子模块指针会直接纳入治理 commit。

## 6. 命令参考

| 命令 | 是否修改仓库 | 用途 |
| --- | --- | --- |
| `.git/submodule-governance/submodule-check.sh` | 否 | 只读检查，与 hook 一致 |
| `.git/submodule-governance/submodule-fix.sh` | 可能 | 交互修复，不自动 push |
| `.git/submodule-governance/submodule-push.sh` | 可能 | 交互修复完成后执行 push |
| `.git/submodule-governance/submodule-accept-pointers.sh` | 是 | 无交互地接受全部可接受指针并创建 commit |
| `.git/submodule-governance/submodule-sync.sh` | 是 | checkout 到主仓库记录的子模块 commit |
| `.git/submodule-governance/uninstall.sh` | 是 | 卸载本地治理脚本和模板生成的 hook |
| `node .git/submodule-governance/cli/submodule-governance.mjs status --json` | 否 | 输出适合工具消费的治理状态 |

## 7. 卸载

在已经安装过的目标仓库中执行：

```bash
.git/submodule-governance/uninstall.sh
```

也可以从模板仓库执行：

```bash
/path/to/submodule-governance-template/uninstall.sh /path/to/main-repo
```

卸载行为：

- 移除本地 `.git/submodule-governance/` 工具目录。
- 只自动删除模板生成的 `pre-push` hook。
- 如果 `pre-push` hook 中包含其他自定义逻辑，脚本会保留文件并提示手动删除治理调用行。
- 默认保留 `.submodule-governance.config`，避免误删团队配置。

如需连配置文件一起删除：

```bash
/path/to/submodule-governance-template/uninstall.sh /path/to/main-repo --remove-config
```

## 8. 什么时候重新安装

以下情况需要重新运行 `bootstrap.sh`：

- 首次接入治理脚本。
- 重新 clone 后需要安装本地 hook 和执行脚本。
- 治理模板升级后，需要将新脚本部署到目标仓库。
- hook 被删除、替换，或者项目调整了 `core.hooksPath`。

仅仅切换已经包含团队 hook 配置的业务分支，不需要重新安装。
