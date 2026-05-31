#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$script_dir/submodule-common.sh" ]]; then
  # shellcheck disable=SC1091
  source "$script_dir/submodule-common.sh"
  sg_setup_colors
else
  sg_error() { echo "错误：$*"; }
  sg_warn() { echo "警告：$*"; }
  sg_success() { echo "$*"; }
  sg_info() { echo "$*"; }
fi

usage() {
  cat <<'EOF'
Usage:
  uninstall.sh [target_repo_path] [--remove-config]

Examples:
  ./uninstall.sh
  ./uninstall.sh /path/to/existing/repo
  ./uninstall.sh /path/to/existing/repo --remove-config

By default, .submodule-governance.config is preserved.
EOF
}

target_repo=""
remove_config="0"

for arg in "$@"; do
  case "$arg" in
    --remove-config)
      remove_config="1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$target_repo" ]]; then
        target_repo="$arg"
      else
        sg_error "Unexpected argument: $arg"
        usage
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$target_repo" ]]; then
  target_repo="$(pwd)"
fi

target_repo="$(cd "$target_repo" && pwd)"
if ! git -C "$target_repo" rev-parse --show-toplevel >/dev/null 2>&1; then
  sg_error "Target is not a git repository: $target_repo"
  exit 1
fi

repo_root="$(git -C "$target_repo" rev-parse --show-toplevel)"
git_dir="$(git -C "$repo_root" rev-parse --git-dir)"
case "$git_dir" in
  /*) ;;
  *) git_dir="$repo_root/$git_dir" ;;
esac

tool_dir="$git_dir/submodule-governance"
template_hook="$tool_dir/pre-push-hook.sh"

configured_hooks_path="$(git -C "$repo_root" config --get core.hooksPath || true)"
if [[ -n "$configured_hooks_path" ]]; then
  case "$configured_hooks_path" in
    /*) hooks_dir="$configured_hooks_path" ;;
    *) hooks_dir="$repo_root/$configured_hooks_path" ;;
  esac
else
  hooks_dir="$git_dir/hooks"
fi

hook_file="$hooks_dir/pre-push"
if [[ "$hooks_dir" == "$repo_root/.husky/_" ]]; then
  hook_file="$repo_root/.husky/pre-push"
fi

removed_hook="0"
if [[ -f "$hook_file" ]]; then
  if [[ -f "$template_hook" ]] && cmp -s "$template_hook" "$hook_file"; then
    rm -f "$hook_file"
    removed_hook="1"
    sg_success "Removed generated pre-push hook: $hook_file"
  elif grep -q 'submodule-governance/pre-push-hook.sh' "$hook_file"; then
    hook_lines="$(sed '/^[[:space:]]*$/d' "$hook_file" | wc -l | tr -d ' ')"
    governance_lines="$(grep -c 'submodule-governance/pre-push-hook.sh' "$hook_file" || true)"
    if [[ "$hook_lines" -le 2 && "$governance_lines" -eq 1 ]]; then
      rm -f "$hook_file"
      removed_hook="1"
      sg_success "Removed generated pre-push hook: $hook_file"
    else
      sg_warn "Existing pre-push hook contains submodule governance but was not removed: $hook_file"
      sg_info "Remove this line manually if you want to keep the rest of the hook:"
      sg_info '  "$(git rev-parse --git-dir)/submodule-governance/pre-push-hook.sh" "$@"'
    fi
  fi
fi

if [[ -d "$tool_dir" ]]; then
  rm -rf "$tool_dir"
  sg_success "Removed tool directory: $tool_dir"
else
  sg_info "Tool directory not found: $tool_dir"
fi

config_file="$repo_root/.submodule-governance.config"
if [[ "$remove_config" == "1" ]]; then
  if [[ -f "$config_file" ]]; then
    rm -f "$config_file"
    sg_success "Removed config file: $config_file"
  else
    sg_info "Config file not found: $config_file"
  fi
else
  sg_info "Kept config file: $config_file"
fi

if [[ "$removed_hook" == "0" ]]; then
  sg_info "No generated pre-push hook was removed."
fi

sg_success "Uninstall complete."
