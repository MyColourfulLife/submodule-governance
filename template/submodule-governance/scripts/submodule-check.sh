#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if [[ -f ".submodule-governance.env" ]]; then
  # shellcheck disable=SC1091
  source ".submodule-governance.env"
fi

if [[ ! -f .gitmodules ]]; then
  echo "未发现 .gitmodules，跳过子模块检查。"
  exit 0
fi

require_pushed="${SUBMODULE_REQUIRE_PUSHED:-0}"
has_error=0
needs_repush=0
auto_push_done=0

print_error() {
  echo "错误：$1"
  has_error=1
}

print_warn() {
  echo "警告：$1"
}

is_interactive() {
  [[ "${SUBMODULE_INTERACTIVE:-1}" == "1" ]] || return 1
  [[ -e /dev/tty ]] && { : </dev/tty >/dev/tty; } 2>/dev/null
}

ask_push_after_repair() {
  local choice=""
  local remote_name="${SUBMODULE_PUSH_REMOTE_NAME:-}"

  if ! is_interactive; then
    echo "问题已修复。请手动执行 git push。"
    needs_repush=1
    return
  fi

  {
    echo
    echo "问题已修复："
    echo "  [y] 自动 push"
    echo "  [n] 手动 push"
    printf "请输入选项 [y/n]: "
  } >/dev/tty
  read -r choice </dev/tty

  case "$choice" in
    y|Y)
      if [[ -n "$remote_name" ]]; then
        git push --no-verify "$remote_name"
      else
        git push --no-verify
      fi
      echo "已自动 push。"
      auto_push_done=1
      ;;
    n|N|"")
      echo "请确认后手动执行 git push。"
      needs_repush=1
      ;;
    *)
      echo "无效选项 '$choice'。请确认后手动执行 git push。"
      needs_repush=1
      ;;
  esac
}

fix_pointer_mismatch() {
  local path="$1"
  local indexed_sha="$2"
  local head_sha="$3"
  local choice=""
  local commit_message=""
  local commit_sha=""

  if ! is_interactive; then
    print_error "子模块 '$path' 当前 HEAD ($head_sha) 与主仓库记录的 commit ($indexed_sha) 不一致。请执行：git add $path && git commit"
    return
  fi

  {
    echo
    echo "当前子模块 '${path}' 与主仓库记录不一致："
    echo "  子模块当前 commit：${head_sha}"
    echo "  主仓库记录 commit：${indexed_sha}"
    echo
    echo "风险说明："
    echo "  如果继续 push，主仓库远端仍然记录旧的子模块 commit。"
    echo "  其他人拉取主仓库后，不会自动拿到你本地当前的 '${path}' commit。"
    echo "  如果这是一次有意的本地调试状态，可以选择继续；如果当前子模块变更属于本次提交，应先更新主仓库指针。"
    echo
    echo "请选择修复方式："
    echo "  [1] 将主仓库指针更新到当前 '${path}' commit"
    echo "  [2] 将 '${path}' 恢复到主仓库记录的 commit"
    echo "  [3] 我已了解风险，继续 push"
    printf "请输入选项 [1/2/3]: "
  } >/dev/tty
  read -r choice </dev/tty

  case "$choice" in
    1)
      git add "$path"
      commit_message="Update ${path} submodule pointer"
      git commit -m "$commit_message"
      commit_sha="$(git rev-parse --short HEAD)"
      echo "已修复：主仓库子模块指针已更新并生成 commit（${commit_sha} ${commit_message}，${path}: ${indexed_sha} -> ${head_sha}）。"
      ask_push_after_repair
      ;;
    2)
      git -C "$path" checkout "$indexed_sha"
      echo "已修复：'${path}' 已恢复到主仓库记录的 commit：${indexed_sha}。"
      ask_push_after_repair
      ;;
    3)
      echo "已选择继续 push：主仓库指针不会更新，远端仍记录旧的 '${path}' commit。"
      ;;
    "")
      print_error "未选择修复方式，push 已阻止。"
      ;;
    *)
      print_error "无效选项 '$choice'，push 已阻止。"
      ;;
  esac
}

submodule_paths=()
while IFS= read -r line; do
  path="${line#* }"
  submodule_paths+=("$path")
done < <(git config --file .gitmodules --get-regexp path || true)

if [[ ${#submodule_paths[@]} -eq 0 ]]; then
  echo ".gitmodules 中未定义子模块路径。"
  exit 0
fi

while IFS= read -r status_line; do
  [[ -z "$status_line" ]] && continue
  state="${status_line:0:1}"
  rest="${status_line:1}"
  path="${rest#* }"
  path="${path%% *}"

  if [[ "$state" == "-" ]]; then
    print_error "子模块 '$path' 未初始化。请执行：.git/submodule-governance/submodule-sync.sh"
  fi
done < <(git submodule status --recursive || true)

for path in "${submodule_paths[@]}"; do
  if [[ ! -d "$path/.git" && ! -f "$path/.git" ]]; then
    print_error "子模块 '$path' 目录缺失。请执行：.git/submodule-governance/submodule-sync.sh"
    continue
  fi

  if [[ -n "$(git -C "$path" status --porcelain)" ]]; then
    print_error "子模块 '$path' 存在未提交改动。请先提交、暂存或还原子模块中的改动。"
  fi

  indexed_sha="$(git ls-files -s -- "$path" | awk '{print $2}')"
  head_sha="$(git -C "$path" rev-parse HEAD)"
  if [[ -n "$indexed_sha" && "$indexed_sha" != "$head_sha" ]]; then
    fix_pointer_mismatch "$path" "$indexed_sha" "$head_sha"
  fi

  if ! git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    if [[ "$require_pushed" == "1" ]]; then
      print_error "子模块 '$path' 未配置 upstream 分支。"
    else
      print_warn "子模块 '$path' 未配置 upstream 分支。"
    fi
    continue
  fi

  if ! git -C "$path" merge-base --is-ancestor HEAD '@{u}'; then
    if [[ "$require_pushed" == "1" ]]; then
      print_error "子模块 '$path' 当前 HEAD 尚未推送到 upstream。请先进入子模块执行 git push。"
    else
      print_warn "子模块 '$path' 当前 HEAD 尚未推送到 upstream。"
    fi
  fi
done

if git diff --cached --name-only --diff-filter=AM | grep -qE '.*'; then
  while IFS= read -r staged_path; do
    if printf '%s\n' "${submodule_paths[@]}" | grep -Fxq "$staged_path"; then
      print_error "子模块指针 '$staged_path' 已暂存但尚未提交。请先提交主仓库。"
    fi
  done < <(git diff --cached --name-only)
fi

if [[ "$has_error" -ne 0 ]]; then
  echo "子模块检查未通过，已阻止 push。"
  exit 1
fi

if [[ "$auto_push_done" -ne 0 ]]; then
  exit 1
fi

if [[ "$needs_repush" -ne 0 ]]; then
  echo "子模块问题已修复。请重新执行 git push。"
  exit 1
fi

if [[ "$require_pushed" == "1" ]]; then
  echo "子模块检查通过（严格模式）。"
else
  echo "子模块检查通过（非严格模式）。"
fi
