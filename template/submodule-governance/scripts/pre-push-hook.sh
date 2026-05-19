#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
git_dir="$(git rev-parse --git-dir)"
case "$git_dir" in
  /*) ;;
  *) git_dir="$repo_root/$git_dir" ;;
esac

if [[ -f "$repo_root/.submodule-governance.env" ]]; then
  # shellcheck disable=SC1090
  source "$repo_root/.submodule-governance.env"
fi

"$git_dir/submodule-governance/submodule-check.sh"
