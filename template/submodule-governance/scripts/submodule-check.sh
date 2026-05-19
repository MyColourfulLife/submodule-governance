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
force_push_without_checks=0
mismatch_paths=()
mismatch_indexed_shas=()
mismatch_head_shas=()
branch_config_file=".submodule-governance.branches"
configured_main_branch=""
configured_submodule_paths=()
configured_submodule_branches=()
branch_mismatch_found=0

print_error() {
  echo "错误：$1"
  has_error=1
}

print_warn() {
  echo "警告：$1"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

is_interactive() {
  [[ "${SUBMODULE_INTERACTIVE:-1}" == "1" ]] || return 1
  [[ -e /dev/tty ]] && { : </dev/tty >/dev/tty; } 2>/dev/null
}

submodule_exists() {
  local needle="$1"
  local path=""

  for path in "${submodule_paths[@]}"; do
    if [[ "$path" == "$needle" ]]; then
      return 0
    fi
  done

  return 1
}

main_repo_has_non_submodule_changes() {
  local changed_path=""

  while IFS= read -r changed_path; do
    [[ -z "$changed_path" ]] && continue
    if ! submodule_exists "$changed_path"; then
      return 0
    fi
  done < <(git status --porcelain | awk '{print $2}')

  return 1
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

load_branch_config() {
  local line=""
  local line_no=0
  local key=""
  local value=""

  [[ -f "$branch_config_file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    line="$(trim "$line")"

    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue

    if [[ "$line" != *=* ]]; then
      print_error "${branch_config_file}:${line_no} 配置格式错误，应使用 key=value。"
      continue
    fi

    key="$(trim "${line%%=*}")"
    value="$(trim "${line#*=}")"

    if [[ -z "$key" || -z "$value" ]]; then
      print_error "${branch_config_file}:${line_no} 配置不能为空。"
      continue
    fi

    if [[ "$key" == "main" ]]; then
      configured_main_branch="$value"
      continue
    fi

    if ! submodule_exists "$key"; then
      print_error "${branch_config_file}:${line_no} 配置了不存在的子模块 '$key'。"
      continue
    fi

    configured_submodule_paths+=("$key")
    configured_submodule_branches+=("$value")
  done < "$branch_config_file"
}

align_branch_config() {
  local current_main_branch=""
  local path=""
  local branch=""
  local i=0

  if main_repo_has_non_submodule_changes; then
    print_error "主仓库存在未提交改动，无法自动切换分支。请先提交、暂存或还原改动。"
    return
  fi

  if [[ -n "$configured_main_branch" ]]; then
    current_main_branch="$(git branch --show-current)"
    if [[ "$current_main_branch" != "$configured_main_branch" ]]; then
      if ! git show-ref --verify --quiet "refs/heads/$configured_main_branch" &&
         ! git show-ref --verify --quiet "refs/remotes/origin/$configured_main_branch"; then
        print_error "主仓库目标分支 '$configured_main_branch' 不存在。"
        return
      fi
      git checkout "$configured_main_branch"
    fi
  fi

  for i in "${!configured_submodule_paths[@]}"; do
    path="${configured_submodule_paths[$i]}"
    branch="${configured_submodule_branches[$i]}"

    if [[ -n "$(git -C "$path" status --porcelain)" ]]; then
      print_error "子模块 '$path' 存在未提交改动，无法自动切换分支。"
      return
    fi

    git -C "$path" fetch origin
    if ! git -C "$path" show-ref --verify --quiet "refs/heads/$branch" &&
       ! git -C "$path" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      print_error "子模块 '$path' 目标分支 '$branch' 不存在。"
      return
    fi

    git -C "$path" checkout "$branch"
    git -C "$path" pull --ff-only origin "$branch"
  done

  echo "分支已根据 ${branch_config_file} 处理到一致状态。"
}

check_branch_config() {
  local current_branch=""
  local expected_branch=""
  local path=""
  local i=0
  local status=""
  local choice=""

  [[ -f "$branch_config_file" ]] || return 0

  load_branch_config
  [[ "$has_error" -ne 0 ]] && return

  if is_interactive; then
    exec 3>/dev/tty
  else
    exec 3>&1
  fi

  echo >&3
  echo "分支匹配检查：" >&3
  echo >&3
  if [[ -n "$configured_main_branch" ]]; then
    current_branch="$(git branch --show-current)"
    status="一致"
    if [[ "$current_branch" != "$configured_main_branch" ]]; then
      status="不一致"
      branch_mismatch_found=1
    fi
    echo "主仓库：" >&3
    echo "  当前分支：${current_branch:-<detached>}" >&3
    echo "  配置分支：${configured_main_branch}" >&3
    echo "  状态：${status}" >&3
    echo >&3
  fi

  if [[ ${#configured_submodule_paths[@]} -gt 0 ]]; then
    echo "子模块：" >&3
    for i in "${!configured_submodule_paths[@]}"; do
      path="${configured_submodule_paths[$i]}"
      expected_branch="${configured_submodule_branches[$i]}"
      current_branch="$(git -C "$path" branch --show-current)"
      status="一致"
      if [[ "$current_branch" != "$expected_branch" ]]; then
        status="不一致"
        branch_mismatch_found=1
      fi
      echo "  ${path}:" >&3
      echo "    当前分支：${current_branch:-<detached>}" >&3
      echo "    配置分支：${expected_branch}" >&3
      echo "    状态：${status}" >&3
      echo >&3
    done
  fi
  exec 3>&-

  [[ "$branch_mismatch_found" -eq 0 ]] && return 0

  if ! is_interactive; then
    print_error "当前分支与 ${branch_config_file} 不一致。非交互环境已阻止 push。"
    return
  fi

  {
    echo "风险说明："
    echo "  当前主仓库或子模块分支与配置文件不一致。"
    echo "  如果继续 push，主仓库可能记录到非预期分支上的子模块 commit。"
    echo "  这会导致需求分支、子模块分支和最终可复现版本不一致。"
    echo "  建议先根据配置文件对齐分支，再继续提交。"
    echo
    echo "请选择处理方式："
    echo "  [1] 根据配置文件将分支处理到一致状态"
    echo "  [2] 取消，终止操作"
    echo "  [3] 我已了解风险，强制继续 push"
    printf "请输入选项 [1/2/3]: "
  } >/dev/tty
  read -r choice </dev/tty

  case "$choice" in
    1)
      align_branch_config
      ;;
    2|"")
      print_error "已取消操作，push 已阻止。"
      ;;
    3)
      echo "已选择强制继续 push：将跳过后续所有子模块检查。"
      force_push_without_checks=1
      ;;
    *)
      print_error "无效选项 '$choice'，push 已阻止。"
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
    echo "  [4] 取消"
    printf "请输入选项 [1/2/3/4]: "
  } >/dev/tty
  read -r choice </dev/tty

  case "$choice" in
    1)
      git add "$path"
      commit_message="Update ${path} submodule pointer"
      git commit -m "$commit_message" -- "$path"
      commit_sha="$(git rev-parse --short HEAD)"
      echo "已修复：主仓库子模块指针已更新并生成 commit（${commit_sha} ${commit_message}，${path}: ${indexed_sha} -> ${head_sha}）。"
      needs_repush=1
      ;;
    2)
      git -C "$path" checkout "$indexed_sha"
      echo "已修复：'${path}' 已恢复到主仓库记录的 commit：${indexed_sha}。"
      needs_repush=1
      ;;
    3)
      echo "已选择继续 push：主仓库指针不会更新，远端仍记录旧的 '${path}' commit。"
      ;;
    4)
      print_error "已取消操作，push 已阻止。"
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

check_branch_config

if [[ "$has_error" -ne 0 ]]; then
  echo "分支匹配检查未通过，已阻止 push。"
  exit 1
fi

if [[ "$force_push_without_checks" -ne 0 ]]; then
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
    mismatch_paths+=("$path")
    mismatch_indexed_shas+=("$indexed_sha")
    mismatch_head_shas+=("$head_sha")
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

if [[ ${#mismatch_paths[@]} -gt 0 ]]; then
  if is_interactive; then
    {
      echo
      echo "发现 ${#mismatch_paths[@]} 个子模块与主仓库记录不一致："
      for i in "${!mismatch_paths[@]}"; do
        echo "  - ${mismatch_paths[$i]}: ${mismatch_indexed_shas[$i]} -> ${mismatch_head_shas[$i]}"
      done
    } >/dev/tty
  fi

  for i in "${!mismatch_paths[@]}"; do
    fix_pointer_mismatch "${mismatch_paths[$i]}" "${mismatch_indexed_shas[$i]}" "${mismatch_head_shas[$i]}"
    if [[ "$has_error" -ne 0 ]]; then
      break
    fi
  done
fi

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

if [[ "$needs_repush" -ne 0 ]]; then
  ask_push_after_repair
  if [[ "$auto_push_done" -ne 0 ]]; then
    exit 0
  fi
  exit 1
fi

if [[ "$require_pushed" == "1" ]]; then
  echo "子模块检查通过（严格模式）。"
else
  echo "子模块检查通过（非严格模式）。"
fi
