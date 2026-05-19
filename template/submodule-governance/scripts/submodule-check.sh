#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if [[ -f ".submodule-governance.env" ]]; then
  # shellcheck disable=SC1091
  source ".submodule-governance.env"
fi

if [[ ! -f .gitmodules ]]; then
  echo "No .gitmodules found. Skip submodule checks."
  exit 0
fi

require_pushed="${SUBMODULE_REQUIRE_PUSHED:-0}"
has_error=0

print_error() {
  echo "ERROR: $1"
  has_error=1
}

print_warn() {
  echo "WARN: $1"
}

submodule_paths=()
while IFS= read -r line; do
  path="${line#* }"
  submodule_paths+=("$path")
done < <(git config --file .gitmodules --get-regexp path || true)

if [[ ${#submodule_paths[@]} -eq 0 ]]; then
  echo "No submodule paths defined in .gitmodules."
  exit 0
fi

while IFS= read -r status_line; do
  [[ -z "$status_line" ]] && continue
  state="${status_line:0:1}"
  rest="${status_line:1}"
  path="${rest#* }"
  path="${path%% *}"

  if [[ "$state" == "-" ]]; then
    print_error "submodule '$path' is not initialized. Run: .git/submodule-governance/submodule-sync.sh"
  fi
done < <(git submodule status --recursive || true)

for path in "${submodule_paths[@]}"; do
  if [[ ! -d "$path/.git" && ! -f "$path/.git" ]]; then
    print_error "submodule '$path' directory is missing. Run: .git/submodule-governance/submodule-sync.sh"
    continue
  fi

  if [[ -n "$(git -C "$path" status --porcelain)" ]]; then
    print_error "submodule '$path' has uncommitted changes."
  fi

  indexed_sha="$(git ls-files -s -- "$path" | awk '{print $2}')"
  head_sha="$(git -C "$path" rev-parse HEAD)"
  if [[ -n "$indexed_sha" && "$indexed_sha" != "$head_sha" ]]; then
    print_error "submodule '$path' HEAD ($head_sha) differs from main repo pointer ($indexed_sha). Commit pointer with: git add $path && git commit"
  fi

  if ! git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    if [[ "$require_pushed" == "1" ]]; then
      print_error "submodule '$path' has no upstream branch configured."
    else
      print_warn "submodule '$path' has no upstream branch configured."
    fi
    continue
  fi

  if ! git -C "$path" merge-base --is-ancestor HEAD '@{u}'; then
    if [[ "$require_pushed" == "1" ]]; then
      print_error "submodule '$path' HEAD is not pushed to upstream yet."
    else
      print_warn "submodule '$path' HEAD is not pushed to upstream yet."
    fi
  fi
done

if git diff --cached --name-only --diff-filter=AM | grep -qE '.*'; then
  while IFS= read -r staged_path; do
    if printf '%s\n' "${submodule_paths[@]}" | grep -Fxq "$staged_path"; then
      print_error "submodule pointer '$staged_path' is staged but not committed."
    fi
  done < <(git diff --cached --name-only)
fi

if [[ "$has_error" -ne 0 ]]; then
  echo "Submodule checks failed. Push blocked."
  exit 1
fi

if [[ "$require_pushed" == "1" ]]; then
  echo "Submodule checks passed (strict mode)."
else
  echo "Submodule checks passed (non-strict mode)."
fi
