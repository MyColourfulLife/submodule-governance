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

cp "$template_root/scripts/submodule-check.sh" "$tool_dir/submodule-check.sh"
cp "$template_root/scripts/submodule-sync.sh" "$tool_dir/submodule-sync.sh"
cp "$template_root/scripts/pre-push-hook.sh" "$tool_dir/pre-push-hook.sh"
cp "$template_root/scripts/install-hooks.sh" "$tool_dir/install-hooks.sh"

chmod +x \
  "$tool_dir/submodule-check.sh" \
  "$tool_dir/submodule-sync.sh" \
  "$tool_dir/pre-push-hook.sh" \
  "$tool_dir/install-hooks.sh"

config_file="$target_repo/.submodule-governance.env"
if [[ ! -f "$config_file" ]]; then
  cat >"$config_file" <<EOF
# 0: only warn when submodule HEAD is not pushed to upstream.
# 1: fail and block push when submodule HEAD is not pushed to upstream.
SUBMODULE_REQUIRE_PUSHED=$strict_mode
EOF
else
  if grep -q '^SUBMODULE_REQUIRE_PUSHED=' "$config_file"; then
    sed -i.bak "s/^SUBMODULE_REQUIRE_PUSHED=.*/SUBMODULE_REQUIRE_PUSHED=$strict_mode/" "$config_file"
    rm -f "$config_file.bak"
  else
    printf "\nSUBMODULE_REQUIRE_PUSHED=%s\n" "$strict_mode" >> "$config_file"
  fi
fi

branch_config_file="$target_repo/.submodule-governance.branches"
if [[ ! -f "$branch_config_file" ]]; then
  cat >"$branch_config_file" <<'EOF'
# 主仓库与子模块分支规划配置。
# 文件格式：模块路径=分支名
# 默认只启用主仓库分支检查，主仓库默认分支为 main。
# 如果你的主仓库使用其他分支，请修改 main 的值。
main=main

# 子模块配置示例：
# 需要启用时，取消注释并把分支名改成当前需求约定的分支。
# key 必须与 .gitmodules 中的子模块路径一致。
#
# ios=dev/v2.2.7/stable
# android=dev/v2.2.7/stable
# libs=dev/v2.2.7/stable
#
# 如果暂时不需要分支规划，可以保留注释内容不变。
EOF
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
  echo "Mode: strict (SUBMODULE_REQUIRE_PUSHED=1)"
else
  echo "Mode: non-strict (SUBMODULE_REQUIRE_PUSHED=0)"
fi
