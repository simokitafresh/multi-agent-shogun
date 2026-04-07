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
    export BUILD_STATUS_FILE
    export BUILD_HASH_FILE
    BUILD_STATUS_FILE="$(mktemp)"
    BUILD_HASH_FILE="$(mktemp)"

    # パーツディレクトリの存在確認（前提条件）
    [ -d "$PROJECT_ROOT/instructions/roles" ] || return 1
    [ -d "$PROJECT_ROOT/instructions/common" ] || return 1
    [ -d "$PROJECT_ROOT/instructions/cli_specific" ] || return 1

    # ビルド実行（全テストの前に1回のみ）
    bash "$BUILD_SCRIPT" > /dev/null 2>&1
    printf '%s\n' "$?" > "$BUILD_STATUS_FILE"
    find "$OUTPUT_DIR" -name "*.md" -type f -exec md5sum {} \; | sort > "$BUILD_HASH_FILE"
}

teardown_file() {
    rm -f "${BUILD_STATUS_FILE:-}"
    rm -f "${BUILD_HASH_FILE:-}"
}

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    BUILD_SCRIPT="$PROJECT_ROOT/scripts/build_instructions.sh"
    OUTPUT_DIR="$PROJECT_ROOT/instructions/generated"
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
    local temp_repo
    temp_repo="$(mktemp -d)"

    mkdir -p \
        "$temp_repo/scripts/lib" \
        "$temp_repo/config" \
        "$temp_repo/instructions/roles" \
        "$temp_repo/instructions/common" \
        "$temp_repo/instructions/cli_specific"

    cp "$PROJECT_ROOT/scripts/build_instructions.sh" "$temp_repo/scripts/build_instructions.sh"
    cp "$PROJECT_ROOT/scripts/lib/cli_lookup.sh" "$temp_repo/scripts/lib/cli_lookup.sh"

    cat > "$temp_repo/CLAUDE.md" <<'EOF'
---
role: root
---
Auto-load file for Claude Code.
EOF

    cat > "$temp_repo/config/settings.yaml" <<'EOF'
cli:
  default: claude
EOF

    cat > "$temp_repo/config/cli_profiles.yaml" <<'EOF'
profiles:
  claude:
    display_name: "Claude Display"
  copilot:
    display_name: "Copilot Display"
  codex:
    display_name: "Codex Display"
EOF

    for role in shogun karo gunshi ashigaru; do
        cat > "$temp_repo/instructions/${role}.md" <<EOF
---
role: ${role}
---
EOF
        printf '%s role\n' "$role" > "$temp_repo/instructions/roles/${role}_role.md"
    done

    printf 'protocol\n' > "$temp_repo/instructions/common/protocol.md"
    printf 'task flow\n' > "$temp_repo/instructions/common/task_flow.md"
    printf 'forbidden\n' > "$temp_repo/instructions/common/forbidden_actions.md"
    printf 'claude tools\n' > "$temp_repo/instructions/cli_specific/claude_tools.md"
    printf 'codex tools\n' > "$temp_repo/instructions/cli_specific/codex_tools.md"
    printf 'copilot tools\n' > "$temp_repo/instructions/cli_specific/copilot_tools.md"
    printf 'kimi tools\n' > "$temp_repo/instructions/cli_specific/kimi_tools.md"

    run bash "$temp_repo/scripts/build_instructions.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Generating: AGENTS.md (codex auto-load)"* ]]
    grep -q "Codex Display" "$temp_repo/AGENTS.md"
    ! grep -q "Copilot Display" "$temp_repo/AGENTS.md"

    rm -rf "$temp_repo"
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
    local second_file
    second_file="$(mktemp)"

    bash "$BUILD_SCRIPT" > /dev/null 2>&1
    find "$OUTPUT_DIR" -name "*.md" -type f -exec md5sum {} \; | sort > "$second_file"

    if ! cmp -s "$BUILD_HASH_FILE" "$second_file"; then
        diff -u "$BUILD_HASH_FILE" "$second_file" >&2 || true
        false
    fi

    rm -f "$second_file"
}
