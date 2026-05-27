#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
git_dir="$(git rev-parse --git-dir)"
case "$git_dir" in
  /*) ;;
  *) git_dir="$repo_root/$git_dir" ;;
esac

set +e
"$git_dir/submodule-governance/submodule-fix.sh"
fix_exit=$?
set -e

case "$fix_exit" in
  0)
    git push "$@"
    ;;
  10)
    echo "本次 push 将带着已确认的分支或指针风险继续。"
    SUBMODULE_GOVERNANCE_BYPASS=1 git push "$@"
    ;;
  *)
    exit "$fix_exit"
    ;;
esac
