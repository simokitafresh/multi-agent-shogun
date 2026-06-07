#!/usr/bin/env bash
# safe_rm.sh — Block rm outside project tree (D002)
# Source this file, then use safe_rm instead of rm for destructive operations.
# Part of multi-agent-shogun destructive operation safety (cmd_147)

# project_rootをsource時1回だけ計算 (cd+pwd+realpath per-call を排除)
_safe_rm_self="${BASH_SOURCE[0]}"
[[ "$_safe_rm_self" != /* ]] && _safe_rm_self="$PWD/$_safe_rm_self"
_SAFE_RM_PROJECT_ROOT="${_safe_rm_self%/scripts/lib/safe_rm.sh}"
unset _safe_rm_self

safe_rm() {
  if [[ $# -eq 0 ]]; then
    echo "safe_rm: no arguments provided" >&2
    return 1
  fi

  local project_root="$_SAFE_RM_PROJECT_ROOT"

  # Validate each path argument (skip flags like -r, -f, -rf)
  local arg
  for arg in "$@"; do
    # Skip flags
    if [[ "$arg" == -* ]]; then
      continue
    fi

    local resolved
    resolved=$(realpath "$arg" 2>/dev/null || echo "$arg")

    if [[ "$resolved" != "$project_root"/* ]]; then
      echo "BLOCKED: rm outside project tree: $resolved (D002)" >&2
      return 1
    fi
  done

  # All paths validated — execute rm with original arguments
  rm "$@"
}
