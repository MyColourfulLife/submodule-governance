# 子模块治理模板（Submodule Governance Template）

这是一个可复用模板，用于给现有主仓库快速接入本地 Git Submodule 治理能力。执行 `bootstrap.sh` 后，会默认安装只读的 `pre-push` 检查 hook；需要交互修复时，通过治理命令在终端完成。

## 使用文档入口

根据团队成员的操作方式选择教程：

| 使用方式 | 适合对象 | 教程 |
| --- | --- | --- |
| 命令行交互 | 使用 Terminal 完成检查、修复与推送的开发者 | [命令行使用教程](docs/command-line-guide.md) |
| SourceTree | 使用 GUI 推送，并通过 Custom Actions 处理明确操作的开发者 | [SourceTree 使用教程](docs/sourcetree-guide.md) |
| 本地 MCP 服务 | 希望由 Agent 只读检查或在确认后执行受控修复的开发者 | [本地 MCP 服务接入教程](docs/local-mcp-guide.md) |

三种入口复用同一套治理规则：hook 始终只读；产生 commit、切换子模块 checkout 或调用 Agent 写工具的操作都需要明确触发。

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

- `git push` 前只读自动检查：hook 只报告风险或阻止 push，不会在 push 过程中修改工作区或创建 commit。
- 终端交互修复与推送：`.git/submodule-governance/submodule-push.sh` 会处理全部子模块选择、汇总生成 commit 后执行 push。
- 子模块未初始化或目录缺失时阻止 push，并提示执行 `.git/submodule-governance/submodule-sync.sh` 自动同步。
- 子模块有未提交改动时，非严格模式会警告这些内容不会包含在主仓库指针 commit 中；严格模式会阻止 push。
- 子模块 HEAD 和主仓库记录的 gitlink commit 不一致时，hook 提示使用修复命令；终端修复命令提供中文菜单，可选择更新主仓库指针、恢复子模块、了解风险继续 push 或取消。
- 如果 `.submodule-governance.config` 配置了期望分支，会先检查主仓库和子模块分支是否一致。
- 主仓库已经 `git add <submodule>` 但还没 commit 时阻止 push。
- 子模块 commit 未推送到上游时，默认只警告；开启严格模式后会阻止 push。
- 提供 `.git/submodule-governance/submodule-sync.sh`，用于一键执行 `git submodule sync --recursive` 和 `git submodule update --init --recursive`。

## 模板会安装哪些文件

- `.git/submodule-governance/submodule-check.sh`
- `.git/submodule-governance/submodule-fix.sh`
- `.git/submodule-governance/submodule-push.sh`
- `.git/submodule-governance/submodule-accept-pointers.sh`
- `.git/submodule-governance/submodule-state.sh`
- `.git/submodule-governance/cli/submodule-governance.mjs`
- `.git/submodule-governance/cli/submodule-governance-mcp.mjs`
- `.git/submodule-governance/submodule-sync.sh`
- `.git/submodule-governance/pre-push-hook.sh`
- `.git/submodule-governance/install-hooks.sh`
- `.submodule-governance.config`（默认生成，建议由主仓库维护并纳入 Git 管理）
- 当前生效的 `pre-push` hook（普通仓库为 `.git/hooks/pre-push`，Husky 仓库为 `.husky/pre-push`）

默认不会在目标主仓库生成 `scripts/` 目录，也不会覆盖目标仓库已有的 `scripts/` 文件。

## 是否需要纳入主项目 Git 管理

默认不需要把治理脚本纳入目标主仓库的 Git 管理。治理脚本会安装到 `.git/submodule-governance/`，这个目录属于本地 Git 元数据，不会被业务仓库提交。

建议纳入目标主仓库 Git 管理的是 `.submodule-governance.config`，因为它同时决定团队是否启用严格模式，以及主仓库与子模块的分支规划。这样团队成员拿到主仓库后，执行一次 `bootstrap.sh` 即可得到一致的本地 hook 行为。

## 统一配置文件

`bootstrap.sh` 会在主仓库根目录生成 Git config 格式的 `.submodule-governance.config`：

```ini
[governance]
    # false: only warn when submodule HEAD is not pushed to upstream.
    # true: fail and block push when submodule HEAD is not pushed to upstream.
    requirePushed = false
    # mainBranch = main

# subsection 名称必须与 .gitmodules 中的子模块路径一致。
# [submodule "ios"]
#     branch = dev/v2.2.7/stable
#
# [submodule "android"]
#     branch = dev/v2.2.7/stable
```

含义：

- `governance.requirePushed` 表示是否开启严格模式，`true` 会在子模块 HEAD 未推送到 upstream 或子模块存在未提交内容时阻止 push。
- `governance.mainBranch` 表示主仓库期望分支；不配置时不检查主仓库分支。
- `submodule "<path>".branch` 表示子模块期望分支，`<path>` 必须和 `.gitmodules` 中的路径一致。
- 子模块默认 remote 为 `origin`。
- 默认不配置任何分支，不启用分支检查。

配置也可以通过 Git 命令修改，例如：

```bash
git config --file .submodule-governance.config governance.mainBranch dev/v2.2.7/stable
git config --file .submodule-governance.config submodule.ios.branch dev/v2.2.7/stable
```

`git push` 前会优先执行分支匹配检查：

```text
分支匹配检查：

主仓库：
  当前分支：feature/test
  配置分支：dev/v2.2.7/stable
  状态：不一致

子模块：
  ios:
    当前分支：feature/ios-test
    配置分支：dev/v2.2.7/stable
    状态：不一致
```

如果分支不一致，会先展示风险说明，再给出菜单：

```text
请选择处理方式：
  [1] 根据配置文件将分支处理到一致状态
  [2] 取消，终止操作
  [3] 我已了解风险，强制继续 push
```

选择 `[1]` 会根据配置切换主仓库和子模块分支；子模块会执行 `fetch origin` 和 `pull --ff-only origin <branch>`，然后继续后续子模块 pointer 检查。

选择 `[2]` 会终止流程并阻止本次 push。

选择 `[3]` 会直接放行本次 push，并跳过后续所有子模块检查。

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

安装后也可以通过 Git config 命令切换：

```bash
git config --file .submodule-governance.config governance.requirePushed true
```

如果希望非严格模式：

```bash
git config --file .submodule-governance.config governance.requirePushed false
```

## 目标仓库中的日常使用

正常情况下，开发者可以正常执行 `git push`，`pre-push` hook 会只读运行检查。如果检查提示子模块指针或配置分支不一致，可在终端执行治理 push 命令：

```bash
.git/submodule-governance/submodule-push.sh
```

它会先提供修复菜单，完成修复并生成汇总 commit 后再执行 `git push`。

普通 Git hook 安装在本地 Git 元数据中，切换业务分支不需要重新安装。使用 Husky 时，`.husky/pre-push` 属于仓库文件，建议将它随 `.submodule-governance.config` 一起纳入 Git 管理并合并到需要治理的分支；分支已经包含该 hook 后，也无需每次切换都重新安装。重新克隆仓库、删除/替换 hook、修改 `core.hooksPath`，或需要更新已安装的治理脚本版本时，应重新运行 `bootstrap.sh`。

如果切分支、拉取代码后发现子模块未同步，或 hook 提示子模块未初始化/目录缺失，可以执行：

```bash
.git/submodule-governance/submodule-sync.sh
```

它会自动同步子模块 URL 和主仓库记录的子模块 commit。

如果想在 push 前主动进行只读检查，可以手动执行：

```bash
.git/submodule-governance/submodule-check.sh
```

如果只想交互修复而暂不 push，可以执行：

```bash
.git/submodule-governance/submodule-fix.sh
```

如果 hook 丢失，可重新安装：

```bash
.git/submodule-governance/install-hooks.sh
```

如果目标仓库已有自定义 `pre-push` hook，安装脚本不会直接覆盖它，而会提示将治理命令合并到现有 hook 中。

完整的终端安装、配置、菜单选择和问题处理步骤，请参阅 [命令行使用教程](docs/command-line-guide.md)。

## SourceTree 集成

SourceTree 中的普通 Push 会执行只读 `pre-push` 检查，因此不会在 GUI 操作过程中突然修改代码或创建 commit。建议配置三个 Custom Actions：

| 动作名称 | 脚本 | 行为 |
| --- | --- | --- |
| `Submodule - Check` | `submodule-check.sh` | 只读检查当前状态 |
| `Submodule - Accept Current Pointers` | `submodule-accept-pointers.sh` | 将全部当前子模块 SHA 汇总生成一条主仓库 commit，不执行 push |
| `Submodule - Sync Recorded Pointers` | `submodule-sync.sh` | 将子模块同步到主仓库已记录的 SHA |

Custom Actions 的具体配置值、GUI 工作流和转入 Terminal 的判断标准，请参阅 [SourceTree 使用教程](docs/sourcetree-guide.md)。

## CLI 与 Agent 接入

CLI 复用与 hook 相同的治理状态采集逻辑，并提供结构化 JSON 输出；MCP server 是建立在 CLI 能力上的本地 Agent 适配层：

```bash
node .git/submodule-governance/cli/submodule-governance.mjs status --json
node .git/submodule-governance/cli/submodule-governance-mcp.mjs
```

启动 MCP server 时，应将进程工作目录设置为需要治理的主仓库根目录；server 会拒绝未显式传入 `confirm: true` 的写操作。完整的 stdio MCP 配置示例、工具说明和 Agent 安全流程，请参阅 [本地 MCP 服务接入教程](docs/local-mcp-guide.md)。

## 关键防护场景

当子模块已经有新的 commit，但主仓库没有更新子模块指针时，普通 `git push` 的 hook 只会阻止并提示执行 `.git/submodule-governance/submodule-push.sh`。在终端执行该治理 push 命令后，会先汇总所有不一致的子模块，再逐个弹出修复菜单：

```text
发现 2 个子模块与主仓库记录不一致：
  - ios: <old_commit> -> <new_commit>
  - android: <old_commit> -> <new_commit>
```

```text
当前子模块 'ios' 与主仓库记录不一致：
  子模块当前 commit：<current_commit>
  主仓库记录 commit：<recorded_commit>

请选择修复方式：
  [1] 将主仓库指针更新到当前 'ios' commit
  [2] 将 'ios' 恢复到主仓库记录的 commit
  [3] 我已了解风险，继续 push
  [4] 取消
```

选择 `[1]` 会记录需要更新的主仓库指针；脚本会继续处理其余不一致的子模块，全部选择完成后，再将所有选择更新的指针合并生成一个主仓库 commit。非严格模式下，子模块内部未提交内容会提示风险但不纳入指针 commit；严格模式或出现其他阻断问题时，脚本会在进入修复菜单前退出，不会留下部分修复 commit。

```text
已修复：主仓库子模块指针已更新并生成 commit（<commit_sha> chore(submodule): update pointers）。
  - ios: <old_commit> -> <new_commit>
  - android: <old_commit> -> <new_commit>
子模块修复完成。
```

通过 `submodule-push.sh` 发起时，修复完成后会继续执行正常 `git push`，由只读 hook 再次确认最终状态；仅执行 `submodule-fix.sh` 时则不会 push。

选择 `[2]` 会将子模块 checkout 回主仓库记录的 commit，适用于本地子模块误切到其他 commit 的情况。

选择 `[3]` 不做修改，并继续本次 push。此时主仓库远端仍然记录旧的子模块 commit，其他人拉取主仓库后不会自动拿到你本地当前的子模块 commit。

选择 `[4]` 会取消当前流程，终止操作并阻止本次 push。如果存在多个子模块不一致，后续子模块不会继续进入修复菜单。

也就是说，正确流程是：先在子模块仓库提交并推送代码，再回到主仓库提交子模块指针变化。这个模板会帮助开发者在忘记第二步时及时发现，并给出可选择的修复动作。

如果脚本运行在非交互环境（例如 GUI、CI 或管道），只读检查不会弹菜单，会直接输出中文错误并阻止需要人工判断的 push。
