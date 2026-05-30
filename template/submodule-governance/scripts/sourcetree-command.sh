#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  .sourcetree/submodule-governance.sh <check|accept-pointers|sync|fix|push|reinstall-hooks>
EOF
}

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

git_dir="$(git rev-parse --git-dir)"
case "$git_dir" in
  /*) ;;
  *) git_dir="$repo_root/$git_dir" ;;
esac

tool_dir="$git_dir/submodule-governance"

if [[ ! -d "$tool_dir" ]]; then
  echo "未检测到本地治理脚本，请先在当前仓库执行 bootstrap.sh 安装。"
  exit 1
fi

case "${1:-}" in
  check)
    exec "$tool_dir/submodule-check.sh"
    ;;
  accept-pointers)
    exec "$tool_dir/submodule-accept-pointers.sh"
    ;;
  sync)
    exec "$tool_dir/submodule-sync.sh"
    ;;
  fix)
    exec "$tool_dir/submodule-fix.sh"
    ;;
  push)
    exec "$tool_dir/submodule-push.sh"
    ;;
  reinstall-hooks)
    exec "$tool_dir/install-hooks.sh"
    ;;
  -h|--help|"")
    usage
    ;;
  *)
    echo "Unknown command: $1"
    usage
    exit 1
    ;;
esac
