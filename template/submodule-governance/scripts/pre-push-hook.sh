#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
git_dir="$(git rev-parse --git-dir)"
case "$git_dir" in
  /*) ;;
  *) git_dir="$repo_root/$git_dir" ;;
esac

export SUBMODULE_PUSH_REMOTE_NAME="${1:-}"
export SUBMODULE_PUSH_REMOTE_URL="${2:-}"

"$git_dir/submodule-governance/submodule-check.sh"
