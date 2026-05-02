#!/bin/bash
# gate_codex_safe_write.sh — Hook-free safety gate for Codex CLI agents
# Replaces PreToolUse hooks that Codex CLI doesn't support.
# Run BEFORE committing or reporting to catch violations that hooks would have blocked.
#
# Usage: bash scripts/gates/gate_codex_safe_write.sh [report_yaml_path]
#
# Checks:
#   1. yaml.dump/safe_dump in recent bash history → BLOCK
#   2. Report YAML syntax validation (if path provided)
#   3. lessons.yaml direct edit detection (git diff)
#   4. Uncommitted operational YAML with Edit tool patterns

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ERRORS=0
REPORT_PATH="${1:-}"

echo "=== Codex Safe Write Gate ==="

# Check 1: yaml.dump in recent commits (last 3)
# Exclude gate scripts themselves (they grep for yaml.dump and contain the pattern as detection target)
_YAML_DUMP_HITS=$(git -C "$SCRIPT_DIR" diff HEAD~3..HEAD --unified=0 -- ':!scripts/gates/' ':!.claude/hooks/' ':!docs/research/' 2>/dev/null | grep -cE 'yaml\.(dump|safe_dump)' || true)
if [[ "${_YAML_DUMP_HITS:-0}" -gt 0 ]]; then
    echo "BLOCK: yaml.dump/safe_dump detected in recent commits. Use yaml_field_set.sh instead." >&2
    ERRORS=$((ERRORS + 1))
fi

# Check 2: Report YAML syntax validation
if [[ -n "$REPORT_PATH" && -f "$REPORT_PATH" ]]; then
    if ! python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$REPORT_PATH" 2>/dev/null; then
        echo "BLOCK: Report YAML parse error: $REPORT_PATH" >&2
        ERRORS=$((ERRORS + 1))
    else
        echo "  PASS: Report YAML syntax OK"
    fi
fi

DIRTY_YAML=$(git -C "$SCRIPT_DIR" diff --name-only -- '*.yaml' '*.yml' 2>/dev/null || true)

# Check 3: lessons.yaml direct edit (should use lesson_write.sh)
if grep -q 'lessons\.yaml$' <<<"$DIRTY_YAML"; then
    echo "WARN: lessons.yaml has uncommitted changes. Use lesson_write.sh for modifications." >&2
fi

# Check 4: Operational YAML modified directly (queue/, tasks/, inbox/)
DIRTY_OPS=$(grep -E '^(queue|tasks|inbox)/' <<<"$DIRTY_YAML" | head -5 || true)
if [[ -n "$DIRTY_OPS" ]]; then
    echo "  INFO: Operational YAML modified: $DIRTY_OPS"
    echo "  Ensure yaml_field_set.sh or inbox_write.sh was used (not direct Edit)."
fi

echo ""
if [[ $ERRORS -eq 0 ]]; then
    echo "=== PASS: All checks clear ==="
    exit 0
else
    echo "=== BLOCK: $ERRORS error(s) found ===" >&2
    exit 1
fi
