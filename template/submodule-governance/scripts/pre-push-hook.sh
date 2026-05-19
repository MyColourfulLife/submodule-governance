#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
if [[ -f "$repo_root/.submodule-governance.env" ]]; then
  # shellcheck disable=SC1090
  source "$repo_root/.submodule-governance.env"
fi

"$repo_root/scripts/submodule-check.sh"
