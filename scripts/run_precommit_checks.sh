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
        "${ruff_parts[@]}" format -- "${python_files[@]}"
    )
    git -C "$ROOT_DIR" add -- "${python_files[@]}"

    # Compare the final staged bytes with HEAD. Existing debt is allowed; only
    # an increase in identical code+message diagnostics blocks the commit.
    _ruff_ratchet_dir="$(mktemp -d)"
    trap 'rm -rf "${_ruff_ratchet_dir:-}"' EXIT
    : > "$_ruff_ratchet_dir/head.jsonl"
    : > "$_ruff_ratchet_dir/staged.jsonl"
    for _ruff_file in "${python_files[@]}"; do
        _ruff_head_rc=0
        _ruff_staged_rc=0
        if git -C "$ROOT_DIR" cat-file -e "HEAD:$_ruff_file" 2>/dev/null; then
            git -C "$ROOT_DIR" show "HEAD:$_ruff_file" |
                "${ruff_parts[@]}" check --output-format json --stdin-filename "$_ruff_file" - \
                    >> "$_ruff_ratchet_dir/head.jsonl" || _ruff_head_rc=$?
        else
            printf '[]\n' >> "$_ruff_ratchet_dir/head.jsonl"
        fi
        git -C "$ROOT_DIR" show ":$_ruff_file" |
            "${ruff_parts[@]}" check --output-format json --stdin-filename "$_ruff_file" - \
                >> "$_ruff_ratchet_dir/staged.jsonl" || _ruff_staged_rc=$?
        if [ "$_ruff_head_rc" -gt 1 ] || [ "$_ruff_staged_rc" -gt 1 ]; then
            echo "ERROR: ruff JSON diagnostics failed for $_ruff_file" >&2
            exit 1
        fi
        printf '\n' >> "$_ruff_ratchet_dir/head.jsonl"
        printf '\n' >> "$_ruff_ratchet_dir/staged.jsonl"
    done
    python3 - "$_ruff_ratchet_dir/head.jsonl" "$_ruff_ratchet_dir/staged.jsonl" <<'PY'
import collections
import json
import sys


def counts(path):
    result = collections.Counter()
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            for item in json.loads(line):
                result[(item.get("code"), item.get("message"))] += 1
    return result


baseline = counts(sys.argv[1])
staged = counts(sys.argv[2])
regressions = [
    (code, message, baseline[key], count)
    for key, count in sorted(staged.items())
    for code, message in [key]
    if count > baseline[key]
]
if regressions:
    print("ERROR: staged Python files add Ruff diagnostics:", file=sys.stderr)
    for code, message, before, after in regressions:
        print(f"  {code}: {message} ({before} -> {after})", file=sys.stderr)
    raise SystemExit(1)
PY
fi

if [ "${#js_files[@]}" -gt 0 ]; then
    (
        cd "$ROOT_DIR"
        npx --yes @biomejs/biome check --write -- "${js_files[@]}"
    )
    git -C "$ROOT_DIR" add -- "${js_files[@]}"
fi

if [ "${#shell_files[@]}" -gt 0 ]; then
    if ! command -v shellcheck >/dev/null 2>&1; then
        echo "ERROR: shellcheck not found. Install it before committing shell scripts." >&2
        exit 1
    fi
    if [ "${#shell_files[@]}" -eq 1 ]; then
        # 1ファイル: 直接呼び出し（並列オーバーヘッド不要）
        (
            cd "$ROOT_DIR"
            shellcheck -- "${shell_files[@]}"
        )
    else
        # 複数ファイル: 並列shellcheck（N×~230ms → ~230ms wall time）
        _sc_tmp="$(mktemp -d)"
        _sc_fail=0
        for _sc_f in "${shell_files[@]}"; do
            ( cd "$ROOT_DIR" && shellcheck -- "$_sc_f" > "$_sc_tmp/${_sc_f//\//_}" 2>&1; printf '%s' $? > "$_sc_tmp/${_sc_f//\//_}.exit" ) &
        done
        wait
        for _sc_f in "${shell_files[@]}"; do
            _sc_out="$_sc_tmp/${_sc_f//\//_}"
            [ -s "$_sc_out" ] && cat "$_sc_out"
            _sc_exit=$(cat "$_sc_tmp/${_sc_f//\//_}.exit" 2>/dev/null || echo 0)
            [ "$_sc_exit" != "0" ] && _sc_fail=1
        done
        rm -rf "$_sc_tmp"
        if [ "$_sc_fail" -eq 1 ]; then exit 1; fi
    fi
fi
