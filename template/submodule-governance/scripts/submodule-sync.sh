#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if [[ ! -f .gitmodules ]]; then
  echo "No .gitmodules found. Nothing to sync."
  exit 0
fi

git submodule sync --recursive
git submodule update --init --recursive

echo "Submodules synced to commits recorded by main repository."
