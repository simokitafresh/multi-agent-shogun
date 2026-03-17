#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

resolve_ruff_cmd() {
    if [ -x "$ROOT_DIR/.venv/bin/ruff" ]; then
        printf '%s\n' "$ROOT_DIR/.venv/bin/ruff"
        return 0
    fi
    if [ -x "$ROOT_DIR/.venv/bin/python" ]; then
        printf '%s\n' "$ROOT_DIR/.venv/bin/python -m ruff"
        return 0
    fi
    if [ -x "$HOME/.local/bin/ruff" ]; then
        printf '%s\n' "$HOME/.local/bin/ruff"
        return 0
    fi
    if command -v ruff >/dev/null 2>&1; then
        printf '%s\n' "ruff"
        return 0
    fi
    if python3 -m pip show ruff >/dev/null 2>&1; then
        printf '%s\n' "python3 -m ruff"
        return 0
    fi

    echo "ERROR: ruff not found. Install it before committing." >&2
    return 1
}

mapfile -t staged_files < <(
    git -C "$ROOT_DIR" diff --cached --name-only --diff-filter=ACMR | sed '/^$/d'
)

if [ "${#staged_files[@]}" -eq 0 ]; then
    exit 0
fi

blocked_files="$(printf '%s\n' "${staged_files[@]}" | grep '^queue/' || true)"
if [ -n "$blocked_files" ]; then
    echo "ERROR: queue/下のファイルがstageされています。git reset HEAD queue/ で除外してください" >&2
    echo "Blocked files:" >&2
    printf '%s\n' "$blocked_files" >&2
    exit 1
fi

if printf '%s\n' "${staged_files[@]}" | grep -qE '^instructions/(common|cli_specific|roles)/|^instructions/(ashigaru|karo|shogun)\.md$'; then
    echo "🔄 Source templates changed. Regenerating instruction files..."
    (
        cd "$ROOT_DIR"
        bash scripts/build_instructions.sh > /dev/null
        git add instructions/generated/ AGENTS.md agents/default/ .github/copilot-instructions.md 2>/dev/null || true
    )
    echo "✅ Generated files updated and staged."
    mapfile -t staged_files < <(
        git -C "$ROOT_DIR" diff --cached --name-only --diff-filter=ACMR | sed '/^$/d'
    )
fi

mapfile -t python_files < <(printf '%s\n' "${staged_files[@]}" | grep -E '\.py$' || true)
mapfile -t shell_files < <(printf '%s\n' "${staged_files[@]}" | grep -E '\.(sh|bash)$' || true)
mapfile -t js_files < <(printf '%s\n' "${staged_files[@]}" | grep -E '\.(js|jsx|ts|tsx)$' || true)

if [ "${#python_files[@]}" -gt 0 ]; then
    ruff_cmd="$(resolve_ruff_cmd)"
    read -r -a ruff_parts <<<"$ruff_cmd"
    (
        cd "$ROOT_DIR"
        "${ruff_parts[@]}" check --fix -- "${python_files[@]}"
        "${ruff_parts[@]}" format -- "${python_files[@]}"
        "${ruff_parts[@]}" check -- "${python_files[@]}"
    )
    git -C "$ROOT_DIR" add -- "${python_files[@]}"
fi

if [ "${#js_files[@]}" -gt 0 ]; then
    (
        cd "$ROOT_DIR"
        npx --yes @biomejs/biome check --write -- "${js_files[@]}"
    )
    git -C "$ROOT_DIR" add -- "${js_files[@]}"
fi

if [ "${#shell_files[@]}" -gt 0 ]; then
    (
        cd "$ROOT_DIR"
        shellcheck -- "${shell_files[@]}"
    )
fi
