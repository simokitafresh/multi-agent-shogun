#!/usr/bin/env bats
# test_gate_vercel_phase.bats — gate_vercel_phase.sh unit tests
# cmd_vercel_false_positive: 外部リポ偽陽性修正の検証

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE="$PROJECT_ROOT/scripts/gates/gate_vercel_phase.sh"
    [ -f "$SRC_GATE" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gate_vercel.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" \
             "$TEST_TMPDIR/config" \
             "$TEST_TMPDIR/context" \
             "$TEST_TMPDIR/docs/research"

    cp "$SRC_GATE" "$TEST_TMPDIR/scripts/gates/gate_vercel_phase.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_vercel_phase.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# ─── helpers ─────────────────────────────────────────────

make_projects_yaml() {
    # $1: extra project lines (optional)
    cat > "$TEST_TMPDIR/config/projects.yaml" << EOF
projects:
  - id: infra
    path: "$TEST_TMPDIR"
$1
EOF
}

make_context_file() {
    # $1: filename, $2: content
    printf '%s\n' "$2" > "$TEST_TMPDIR/context/$1"
}

run_gate() {
    run bash "$TEST_TMPDIR/scripts/gates/gate_vercel_phase.sh" "$@"
}

# ─── tests ───────────────────────────────────────────────

@test "当リポに存在する参照: PASS" {
    make_projects_yaml ""
    echo "content" > "$TEST_TMPDIR/docs/research/existing.md"
    make_context_file "test.md" "link: \`docs/research/existing.md\`"

    run_gate "$TEST_TMPDIR/context/test.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[OK]"* ]]
    [[ "$output" == *"1 refs checked"* ]]
}

@test "当リポに存在しない参照 + 外部リポなし: SKIP（偽陽性防止）" {
    # 外部リポを持たないprojects.yaml
    make_projects_yaml ""
    make_context_file "test.md" "link: \`docs/research/external_only.md\`"

    run_gate "$TEST_TMPDIR/context/test.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[OK]"* ]]
    # スキップされて0 refs
    [[ "$output" == *"0 refs checked"* ]]
}

@test "外部リポが存在し参照先がそこにある: PASS" {
    FAKE_EXT="$TEST_TMPDIR/fake_external"
    mkdir -p "$FAKE_EXT/docs/research"
    echo "data" > "$FAKE_EXT/docs/research/external_file.md"

    make_projects_yaml "  - id: external-pj
    path: \"$FAKE_EXT\""
    make_context_file "test.md" "link: \`docs/research/external_file.md\`"

    run_gate "$TEST_TMPDIR/context/test.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[OK]"* ]]
    [[ "$output" == *"1 refs checked"* ]]
}

@test "外部リポが存在するが参照先がどこにもない: FAIL（本物のリンク切れ）" {
    FAKE_EXT="$TEST_TMPDIR/fake_external"
    mkdir -p "$FAKE_EXT/docs/research"
    # broken_file.md は作成しない

    make_projects_yaml "  - id: external-pj
    path: \"$FAKE_EXT\""
    make_context_file "test.md" "link: \`docs/research/broken_file.md\`"

    run_gate "$TEST_TMPDIR/context/test.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"[ALERT]"* ]]
    [[ "$output" == *"broken_file.md [NOT FOUND]"* ]]
}

@test "壊れ参照検出時: 類似する修正候補パスが表示される" {
    FAKE_EXT="$TEST_TMPDIR/fake_external"
    mkdir -p "$FAKE_EXT/docs/research"
    echo "data" > "$TEST_TMPDIR/docs/research/gate-vercel-phase-design.md"
    echo "data" > "$FAKE_EXT/docs/research/gate-vercel-phase-notes.md"

    make_projects_yaml "  - id: external-pj
    path: \"$FAKE_EXT\""
    make_context_file "test.md" "link: \`docs/research/gate-vercel-phase-missing.md\`"

    run_gate "$TEST_TMPDIR/context/test.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"candidates:"* ]]
    [[ "$output" == *"docs/research/gate-vercel-phase-design.md"* ]]
    [[ "$output" == *"fake_external/docs/research/gate-vercel-phase-notes.md"* ]]
}

@test "複数contextファイル引数: 両方チェックされる" {
    make_projects_yaml ""
    echo "data" > "$TEST_TMPDIR/docs/research/file1.md"
    echo "data" > "$TEST_TMPDIR/docs/research/file2.md"
    make_context_file "a.md" "ref: \`docs/research/file1.md\`"
    make_context_file "b.md" "ref: \`docs/research/file2.md\`"

    run_gate "$TEST_TMPDIR/context/a.md" "$TEST_TMPDIR/context/b.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 refs checked"* ]]
}

@test "引数なし: context/以下を全走査" {
    make_projects_yaml ""
    echo "data" > "$TEST_TMPDIR/docs/research/all.md"
    make_context_file "only.md" "ref: \`docs/research/all.md\`"

    run_gate
    [ "$status" -eq 0 ]
    [[ "$output" == *"[OK]"* ]]
}

@test "DM-signal偽陽性パターン: 外部リポなし環境でdm-signal参照をスキップ" {
    # 外部リポ(DM-signal等)が全て存在しない環境をシミュレート
    make_projects_yaml "  - id: dm-signal
    path: \"/tmp/nonexistent_dm_signal_xyz987\""

    # dm-signal*ではないcontextファイルにDM-signal-onlyの参照
    make_context_file "cmd-chronicle.md" \
        "ref: \`docs/research/alm-integration-design.md\`"

    run_gate "$TEST_TMPDIR/context/cmd-chronicle.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[OK]"* ]]
}
