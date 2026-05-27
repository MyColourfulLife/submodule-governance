#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./bootstrap.sh [target_repo_path] [--strict]

Examples:
  ./bootstrap.sh
  ./bootstrap.sh /path/to/existing/repo
  ./bootstrap.sh /path/to/existing/repo --strict
EOF
}

target_repo=""
strict_mode="0"

for arg in "$@"; do
  case "$arg" in
    --strict)
      strict_mode="1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$target_repo" ]]; then
        target_repo="$arg"
      else
        echo "Unexpected argument: $arg"
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
template_root="$(cd "$(dirname "$0")/template/submodule-governance" && pwd)"

if ! git -C "$target_repo" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "Target is not a git repository: $target_repo"
  exit 1
fi

target_repo="$(git -C "$target_repo" rev-parse --show-toplevel)"
git_dir="$(git -C "$target_repo" rev-parse --git-dir)"
case "$git_dir" in
  /*) ;;
  *) git_dir="$target_repo/$git_dir" ;;
esac

tool_dir="$git_dir/submodule-governance"
mkdir -p "$tool_dir"
mkdir -p "$tool_dir/cli"

cp "$template_root/scripts/submodule-check.sh" "$tool_dir/submodule-check.sh"
cp "$template_root/scripts/submodule-common.sh" "$tool_dir/submodule-common.sh"
cp "$template_root/scripts/submodule-fix.sh" "$tool_dir/submodule-fix.sh"
cp "$template_root/scripts/submodule-push.sh" "$tool_dir/submodule-push.sh"
cp "$template_root/scripts/submodule-accept-pointers.sh" "$tool_dir/submodule-accept-pointers.sh"
cp "$template_root/scripts/submodule-state.sh" "$tool_dir/submodule-state.sh"
cp "$template_root/cli/submodule-governance.mjs" "$tool_dir/cli/submodule-governance.mjs"
cp "$template_root/cli/submodule-governance-mcp.mjs" "$tool_dir/cli/submodule-governance-mcp.mjs"
cp "$template_root/scripts/submodule-sync.sh" "$tool_dir/submodule-sync.sh"
cp "$template_root/scripts/pre-push-hook.sh" "$tool_dir/pre-push-hook.sh"
cp "$template_root/scripts/install-hooks.sh" "$tool_dir/install-hooks.sh"

chmod +x \
  "$tool_dir/submodule-check.sh" \
  "$tool_dir/submodule-common.sh" \
  "$tool_dir/submodule-fix.sh" \
  "$tool_dir/submodule-push.sh" \
  "$tool_dir/submodule-accept-pointers.sh" \
  "$tool_dir/submodule-state.sh" \
  "$tool_dir/cli/submodule-governance.mjs" \
  "$tool_dir/cli/submodule-governance-mcp.mjs" \
  "$tool_dir/submodule-sync.sh" \
  "$tool_dir/pre-push-hook.sh" \
  "$tool_dir/install-hooks.sh"

config_file="$target_repo/.submodule-governance.config"
strict_value="false"
if [[ "$strict_mode" == "1" ]]; then
  strict_value="true"
fi

if [[ ! -f "$config_file" ]]; then
  cat >"$config_file" <<EOF
[governance]
    # false: only warn when submodule HEAD is not pushed to upstream.
    # true: fail and block push when submodule HEAD is not pushed to upstream.
    requirePushed = $strict_value
    # mainBranch = main

# 子模块分支配置示例。subsection 名称必须与 .gitmodules 中的路径一致。
# [submodule "ios"]
#     branch = dev/v2.2.7/stable
#
# [submodule "android"]
#     branch = dev/v2.2.7/stable
EOF
elif ! git config --file "$config_file" --list >/dev/null 2>&1; then
  echo "Invalid Git config file: $config_file"
  exit 1
else
  git config --file "$config_file" governance.requirePushed "$strict_value"
fi

(
  cd "$target_repo"
  "$tool_dir/install-hooks.sh"
)

echo "Running initial check..."
(
  cd "$target_repo"
  SUBMODULE_INTERACTIVE=0 "$tool_dir/submodule-check.sh" || true
)

echo "Bootstrap complete."
echo "Target repo: $target_repo"
echo "Tool dir: $tool_dir"
if [[ "$strict_mode" == "1" ]]; then
  echo "Mode: strict (governance.requirePushed=true)"
else
  echo "Mode: non-strict (governance.requirePushed=false)"
fi
