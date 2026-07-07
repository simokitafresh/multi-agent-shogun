#!/usr/bin/env bats
# test_causal_backlink_counts.bats — cmd_karo_hotfix_rg_fallback_causal_backlinks_202607080241
# rg実体がPATHに無い環境(WSL2でripgrep未インストール)でも、causal_backlink_counts.shが
# FileNotFoundError/空出力に沈まずPure Pythonフォールバックで決定論的に動作することを検証する。

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/scripts/causal_backlink_counts.sh"
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/causal_backlink.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/context" "$TEST_TMPDIR/docs/research" \
             "$TEST_TMPDIR/skills/myskill" "$TEST_TMPDIR/memory" \
             "$TEST_TMPDIR/docs/semantic-index" "$TEST_TMPDIR/instructions"

    # alpha: referenced by memory/note.md ([[alpha]]) + docs/research/gamma.md (path ref) → count=2
    cat > "$TEST_TMPDIR/context/alpha.md" <<'EOF'
# Alpha
See [[beta]] for more.
EOF
    # beta: referenced by context/alpha.md ([[beta]]) + docs/semantic-index/index.md ([[beta]]) → count=2
    cat > "$TEST_TMPDIR/context/beta.md" <<'EOF'
# Beta
No outgoing links here.
EOF
    # gamma: referenced by skills/myskill/SKILL.md ([[gamma]]) → count=1
    cat > "$TEST_TMPDIR/docs/research/gamma.md" <<'EOF'
# Gamma
Directly cites context/alpha.md as source.
EOF
    # myskill/SKILL.md: referenced by nobody → count=0
    cat > "$TEST_TMPDIR/skills/myskill/SKILL.md" <<'EOF'
# My Skill
Uses [[gamma]] internally.
EOF
    cat > "$TEST_TMPDIR/memory/note.md" <<'EOF'
memory is a --no-ignore search dir: [[alpha]] mention here must still count.
EOF
    cat > "$TEST_TMPDIR/docs/semantic-index/index.md" <<'EOF'
semantic-index is a --no-ignore search dir: [[beta]] mention here must still count.
EOF
    cat > "$TEST_TMPDIR/instructions/guide.md" <<'EOF'
No links in this file.
EOF
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "rg absent from PATH: fallback still returns deterministic non-empty counts (no silent empty output)" {
    # Strip any real rg binary from PATH while keeping core utils/python3/git usable —
    # reproduces the original bug precondition (rg not installed on WSL2).
    local minimal_bin
    minimal_bin="$(mktemp -d)"
    for tool in python3 git bash sh cat mkdir rm mktemp sort dirname cd env; do
        local real_path
        real_path="$(command -v "$tool" 2>/dev/null)" || continue
        ln -s "$real_path" "$minimal_bin/$tool"
    done

    run env -i PATH="$minimal_bin" HOME="$HOME" \
        CAUSAL_BACKLINK_COUNTS_ROOT="$TEST_TMPDIR" \
        bash "$SCRIPT"
    rm -rf "$minimal_bin"

    [ "$status" -eq 0 ]
    [ -n "$output" ]
    [[ "$output" == *"context/alpha.md"* ]]
    [[ "$output" == *"context/beta.md"* ]]
    [[ "$output" == *"docs/research/gamma.md"* ]]
    [[ "$output" == *"skills/myskill/SKILL.md"* ]]
}

@test "forced fallback: wiki-links and path-references resolve to correct backlink counts" {
    run env CAUSAL_BACKLINK_COUNTS_ROOT="$TEST_TMPDIR" CAUSAL_BACKLINK_COUNTS_FORCE_FALLBACK=1 \
        bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'2\tcontext/alpha.md\talpha'* ]]
    [[ "$output" == *$'2\tcontext/beta.md\tbeta'* ]]
    [[ "$output" == *$'1\tdocs/research/gamma.md\tgamma'* ]]
    [[ "$output" == *$'0\tskills/myskill/SKILL.md\tmyskill'* ]]
}

@test "forced fallback: --zero isolates only zero-backlink files" {
    run env CAUSAL_BACKLINK_COUNTS_ROOT="$TEST_TMPDIR" CAUSAL_BACKLINK_COUNTS_FORCE_FALLBACK=1 \
        bash "$SCRIPT" --zero --limit 20
    [ "$status" -eq 0 ]
    [[ "$output" == *"skills/myskill/SKILL.md"* ]]
    [[ "$output" != *"context/alpha.md"* ]]
    [[ "$output" != *"context/beta.md"* ]]
    [[ "$output" != *"docs/research/gamma.md"* ]]
}

@test "forced fallback: --limit truncates emitted rows" {
    run env CAUSAL_BACKLINK_COUNTS_ROOT="$TEST_TMPDIR" CAUSAL_BACKLINK_COUNTS_FORCE_FALLBACK=1 \
        bash "$SCRIPT" --limit 1
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]
}

@test "rg present on PATH: rg branch produces the same backlink counts as the fallback (parity)" {
    local rg_bin=""
    for candidate in /usr/bin/rg /usr/local/bin/rg "$HOME/.local/bin/rg" /snap/bin/rg; do
        if [ -x "$candidate" ]; then
            rg_bin="$candidate"
            break
        fi
    done
    [ -n "$rg_bin" ] || skip "no real rg binary available in this environment"
    local rg_dir
    rg_dir="$(dirname "$rg_bin")"

    run env PATH="$rg_dir:$PATH" CAUSAL_BACKLINK_COUNTS_ROOT="$TEST_TMPDIR" bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'2\tcontext/alpha.md\talpha'* ]]
    [[ "$output" == *$'2\tcontext/beta.md\tbeta'* ]]
    [[ "$output" == *$'1\tdocs/research/gamma.md\tgamma'* ]]
    [[ "$output" == *$'0\tskills/myskill/SKILL.md\tmyskill'* ]]
}

@test "forced fallback inside a git repo: gitignore excludes context/docs/skills but not memory (--no-ignore parity)" {
    (
        cd "$TEST_TMPDIR" || exit 1
        git init -q
        git config user.email "test@example.com"
        git config user.name "test"
        # gitignore excludes beta.md from the gitignore-respecting dirs
        echo "context/beta.md" > .gitignore
        git add -A
        git commit -q -m "fixture"
    )

    run env CAUSAL_BACKLINK_COUNTS_ROOT="$TEST_TMPDIR" CAUSAL_BACKLINK_COUNTS_FORCE_FALLBACK=1 \
        bash "$SCRIPT"
    [ "$status" -eq 0 ]
    # beta.md is gitignored → excluded from targets (mirrors `rg --files` gitignore-respecting behavior)
    [[ "$output" != *"context/beta.md"* ]]
    # alpha.md is still tracked/whitelisted → present, count unaffected by beta.md's
    # exclusion (alpha's sources are memory/note.md + docs/research/gamma.md, neither
    # of which reference beta).
    [[ "$output" == *$'2\tcontext/alpha.md\talpha'* ]]
}
