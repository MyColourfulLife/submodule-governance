#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./bootstrap.sh [target_repo_path] [--strict]

Examples:
  ./bootstrap.sh
  ./bootstrap.sh /path/to/existing/repo
  ./bootstrap.sh /path/to/existing/repo --strict
EOF
}

target_repo=""
strict_mode="0"

for arg in "$@"; do
  case "$arg" in
    --strict)
      strict_mode="1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$target_repo" ]]; then
        target_repo="$arg"
      else
        echo "Unexpected argument: $arg"
        usage
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$target_repo" ]]; then
  target_repo="$(pwd)"
fi

target_repo="$(cd "$target_repo" && pwd)"
template_root="$(cd "$(dirname "$0")/template/submodule-governance" && pwd)"

if [[ ! -d "$target_repo/.git" ]]; then
  echo "Target is not a git repository: $target_repo"
  exit 1
fi

mkdir -p "$target_repo/scripts"

cp "$template_root/scripts/submodule-check.sh" "$target_repo/scripts/submodule-check.sh"
cp "$template_root/scripts/submodule-sync.sh" "$target_repo/scripts/submodule-sync.sh"
cp "$template_root/scripts/pre-push-hook.sh" "$target_repo/scripts/pre-push-hook.sh"
cp "$template_root/scripts/install-hooks.sh" "$target_repo/scripts/install-hooks.sh"

chmod +x \
  "$target_repo/scripts/submodule-check.sh" \
  "$target_repo/scripts/submodule-sync.sh" \
  "$target_repo/scripts/pre-push-hook.sh" \
  "$target_repo/scripts/install-hooks.sh"

config_file="$target_repo/.submodule-governance.env"
if [[ ! -f "$config_file" ]]; then
  cat >"$config_file" <<EOF
# 0: only warn when submodule HEAD is not pushed to upstream.
# 1: fail and block push when submodule HEAD is not pushed to upstream.
SUBMODULE_REQUIRE_PUSHED=$strict_mode
EOF
else
  if grep -q '^SUBMODULE_REQUIRE_PUSHED=' "$config_file"; then
    sed -i.bak "s/^SUBMODULE_REQUIRE_PUSHED=.*/SUBMODULE_REQUIRE_PUSHED=$strict_mode/" "$config_file"
    rm -f "$config_file.bak"
  else
    printf "\nSUBMODULE_REQUIRE_PUSHED=%s\n" "$strict_mode" >> "$config_file"
  fi
fi

(
  cd "$target_repo"
  ./scripts/install-hooks.sh
)

echo "Running initial check..."
(
  cd "$target_repo"
  ./scripts/submodule-check.sh || true
)

echo "Bootstrap complete."
echo "Target repo: $target_repo"
if [[ "$strict_mode" == "1" ]]; then
  echo "Mode: strict (SUBMODULE_REQUIRE_PUSHED=1)"
else
  echo "Mode: non-strict (SUBMODULE_REQUIRE_PUSHED=0)"
fi
