#!/usr/bin/env bash
# Bash 3.2 treats empty array expansion as unset under nounset.
set -eo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/submodule-common.sh"

sg_init
if [[ ! -f .gitmodules ]]; then
  echo "未发现 .gitmodules，跳过子模块检查。"
  exit 0
fi
if [[ ${#submodule_paths[@]} -eq 0 ]]; then
  echo ".gitmodules 中未定义子模块路径。"
  exit 0
fi

bypass_risks="${SUBMODULE_GOVERNANCE_BYPASS:-0}"
has_error=0

error() {
  echo "错误：$1"
  has_error=1
}

warn() {
  echo "警告：$1"
}

for message in "${config_errors[@]}"; do
  error "$message"
done
for path in "${missing_paths[@]}"; do
  error "子模块 '$path' 目录缺失或未初始化。请执行：.git/submodule-governance/submodule-sync.sh"
done
for path in "${dirty_paths[@]}"; do
  if [[ "$require_pushed" == "1" ]]; then
    error "子模块 '$path' 存在未提交改动。请先处理子模块中的改动。"
  else
    warn "子模块 '$path' 存在未提交改动；这些改动不会包含在主仓库子模块指针 commit 中。"
  fi
done
for path in "${no_upstream_paths[@]}"; do
  if [[ "$require_pushed" == "1" ]]; then
    error "子模块 '$path' 未配置 upstream 分支。"
  else
    warn "子模块 '$path' 未配置 upstream 分支。"
  fi
done
for path in "${unpushed_paths[@]}"; do
  if [[ "$require_pushed" == "1" ]]; then
    error "子模块 '$path' 当前 HEAD 尚未推送到 upstream。请先进入子模块执行 git push。"
  else
    warn "子模块 '$path' 当前 HEAD 尚未推送到 upstream。"
  fi
done
for i in "${!branch_mismatch_paths[@]}"; do
  if [[ "$bypass_risks" == "1" ]]; then
    warn "'${branch_mismatch_paths[$i]}' 当前分支 '${branch_current_values[$i]}' 与配置分支 '${branch_expected_values[$i]}' 不一致；已确认本次继续。"
  else
    error "'${branch_mismatch_paths[$i]}' 当前分支 '${branch_current_values[$i]}' 与配置分支 '${branch_expected_values[$i]}' 不一致。请执行：.git/submodule-governance/submodule-fix.sh"
  fi
done
for i in "${!mismatch_paths[@]}"; do
  if [[ "$bypass_risks" == "1" ]]; then
    warn "子模块 '${mismatch_paths[$i]}' 当前 HEAD 与主仓库记录不一致；已确认本次继续。"
  else
    error "子模块 '${mismatch_paths[$i]}' 当前 HEAD (${mismatch_head_shas[$i]}) 与主仓库记录的 commit (${mismatch_indexed_shas[$i]}) 不一致。请执行：.git/submodule-governance/submodule-fix.sh"
  fi
done
for path in "${staged_pointer_paths[@]}"; do
  error "子模块指针 '$path' 已暂存但尚未提交。请先提交主仓库。"
done

if [[ "$has_error" -ne 0 ]]; then
  echo "子模块检查未通过，已阻止 push。"
  exit 1
fi
if [[ "$require_pushed" == "1" ]]; then
  echo "子模块检查通过（严格模式）。"
else
  echo "子模块检查通过（非严格模式）。"
fi
