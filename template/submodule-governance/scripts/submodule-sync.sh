#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/submodule-common.sh"
sg_setup_colors

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if [[ ! -f .gitmodules ]]; then
  sg_info "No .gitmodules found. Nothing to sync."
  exit 0
fi

git submodule sync --recursive
git submodule update --init --recursive

sg_success "Submodules synced to commits recorded by main repository."
