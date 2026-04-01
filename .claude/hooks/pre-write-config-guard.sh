#!/usr/bin/env bash
set -eu

payload="$(cat 2>/dev/null || true)"
[[ -z "${payload//[[:space:]]/}" ]] && exit 0

# Fast-path: skip if not Write/Edit
[[ "$payload" != *'"Write"'* && "$payload" != *'"Edit"'* ]] && exit 0

# Fast-path: skip if no protected config file keywords
[[ "$payload" != *'pyproject.toml'* && \
   "$payload" != *'eslintrc'* && \
   "$payload" != *'eslint.config'* && \
   "$payload" != *'biome.json'* && \
   "$payload" != *'prettierrc'* && \
   "$payload" != *'tsconfig.json'* && \
   "$payload" != *'.ruff.toml'* && \
   "$payload" != *'setup.cfg'* ]] && exit 0

# Extract file_path with jq
file_path="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .file_path // .filePath // .path // empty' 2>/dev/null)" || exit 0
[[ -z "$file_path" ]] && exit 0

# Check basename against protected patterns
basename="${file_path##*/}"
case "$basename" in
    pyproject.toml|.eslintrc|.eslintrc.*|eslint.config*|biome.json|.prettierrc|.prettierrc.*|tsconfig.json|.ruff.toml|setup.cfg)
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"ERROR: %s is a protected config file.\\nWHY: Linter/formatter configs must not be modified to suppress violations.\\nFIX: Fix the code that triggered the violation, not the linter config."}}\n' "$basename"
        exit 1
        ;;
esac

exit 0
