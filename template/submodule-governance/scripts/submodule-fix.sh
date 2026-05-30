#!/usr/bin/env bash
# Bash 3.2 treats empty array expansion as unset under nounset.
set -eo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/submodule-common.sh"

sg_init
if [[ ! -f .gitmodules || ${#submodule_paths[@]} -eq 0 ]]; then
  echo "没有需要治理的子模块。"
  exit 0
fi
if ! sg_is_interactive; then
  echo "错误：交互修复需要在终端中执行。"
  exit 1
fi

has_error=0
risk_acknowledged=0
changed=0
update_pointer_paths=()
update_pointer_old=()
update_pointer_new=()
restore_paths=()
restore_shas=()
commit_pointer_paths=()

error() {
  echo "错误：$1"
  has_error=1
}

for message in "${config_errors[@]}"; do error "$message"; done
for path in "${missing_paths[@]}"; do error "子模块 '$path' 目录缺失或未初始化。请先执行 submodule-sync.sh。"; done
for path in "${staged_pointer_paths[@]}"; do
  echo "提示：子模块指针 '$path' 已暂存，将直接纳入本次治理 commit。"
  commit_pointer_paths+=("$path")
done
for path in "${dirty_paths[@]}"; do
  if [[ "$require_pushed" == "1" ]]; then
    error "子模块 '$path' 存在未提交改动。严格模式下不能自动修复。"
  else
    echo "警告：子模块 '$path' 存在未提交改动；这些内容不会包含在主仓库指针 commit 中。"
  fi
done
for path in "${no_upstream_paths[@]}"; do
  [[ "$require_pushed" == "1" ]] && error "子模块 '$path' 未配置 upstream 分支。" || echo "警告：子模块 '$path' 未配置 upstream 分支。"
done
for path in "${unpushed_paths[@]}"; do
  [[ "$require_pushed" == "1" ]] && error "子模块 '$path' 当前 HEAD 尚未推送到 upstream。" || echo "警告：子模块 '$path' 当前 HEAD 尚未推送到 upstream。"
done
if [[ "$has_error" -ne 0 ]]; then
  echo "存在需要先手动处理的问题，未执行修复。"
  exit 1
fi

if [[ ${#branch_mismatch_paths[@]} -gt 0 ]]; then
  echo
  echo "发现分支配置不一致："
  for i in "${!branch_mismatch_paths[@]}"; do
    echo "  - ${branch_mismatch_paths[$i]}: ${branch_current_values[$i]} -> ${branch_expected_values[$i]}"
  done
  {
    echo "请选择处理方式："
    echo "  [1] 根据配置切换到一致分支"
    echo "  [2] 保持当前分支并承担本次风险"
    echo "  [3] 取消"
    printf "请输入选项 [1/2/3]: "
  } >/dev/tty
  read -r choice </dev/tty
  case "$choice" in
    1)
      if sg_main_has_non_submodule_changes; then
        error "主仓库存在非子模块改动，无法自动切换分支。"
      else
        if [[ -n "$configured_main_branch" && "$(git branch --show-current)" != "$configured_main_branch" ]]; then
          git checkout "$configured_main_branch"
        fi
        for i in "${!configured_submodule_paths[@]}"; do
          path="${configured_submodule_paths[$i]}"
          branch="${configured_submodule_branches[$i]}"
          [[ -z "$(git -C "$path" status --porcelain)" ]] || { error "子模块 '$path' 存在改动，无法切换分支。"; break; }
          git -C "$path" fetch origin
          git -C "$path" checkout "$branch"
          git -C "$path" pull --ff-only origin "$branch"
        done
        if [[ "$has_error" -eq 0 ]]; then
          echo "分支已根据配置处理完成，重新检查子模块状态。"
          exec "$0"
        fi
      fi
      ;;
    2) risk_acknowledged=1 ;;
    *) error "已取消操作。" ;;
  esac
fi
[[ "$has_error" -eq 0 ]] || exit 1

if [[ ${#mismatch_paths[@]} -gt 0 ]]; then
  echo
  echo "发现 ${#mismatch_paths[@]} 个子模块与主仓库记录不一致："
  for i in "${!mismatch_paths[@]}"; do
    echo "  - ${mismatch_paths[$i]}: ${mismatch_indexed_shas[$i]} -> ${mismatch_head_shas[$i]}"
  done
  for i in "${!mismatch_paths[@]}"; do
    path="${mismatch_paths[$i]}"
    {
      echo
      echo "子模块 '$path'："
      echo "  [1] 将主仓库指针更新到当前 commit"
      echo "  [2] 将子模块恢复到主仓库记录的 commit"
      echo "  [3] 保持不一致并承担本次风险"
      echo "  [4] 取消"
      printf "请输入选项 [1/2/3/4]: "
    } >/dev/tty
    read -r choice </dev/tty
    case "$choice" in
      1)
        update_pointer_paths+=("$path")
        update_pointer_old+=("${mismatch_indexed_shas[$i]}")
        update_pointer_new+=("${mismatch_head_shas[$i]}")
        ;;
      2)
        if [[ -n "$(git -C "$path" status --porcelain)" ]]; then
          error "子模块 '$path' 存在未提交内容，不能恢复到主仓库记录的 commit。"
          break
        fi
        restore_paths+=("$path")
        restore_shas+=("${mismatch_indexed_shas[$i]}")
        ;;
      3) risk_acknowledged=1 ;;
      *) error "已取消操作。"; break ;;
    esac
  done
fi
[[ "$has_error" -eq 0 ]] || exit 1

for i in "${!restore_paths[@]}"; do
  git -C "${restore_paths[$i]}" checkout "${restore_shas[$i]}"
  echo "已恢复：'${restore_paths[$i]}' 已 checkout 到 ${restore_shas[$i]}。"
  changed=1
done

if [[ ${#update_pointer_paths[@]} -gt 0 ]]; then
  git add "${update_pointer_paths[@]}"
  for path in "${update_pointer_paths[@]}"; do
    commit_pointer_paths+=("$path")
  done
fi

if [[ ${#commit_pointer_paths[@]} -gt 0 ]]; then
  message="chore(submodule): update pointers"
  [[ ${#commit_pointer_paths[@]} -gt 1 ]] || message="chore(submodule): update ${commit_pointer_paths[0]} pointer"
  git commit --no-verify -m "$message" -- "${commit_pointer_paths[@]}"
  echo "已生成 commit：$(git rev-parse --short HEAD) $message"
  changed=1
fi

[[ "$changed" -ne 0 ]] && echo "子模块修复完成。" || echo "未修改工作区。"
[[ "$risk_acknowledged" -eq 0 ]] || exit 10
