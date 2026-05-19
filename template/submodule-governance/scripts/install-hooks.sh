#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"
script_dir="$(cd "$(dirname "$0")" && pwd)"

mkdir -p .git/hooks
cp "$script_dir/pre-push-hook.sh" .git/hooks/pre-push
chmod +x .git/hooks/pre-push

echo "Installed pre-push hook to .git/hooks/pre-push"
