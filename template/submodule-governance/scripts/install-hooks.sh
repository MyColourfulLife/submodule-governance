#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"
script_dir="$(cd "$(dirname "$0")" && pwd)"
git_dir="$(git rev-parse --git-dir)"
case "$git_dir" in
  /*) ;;
  *) git_dir="$repo_root/$git_dir" ;;
esac

configured_hooks_path="$(git config --get core.hooksPath || true)"
if [[ -n "$configured_hooks_path" ]]; then
  case "$configured_hooks_path" in
    /*) hooks_dir="$configured_hooks_path" ;;
    *) hooks_dir="$repo_root/$configured_hooks_path" ;;
  esac
else
  hooks_dir="$git_dir/hooks"
fi

hook_file="$hooks_dir/pre-push"
use_husky_wrapper=0
if [[ "$hooks_dir" == "$repo_root/.husky/_" ]]; then
  hook_file="$repo_root/.husky/pre-push"
  use_husky_wrapper=1
fi

if [[ -f "$hook_file" ]]; then
  if grep -q 'submodule-governance/pre-push-hook.sh' "$hook_file"; then
    echo "Existing pre-push hook already invokes submodule governance: $hook_file"
    exit 0
  fi

  if [[ "$use_husky_wrapper" != "1" ]] &&
     cmp -s "$script_dir/pre-push-hook.sh" "$hook_file"; then
    cp "$script_dir/pre-push-hook.sh" "$hook_file"
    chmod +x "$hook_file"
    echo "Updated pre-push hook at $hook_file"
    exit 0
  fi

  echo "Existing pre-push hook was not overwritten: $hook_file"
  echo "Add this command to that hook, then run installation again:"
  echo '  "$(git rev-parse --git-dir)/submodule-governance/pre-push-hook.sh" "$@"'
  exit 1
fi

mkdir -p "$(dirname "$hook_file")"
if [[ "$use_husky_wrapper" == "1" ]]; then
  cat >"$hook_file" <<'EOF'
#!/usr/bin/env sh
"$(git rev-parse --git-dir)/submodule-governance/pre-push-hook.sh" "$@"
EOF
else
  cp "$script_dir/pre-push-hook.sh" "$hook_file"
fi
chmod +x "$hook_file"

echo "Installed pre-push hook to $hook_file"
