#!/usr/bin/env bash
# Non-interactive pointer acceptance for GUI clients such as SourceTree.
set -eo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/submodule-common.sh"

sg_init
if [[ ! -f .gitmodules || ${#submodule_paths[@]} -eq 0 ]]; then
  sg_info "没有需要治理的子模块。"
  exit 0
fi

has_error=0
commit_pointer_paths=()
error() {
  sg_error "$1"
  has_error=1
}

for message in "${config_errors[@]}"; do error "$message"; done
for path in "${missing_paths[@]}"; do error "子模块 '$path' 目录缺失或未初始化。请先执行 submodule-sync.sh。"; done
for path in "${staged_pointer_paths[@]}"; do
  sg_info "提示：子模块指针 '$path' 已暂存，将直接纳入本次治理 commit。"
  commit_pointer_paths+=("$path")
done
for i in "${!branch_mismatch_paths[@]}"; do
  error "'${branch_mismatch_paths[$i]}' 当前分支 '${branch_current_values[$i]}' 与配置分支 '${branch_expected_values[$i]}' 不一致。请在终端执行 submodule-fix.sh。"
done
for path in "${dirty_paths[@]}"; do
  if [[ "$require_pushed" == "1" ]]; then
    error "子模块 '$path' 存在未提交改动。严格模式下不能接受当前指针。"
  else
    sg_warn "子模块 '$path' 存在未提交改动；这些内容不会包含在主仓库指针 commit 中。"
  fi
done
for path in "${no_upstream_paths[@]}"; do
  [[ "$require_pushed" == "1" ]] && error "子模块 '$path' 未配置 upstream 分支。" || sg_warn "子模块 '$path' 未配置 upstream 分支。"
done
for path in "${unpushed_paths[@]}"; do
  [[ "$require_pushed" == "1" ]] && error "子模块 '$path' 当前 HEAD 尚未推送到 upstream。" || sg_warn "子模块 '$path' 当前 HEAD 尚未推送到 upstream。"
done

if [[ "$has_error" -ne 0 ]]; then
  sg_error "当前状态不适合自动接受子模块指针，请在终端中处理。"
  exit 1
fi
if [[ ${#mismatch_paths[@]} -eq 0 && ${#commit_pointer_paths[@]} -eq 0 ]]; then
  sg_success "主仓库记录的子模块指针无需更新。"
  exit 0
fi

if [[ ${#mismatch_paths[@]} -gt 0 ]]; then
  git add "${mismatch_paths[@]}"
  for path in "${mismatch_paths[@]}"; do
    commit_pointer_paths+=("$path")
  done
fi
message="chore(submodule): update pointers"
[[ ${#commit_pointer_paths[@]} -gt 1 ]] || message="chore(submodule): update ${commit_pointer_paths[0]} pointer"
git commit --no-verify -m "$message" -- "${commit_pointer_paths[@]}"
sg_success "已生成 commit：$(git rev-parse --short HEAD) $message"
for i in "${!mismatch_paths[@]}"; do
  echo "  - ${mismatch_paths[$i]}: ${mismatch_indexed_shas[$i]} -> ${mismatch_head_shas[$i]}"
done
