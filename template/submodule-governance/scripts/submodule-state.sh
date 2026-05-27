#!/usr/bin/env bash
# Machine-readable, read-only state records for CLI and MCP adapters.
set -eo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/submodule-common.sh"

sg_init
printf 'meta\trequirePushed\t%s\n' "$require_pushed"
printf 'meta\tconfigFile\t%s\n' "$config_file"

for message in "${config_errors[@]}"; do printf 'configError\t%s\n' "$message"; done
for path in "${submodule_paths[@]}"; do printf 'submodule\t%s\n' "$path"; done
for path in "${missing_paths[@]}"; do printf 'missing\t%s\n' "$path"; done
for path in "${dirty_paths[@]}"; do printf 'dirty\t%s\n' "$path"; done
for path in "${no_upstream_paths[@]}"; do printf 'noUpstream\t%s\n' "$path"; done
for path in "${unpushed_paths[@]}"; do printf 'unpushed\t%s\n' "$path"; done
for path in "${staged_pointer_paths[@]}"; do printf 'stagedPointer\t%s\n' "$path"; done
for i in "${!mismatch_paths[@]}"; do
  printf 'mismatch\t%s\t%s\t%s\n' "${mismatch_paths[$i]}" "${mismatch_indexed_shas[$i]}" "${mismatch_head_shas[$i]}"
done
for i in "${!branch_mismatch_paths[@]}"; do
  printf 'branchMismatch\t%s\t%s\t%s\n' "${branch_mismatch_paths[$i]}" "${branch_current_values[$i]}" "${branch_expected_values[$i]}"
done
