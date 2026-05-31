#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sourcetree.sh <repo_path> <check|accept-pointers|sync|fix|push|reinstall-hooks>
EOF
}

repo_path="${1:-}"
command="${2:-}"

if [[ -z "$repo_path" || -z "$command" ]]; then
  usage
  exit 2
fi

repo_root="$(git -C "$repo_path" rev-parse --show-toplevel)"
git_dir="$(git -C "$repo_root" rev-parse --git-dir)"
case "$git_dir" in
  /*) ;;
  *) git_dir="$repo_root/$git_dir" ;;
esac

tool="$git_dir/submodule-governance/sourcetree-command.sh"
if [[ ! -x "$tool" ]]; then
  echo "未检测到本地治理脚本，请先执行："
  echo "  /path/to/submodule-governance-template/bootstrap.sh \"$repo_root\""
  exit 1
fi

cd "$repo_root"
exec "$tool" "$command"
