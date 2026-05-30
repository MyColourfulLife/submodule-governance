#!/usr/bin/env bash

sg_init() {
  repo_root="$(git rev-parse --show-toplevel)"
  cd "$repo_root"
  config_file=".submodule-governance.config"
  require_pushed=0
  config_errors=()
  submodule_paths=()
  configured_submodule_paths=()
  configured_submodule_branches=()
  configured_main_branch=""
  missing_paths=()
  dirty_paths=()
  mismatch_paths=()
  mismatch_indexed_shas=()
  mismatch_head_shas=()
  no_upstream_paths=()
  unpushed_paths=()
  branch_mismatch_paths=()
  branch_current_values=()
  branch_expected_values=()
  staged_pointer_paths=()

  [[ -f .gitmodules ]] || return 0
  sg_discover_submodules
  sg_load_config
  sg_collect_state
}

sg_discover_submodules() {
  local line=""
  while IFS= read -r line; do
    submodule_paths+=("${line#* }")
  done < <(git config --file .gitmodules --get-regexp path 2>/dev/null || true)
}

sg_has_submodule() {
  local needle="$1"
  local path=""
  for path in "${submodule_paths[@]}"; do
    [[ "$path" == "$needle" ]] && return 0
  done
  return 1
}

sg_load_config() {
  local value=""
  local key=""
  local path=""

  [[ -f "$config_file" ]] || return 0
  if ! git config --file "$config_file" --list >/dev/null 2>&1; then
    config_errors+=("${config_file} 不是有效的 Git config 文件。")
    return
  fi

  if git config --file "$config_file" --get governance.requirePushed >/dev/null 2>&1; then
    if ! value="$(git config --file "$config_file" --type=bool --get governance.requirePushed 2>/dev/null)"; then
      config_errors+=("${config_file} 中 governance.requirePushed 必须为布尔值。")
    elif [[ "$value" == "true" ]]; then
      require_pushed=1
    fi
  fi

  if git config --file "$config_file" --get governance.mainBranch >/dev/null 2>&1; then
    configured_main_branch="$(git config --file "$config_file" --get governance.mainBranch)"
    [[ -n "$configured_main_branch" ]] || config_errors+=("${config_file} 中 governance.mainBranch 不能为空。")
  fi

  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    path="${key#submodule.}"
    path="${path%.branch}"
    value="$(git config --file "$config_file" --get "$key")"
    if [[ -z "$value" ]]; then
      config_errors+=("${config_file} 中 ${key} 不能为空。")
    elif ! sg_has_submodule "$path"; then
      config_errors+=("${config_file} 配置了不存在的子模块 '$path'。")
    else
      configured_submodule_paths+=("$path")
      configured_submodule_branches+=("$value")
    fi
  done < <(git config --file "$config_file" --name-only --get-regexp '^submodule\..*\.branch$' 2>/dev/null || true)
}

sg_collect_state() {
  local path=""
  local indexed_sha=""
  local head_sha=""
  local current=""
  local i=0
  local staged=""

  if [[ -n "$configured_main_branch" ]]; then
    current="$(git branch --show-current)"
    if [[ "$current" != "$configured_main_branch" ]]; then
      branch_mismatch_paths+=("<main>")
      branch_current_values+=("${current:-<detached>}")
      branch_expected_values+=("$configured_main_branch")
    fi
  fi

  for path in "${submodule_paths[@]}"; do
    if [[ ! -d "$path/.git" && ! -f "$path/.git" ]]; then
      missing_paths+=("$path")
      continue
    fi
    [[ -z "$(git -C "$path" status --porcelain)" ]] || dirty_paths+=("$path")
    indexed_sha="$(git ls-files -s -- "$path" | awk '{print $2}')"
    head_sha="$(git -C "$path" rev-parse HEAD)"
    if [[ -n "$indexed_sha" && "$indexed_sha" != "$head_sha" ]]; then
      mismatch_paths+=("$path")
      mismatch_indexed_shas+=("$indexed_sha")
      mismatch_head_shas+=("$head_sha")
    fi
    if ! git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
      no_upstream_paths+=("$path")
    elif ! git -C "$path" merge-base --is-ancestor HEAD '@{u}'; then
      unpushed_paths+=("$path")
    fi
  done

  for i in "${!configured_submodule_paths[@]}"; do
    path="${configured_submodule_paths[$i]}"
    [[ -d "$path/.git" || -f "$path/.git" ]] || continue
    current="$(git -C "$path" branch --show-current)"
    if [[ "$current" != "${configured_submodule_branches[$i]}" ]]; then
      branch_mismatch_paths+=("$path")
      branch_current_values+=("${current:-<detached>}")
      branch_expected_values+=("${configured_submodule_branches[$i]}")
    fi
  done

  while IFS= read -r staged; do
    if sg_has_submodule "$staged"; then
      staged_pointer_paths+=("$staged")
    fi
  done < <(git diff --cached --name-only --diff-filter=AM)
}

sg_is_interactive() {
  [[ "${SUBMODULE_INTERACTIVE:-1}" == "1" ]] || return 1
  [[ -e /dev/tty ]] && { : </dev/tty >/dev/tty; } 2>/dev/null
}

sg_main_has_non_submodule_changes() {
  local changed=""
  while IFS= read -r changed; do
    [[ -z "$changed" ]] && continue
    sg_has_submodule "$changed" || return 0
  done < <(git status --porcelain | awk '{print $2}')
  return 1
}
