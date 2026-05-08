#!/usr/bin/env bats
# test_build_system.bats — ビルドシステム（build_instructions.sh）ユニットテスト
# Phase 2+3 品質テスト基盤
#
# テスト構成:
#   - ビルド実行テスト: スクリプト正常終了、ディレクトリ生成
#   - ファイル生成テスト: claude/codex/copilot各ロールの生成確認
#   - 内容検証テスト: 空でないこと、ロール名・CLI固有セクション含有
#   - AGENTS.md / copilot-instructions.md 生成テスト
#   - 冪等性テスト: 2回ビルドで差分なし
#
# Phase 2+3未実装テストについて:
#   copilot生成、AGENTS.md、copilot-instructions.md のテストは
#   build_instructions.shが拡張されるまでFAILする（受入基準）。
#   SKIP は使用しない（SKIP=0ルール遵守）。

# --- セットアップ ---

setup_file() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export BUILD_SCRIPT="$PROJECT_ROOT/scripts/build_instructions.sh"
    export OUTPUT_DIR="$PROJECT_ROOT/instructions/generated"
    export BUILD_STATUS_FILE BUILD_HASH_FILE BUILD_HASH2_FILE
    BUILD_STATUS_FILE="$(mktemp)"
    BUILD_HASH_FILE="$(mktemp)"
    BUILD_HASH2_FILE="$(mktemp)"

    # パーツディレクトリの存在確認（前提条件）
    [ -d "$PROJECT_ROOT/instructions/roles" ] || return 1
    [ -d "$PROJECT_ROOT/instructions/common" ] || return 1
    [ -d "$PROJECT_ROOT/instructions/cli_specific" ] || return 1

    # cmd_2116: agents test temp_repo → setup_file()で1回のみ事前構築
    export AGENTS_TMPDIR AGENTS_BUILD_STATUS_FILE AGENTS_BUILD_OUTPUT_FILE
    AGENTS_TMPDIR="$(mktemp -d)"
    AGENTS_BUILD_STATUS_FILE="$(mktemp)"
    AGENTS_BUILD_OUTPUT_FILE="$(mktemp)"

    mkdir -p \
        "$AGENTS_TMPDIR/scripts/lib" \
        "$AGENTS_TMPDIR/config" \
        "$AGENTS_TMPDIR/instructions/roles" \
        "$AGENTS_TMPDIR/instructions/common" \
        "$AGENTS_TMPDIR/instructions/cli_specific"
    cp "$PROJECT_ROOT/scripts/build_instructions.sh" "$AGENTS_TMPDIR/scripts/build_instructions.sh"
    cp "$PROJECT_ROOT/scripts/lib/cli_lookup.sh" "$AGENTS_TMPDIR/scripts/lib/cli_lookup.sh"
    cat > "$AGENTS_TMPDIR/CLAUDE.md" <<'EOF'
---
role: root
---
Auto-load file for Claude Code.
EOF
    cat > "$AGENTS_TMPDIR/config/settings.yaml" <<'EOF'
cli:
  default: claude
EOF
    cat > "$AGENTS_TMPDIR/config/cli_profiles.yaml" <<'EOF'
profiles:
  claude:
    display_name: "Claude Display"
  copilot:
    display_name: "Copilot Display"
  codex:
    display_name: "Codex Display"
EOF
    for role in shogun karo gunshi ashigaru; do
        cat > "$AGENTS_TMPDIR/instructions/${role}.md" <<EOF
---
role: ${role}
---
EOF
        printf '%s role\n' "$role" > "$AGENTS_TMPDIR/instructions/roles/${role}_role.md"
    done
    printf 'protocol\n'    > "$AGENTS_TMPDIR/instructions/common/protocol.md"
    printf 'task flow\n'   > "$AGENTS_TMPDIR/instructions/common/task_flow.md"
    printf 'forbidden\n'   > "$AGENTS_TMPDIR/instructions/common/forbidden_actions.md"
    printf 'claude tools\n'  > "$AGENTS_TMPDIR/instructions/cli_specific/claude_tools.md"
    printf 'codex tools\n'   > "$AGENTS_TMPDIR/instructions/cli_specific/codex_tools.md"
    printf 'copilot tools\n' > "$AGENTS_TMPDIR/instructions/cli_specific/copilot_tools.md"
    printf 'kimi tools\n'    > "$AGENTS_TMPDIR/instructions/cli_specific/kimi_tools.md"

    # cmd_2116: agents buildをバックグラウンドで並列実行 (main build 1と同時。I/O競合なし: /tmp vs /mnt/c)
    local _agents_pid
    (
        out=$(bash "$AGENTS_TMPDIR/scripts/build_instructions.sh" 2>&1)
        st=$?
        printf '%s\n' "$st"  > "$AGENTS_BUILD_STATUS_FILE"
        printf '%s\n' "$out" > "$AGENTS_BUILD_OUTPUT_FILE"
    ) &
    _agents_pid=$!

    # main build 1 (agents buildと並列)
    bash "$BUILD_SCRIPT" > /dev/null 2>&1
    printf '%s\n' "$?" > "$BUILD_STATUS_FILE"
    # cmd_2116: find -exec md5sum (16サブプロセス) → md5sum glob (1サブプロセス)
    md5sum "$OUTPUT_DIR"/*.md 2>/dev/null | sort > "$BUILD_HASH_FILE"

    # cmd_2116: 冪等性チェック用 2回目build → setup_file()に移動 (test bodyから除去)
    bash "$BUILD_SCRIPT" > /dev/null 2>&1
    md5sum "$OUTPUT_DIR"/*.md 2>/dev/null | sort > "$BUILD_HASH2_FILE"

    wait "$_agents_pid" || true
}

teardown_file() {
    rm -f "${BUILD_STATUS_FILE:-}" "${BUILD_HASH_FILE:-}" "${BUILD_HASH2_FILE:-}"
    rm -f "${AGENTS_BUILD_STATUS_FILE:-}" "${AGENTS_BUILD_OUTPUT_FILE:-}"
    rm -rf "${AGENTS_TMPDIR:-}"
}

# cmd_2116: setup()のサブシェル削除 (PROJECT_ROOT/BUILD_SCRIPT/OUTPUT_DIRはsetup_file()でexport済み)
setup() { :; }

find_forbidden_codex_clear_refs() {
    local file="$1"
    grep -nE '(/clear Recovery|/clear recovery|/clear前|/clear後|after /clear|After /clear|pre-/clear|無条件/clear|家老/clear|test /clear recovery|sending /clear|prepare for /clear|/clearされた|`/clear`)' "$file" 2>/dev/null \
        | grep -Ev 'clear_command|/shogun-clear-prep|`/clear` \(closest\)|`/clear` context reset|instead of `/clear`' || true
}

# =============================================================================
# ビルド実行テスト
# =============================================================================

@test "build: build_instructions.sh exits with status 0" {
    [ "$(cat "$BUILD_STATUS_FILE")" -eq 0 ]
}

@test "build: generated/ directory exists after build" {
    [ -d "$OUTPUT_DIR" ]
}

@test "build: generated/ contains at least 8 files" {
    local count
    count=$(find "$OUTPUT_DIR" -name "*.md" -type f | wc -l)
    [ "$count" -ge 8 ]
}

@test "build: parallel child failure makes build fail" {
    local tmpdir role
    tmpdir="$(mktemp -d)"
    mkdir -p \
        "$tmpdir/scripts/lib" \
        "$tmpdir/config" \
        "$tmpdir/instructions/roles" \
        "$tmpdir/instructions/common" \
        "$tmpdir/instructions/cli_specific"
    cp "$PROJECT_ROOT/scripts/build_instructions.sh" "$tmpdir/scripts/build_instructions.sh"
    cp "$PROJECT_ROOT/scripts/lib/cli_lookup.sh" "$tmpdir/scripts/lib/cli_lookup.sh"
    cat > "$tmpdir/CLAUDE.md" <<'EOF'
---
role: root
---
Claude Code root.
EOF
    cat > "$tmpdir/config/settings.yaml" <<'EOF'
cli:
  default: claude
EOF
    cat > "$tmpdir/config/cli_profiles.yaml" <<'EOF'
profiles:
  claude:
    display_name: "Claude"
  codex:
    display_name: "Codex"
EOF
    for role in shogun karo gunshi ashigaru; do
        cat > "$tmpdir/instructions/${role}.md" <<EOF
---
role: ${role}
---
EOF
        if [ "$role" != "karo" ]; then
            printf '%s role\n' "$role" > "$tmpdir/instructions/roles/${role}_role.md"
        fi
    done
    printf 'protocol\n' > "$tmpdir/instructions/common/protocol.md"
    printf 'task flow\n' > "$tmpdir/instructions/common/task_flow.md"
    printf 'forbidden\n' > "$tmpdir/instructions/common/forbidden_actions.md"
    printf 'claude tools\n' > "$tmpdir/instructions/cli_specific/claude_tools.md"
    printf 'codex tools\n' > "$tmpdir/instructions/cli_specific/codex_tools.md"
    printf 'copilot tools\n' > "$tmpdir/instructions/cli_specific/copilot_tools.md"
    printf 'kimi tools\n' > "$tmpdir/instructions/cli_specific/kimi_tools.md"

    run bash "$tmpdir/scripts/build_instructions.sh"
    rm -rf "$tmpdir"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Failed: instruction claude/karo"* ]]
}

# =============================================================================
# ファイル生成テスト — Claude
# =============================================================================

@test "claude: shogun.md generated" {
    [ -f "$OUTPUT_DIR/shogun.md" ]
}

@test "claude: karo.md generated" {
    [ -f "$OUTPUT_DIR/karo.md" ]
}

@test "claude: gunshi.md generated" {
    [ -f "$OUTPUT_DIR/gunshi.md" ]
}

@test "claude: ashigaru.md generated" {
    [ -f "$OUTPUT_DIR/ashigaru.md" ]
}

# =============================================================================
# ファイル生成テスト — Codex
# =============================================================================

@test "codex: codex-shogun.md generated" {
    [ -f "$OUTPUT_DIR/codex-shogun.md" ]
}

@test "codex: codex-karo.md generated" {
    [ -f "$OUTPUT_DIR/codex-karo.md" ]
}

@test "codex: codex-gunshi.md generated" {
    [ -f "$OUTPUT_DIR/codex-gunshi.md" ]
}

@test "codex: codex-ashigaru.md generated" {
    [ -f "$OUTPUT_DIR/codex-ashigaru.md" ]
}

# =============================================================================
# ファイル生成テスト — Copilot (Phase 2+3 受入基準)
# =============================================================================

@test "copilot: copilot-shogun.md generated [Phase 2+3]" {
    [ -f "$OUTPUT_DIR/copilot-shogun.md" ]
}

@test "copilot: copilot-karo.md generated [Phase 2+3]" {
    [ -f "$OUTPUT_DIR/copilot-karo.md" ]
}

@test "copilot: copilot-gunshi.md generated [Phase 2+3]" {
    [ -f "$OUTPUT_DIR/copilot-gunshi.md" ]
}

@test "copilot: copilot-ashigaru.md generated [Phase 2+3]" {
    [ -f "$OUTPUT_DIR/copilot-ashigaru.md" ]
}

# =============================================================================
# 内容検証テスト — 空でないこと
# =============================================================================

@test "content: shogun.md is not empty" {
    [ -s "$OUTPUT_DIR/shogun.md" ]
}

@test "content: karo.md is not empty" {
    [ -s "$OUTPUT_DIR/karo.md" ]
}

@test "content: gunshi.md is not empty" {
    [ -s "$OUTPUT_DIR/gunshi.md" ]
}

@test "content: ashigaru.md is not empty" {
    [ -s "$OUTPUT_DIR/ashigaru.md" ]
}

@test "content: codex-shogun.md is not empty" {
    [ -s "$OUTPUT_DIR/codex-shogun.md" ]
}

@test "content: codex-karo.md is not empty" {
    [ -s "$OUTPUT_DIR/codex-karo.md" ]
}

@test "content: codex-gunshi.md is not empty" {
    [ -s "$OUTPUT_DIR/codex-gunshi.md" ]
}

@test "content: codex-ashigaru.md is not empty" {
    [ -s "$OUTPUT_DIR/codex-ashigaru.md" ]
}

# =============================================================================
# 内容検証テスト — ロール名含有
# =============================================================================

@test "content: shogun.md contains shogun role reference" {
    grep -qi "shogun\|将軍" "$OUTPUT_DIR/shogun.md"
}

@test "content: karo.md contains karo role reference" {
    grep -qi "karo\|家老" "$OUTPUT_DIR/karo.md"
}

@test "content: gunshi.md contains gunshi role reference" {
    grep -qi "gunshi\|軍師" "$OUTPUT_DIR/gunshi.md"
}

@test "content: ashigaru.md contains ninja/ashigaru role reference" {
    grep -qi "ninja\|忍者\|ashigaru\|足軽" "$OUTPUT_DIR/ashigaru.md"
}

@test "content: codex-shogun.md contains shogun role reference" {
    grep -qi "shogun\|将軍" "$OUTPUT_DIR/codex-shogun.md"
}

@test "content: codex-karo.md contains karo role reference" {
    grep -qi "karo\|家老" "$OUTPUT_DIR/codex-karo.md"
}

@test "content: codex-gunshi.md contains gunshi role reference" {
    grep -qi "gunshi\|軍師" "$OUTPUT_DIR/codex-gunshi.md"
}

@test "content: codex-ashigaru.md contains ninja/ashigaru role reference" {
    grep -qi "ninja\|忍者\|ashigaru\|足軽" "$OUTPUT_DIR/codex-ashigaru.md"
}

# =============================================================================
# 内容検証テスト — CLI固有セクション
# =============================================================================

@test "content: claude files contain Claude-specific tools" {
    # Claude Code固有ツール: Read, Write, Edit, Bash等
    grep -qi "claude\|Read\|Write\|Edit\|Bash" "$OUTPUT_DIR/shogun.md"
}

@test "content: codex files contain Codex-specific content" {
    grep -qi "codex\|AGENTS.md\|Codex" "$OUTPUT_DIR/codex-shogun.md"
}

@test "content: copilot files contain Copilot-specific content [Phase 2+3]" {
    grep -qi "copilot\|Copilot" "$OUTPUT_DIR/copilot-shogun.md"
}

# =============================================================================
# AGENTS.md 生成テスト (Phase 2+3 受入基準)
# =============================================================================

@test "agents: AGENTS.md generated [Phase 2+3]" {
    [ -f "$PROJECT_ROOT/AGENTS.md" ]
}

@test "agents: AGENTS.md contains Codex-specific content [Phase 2+3]" {
    [ -f "$PROJECT_ROOT/AGENTS.md" ] && grep -qi "codex\|agent" "$PROJECT_ROOT/AGENTS.md"
}

@test "agents: AGENTS.md prefers codex profile over first non-default profile" {
    # cmd_2116: temp_repo構築+build → setup_file()に移動済み。キャッシュ結果を使用
    local build_exit build_out
    build_exit=$(cat "$AGENTS_BUILD_STATUS_FILE")
    build_out=$(cat "$AGENTS_BUILD_OUTPUT_FILE")
    [ "$build_exit" -eq 0 ]
    [[ "$build_out" == *"Generating: AGENTS.md (codex auto-load)"* ]]
    grep -q "Codex Display" "$AGENTS_TMPDIR/AGENTS.md"
    ! grep -q "Copilot Display" "$AGENTS_TMPDIR/AGENTS.md"
}

# =============================================================================
# copilot-instructions.md 生成テスト (Phase 2+3 受入基準)
# =============================================================================

@test "copilot-inst: .github/copilot-instructions.md generated [Phase 2+3]" {
    [ -f "$PROJECT_ROOT/.github/copilot-instructions.md" ]
}

@test "copilot-inst: contains Copilot-specific content [Phase 2+3]" {
    [ -f "$PROJECT_ROOT/.github/copilot-instructions.md" ] && \
        grep -qi "copilot" "$PROJECT_ROOT/.github/copilot-instructions.md"
}

# =============================================================================
# 冪等性テスト
# =============================================================================

@test "idempotent: second build produces identical output" {
    # cmd_2116: 2回目buildをsetup_file()に移動済み。hash file比較のみ
    if ! cmp -s "$BUILD_HASH_FILE" "$BUILD_HASH2_FILE"; then
        diff -u "$BUILD_HASH_FILE" "$BUILD_HASH2_FILE" >&2 || true
        false
    fi
}

# =============================================================================
# /clear→/new 変換ロジックテスト (AC3: cmd_2468)
# build_instructions.sh generate_agents_md()の変換ロジック検証
# =============================================================================

@test "clear-conv: AGENTS.md has no raw '/clear Recovery' (converted to /new Recovery)" {
    [ -f "$PROJECT_ROOT/AGENTS.md" ]
    ! grep -q "/clear Recovery" "$PROJECT_ROOT/AGENTS.md"
}

@test "clear-conv: AGENTS.md contains '/new Recovery' after conversion" {
    [ -f "$PROJECT_ROOT/AGENTS.md" ]
    grep -q "/new Recovery" "$PROJECT_ROOT/AGENTS.md"
}

@test "clear-conv: AGENTS.md has no raw '/clear前' (converted to /new前)" {
    [ -f "$PROJECT_ROOT/AGENTS.md" ]
    ! grep -q "/clear前" "$PROJECT_ROOT/AGENTS.md"
}

@test "clear-conv: AGENTS.md has no raw backtick /clear backtick (converted)" {
    [ -f "$PROJECT_ROOT/AGENTS.md" ]
    ! grep -qF '`/clear`' "$PROJECT_ROOT/AGENTS.md"
}

@test "clear-conv: AGENTS.md has no '無条件/clear' (converted to 無条件/new)" {
    [ -f "$PROJECT_ROOT/AGENTS.md" ]
    ! grep -q "無条件/clear" "$PROJECT_ROOT/AGENTS.md"
}

@test "clear-conv: AGENTS.md has no '家老/clear' (converted to 家老/new)" {
    [ -f "$PROJECT_ROOT/AGENTS.md" ]
    ! grep -q "家老/clear" "$PROJECT_ROOT/AGENTS.md"
}

@test "clear-conv: Codex generated files have no forbidden raw /clear reset references" {
    local file hits out
    local files=(
        "$PROJECT_ROOT/AGENTS.md"
        "$OUTPUT_DIR/codex-shogun.md"
        "$OUTPUT_DIR/codex-karo.md"
        "$OUTPUT_DIR/codex-gunshi.md"
        "$OUTPUT_DIR/codex-ashigaru.md"
    )

    hits=""
    for file in "${files[@]}"; do
        [ -f "$file" ]
        out="$(find_forbidden_codex_clear_refs "$file")"
        if [ -n "$out" ]; then
            hits+="${file}:${out}"$'\n'
        fi
    done

    if [ -n "$hits" ]; then
        printf '%s\n' "$hits" >&2
        false
    fi
}

@test "clear-conv: legal clear words are not treated as forbidden raw /clear reset references" {
    local fixture
    fixture="$BATS_TEST_TMPDIR/legal_clear_terms.md"
    cat > "$fixture" <<'EOF'
`/shogun-clear-prep` remains a valid skill name.
`clear_command` remains a valid inbox message type.
- `type: clear_command` → sends the configured session reset command (`/clear` for Claude, `/new` for Codex)
| `/new` | Start fresh conversation within current session | `/clear` (closest) |
| `/clear` context reset | Yes | `/new` (TUI only) |
**Key difference from Claude Code**: Codex uses `/new` instead of /clear for context reset.
**Key difference from Claude Code**: Codex uses `/new` instead of `/clear` for context reset.
EOF

    run find_forbidden_codex_clear_refs "$fixture"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
