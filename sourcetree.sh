#!/usr/bin/env bash
set -euo pipefail

template_dir="$(cd "$(dirname "$0")" && pwd)"
common_file="$template_dir/template/submodule-governance/scripts/submodule-common.sh"
export SUBMODULE_GOVERNANCE_COLOR="${SUBMODULE_GOVERNANCE_COLOR:-always}"
if [[ -f "$common_file" ]]; then
  # shellcheck disable=SC1090
  source "$common_file"
  sg_setup_colors
else
  sg_error() { echo "错误：$*"; }
  sg_info() { echo "$*"; }
fi

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
  sg_error "未检测到本地治理脚本，请先执行："
  sg_info "  /path/to/submodule-governance-template/bootstrap.sh \"$repo_root\""
  exit 1
fi

cd "$repo_root"
exec "$tool" "$command"
