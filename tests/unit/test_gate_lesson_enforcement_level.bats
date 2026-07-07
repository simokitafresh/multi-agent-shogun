#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_lesson_enforcement_level.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gate_lesson_enforcement_level.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/projects/infra" "$TEST_TMPDIR/projects/dm-signal"
    export LESSON_ENFORCEMENT_ROOT="$TEST_TMPDIR"

    # 忍者/PJ教訓: enforcement fieldを持たない(実運用と同じ構造)
    cat > "$TEST_TMPDIR/projects/infra/lessons.yaml" <<'EOF'
lessons:
- id: L001
  title: pj lesson without enforcement
  summary: pj lesson without enforcement
EOF
    cat > "$TEST_TMPDIR/projects/dm-signal/lessons.yaml" <<'EOF'
lessons:
- id: L900
  title: dm-signal pj lesson
  summary: dm-signal pj lesson
EOF
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "gate_lesson_enforcement_level classifies explicit Level marker and excludes it from below-4 candidates" {
    cat > "$TEST_TMPDIR/projects/infra/lessons_gunshi.yaml" <<'EOF'
lessons:
- id: LG-T01
  title: explicit level5 marker
  enforcement: 'post-shogun-inbox-check.sh自走チェック(L5: insightキュー+掲示板action_required強制表示)'
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_shogun.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_karo.yaml" <<'EOF'
lessons: []
EOF

    run bash "$SRC_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"lessons_gunshi.yaml: enforcement記載1件"* ]]
    [[ "$output" == *"L5:1"* ]]
    [[ "$output" != *"LG-T01"* ]]
    [[ "$output" == *"##ENFORCEMENT_LEVEL_BELOW4_COUNT##"$'\n'"0"* ]]
}

@test "gate_lesson_enforcement_level does not mistake a multi-digit lesson-ID reference for an explicit Level marker" {
    cat > "$TEST_TMPDIR/projects/infra/lessons_shogun.yaml" <<'EOF'
lessons:
- id: LS-T02
  title: lesson-id lookalike must not be misread as explicit Level marker
  enforcement: 'L2684参照+L1553参照のみ。自動化の記述なし'
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_karo.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_gunshi.yaml" <<'EOF'
lessons: []
EOF

    run bash "$SRC_SCRIPT"
    [ "$status" -eq 0 ]
    # L2684/L1553のような多桁ID参照が誤ってexplicit L2/L1マーカーとして拾われると
    # (バグがあれば)分類先レベルが変わってしまう。正しくは明示マーカーなし+
    # keywordにもヒットしないためdefaultのL1に分類されるべき。
    [[ "$output" == *"[lessons_shogun.yaml] LS-T02 (L1:事後検出)"* ]]
}

@test "gate_lesson_enforcement_level excludes superseded lessons from active promotion inventory" {
    cat > "$TEST_TMPDIR/projects/infra/lessons_shogun.yaml" <<'EOF'
lessons:
- id: LS-OLD
  title: old below-4 lesson
  enforcement: '意志依存(gate/hookなし)'
  superseded_by: 'LS-NEW'
- id: LS-NEW
  title: new guarded lesson
  enforcement: 'type=flow_block; file=scripts/note_draft.sh; pattern=LS029 Level4 guard'
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_karo.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_gunshi.yaml" <<'EOF'
lessons: []
EOF

    run bash "$SRC_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"lessons_shogun.yaml: enforcement記載1件"* ]]
    [[ "$output" == *"L4:1"* ]]
    [[ "$output" != *"LS-OLD"* ]]
    [[ "$output" != *"old below-4 lesson"* ]]
    [[ "$output" == *"##ENFORCEMENT_LEVEL_BELOW4_COUNT##"$'\n'"0"* ]]
}

@test "gate_lesson_enforcement_level classifies keyword-based BLOCK/guard text as Level4 and lists true below-4 candidates" {
    cat > "$TEST_TMPDIR/projects/infra/lessons_karo.yaml" <<'EOF'
lessons:
- id: LK-T01
  title: block keyword
  enforcement: 'cmd_delegate.sh guard(status未満はinbox_write BLOCK)'
- id: LK-T02
  title: no automation signal at all
  enforcement: 'レビュー時にdraft/報告の変更パターンをgrep横展開確認'
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_shogun.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_gunshi.yaml" <<'EOF'
lessons: []
EOF

    run bash "$SRC_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"lessons_karo.yaml: enforcement記載2件"* ]]
    [[ "$output" == *"L4未満:1件(50.0%)"* ]]
    [[ "$output" == *"[lessons_karo.yaml] LK-T02 (L1:事後検出): no automation signal at all"* ]]
    [[ "$output" != *"LK-T01"* ]]
    [[ "$output" == *"##ENFORCEMENT_LEVEL_BELOW4_COUNT##"$'\n'"1"* ]]
}

@test "gate_lesson_enforcement_level classifies weak_points injection text as Level6" {
    cat > "$TEST_TMPDIR/projects/infra/lessons_gunshi.yaml" <<'EOF'
lessons:
- id: LG-T03
  title: level6 weak points injection
  enforcement: 'ninja_weak_points: 過去の弱点を次回配備時に自動注入'
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_shogun.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_karo.yaml" <<'EOF'
lessons: []
EOF

    run bash "$SRC_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"L6:1"* ]]
    [[ "$output" != *"LG-T03"* ]]
}

@test "gate_lesson_enforcement_level reports PJ lessons (no enforcement field) as out-of-scope counts, not candidates" {
    cat > "$TEST_TMPDIR/projects/infra/lessons_shogun.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_karo.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_gunshi.yaml" <<'EOF'
lessons: []
EOF

    run bash "$SRC_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"infra: 1件 (enforcement field無し)"* ]]
    [[ "$output" == *"dm-signal: 1件 (enforcement field無し)"* ]]
    [[ "$output" == *"PJ別enforcement記載合計: 0件"* ]]
    [[ "$output" == *"PJ別(忍者教訓)合計: 2件(field無しはLevel分布の集計対象外)"* ]]
    [[ "$output" != *"L001"* ]]
    [[ "$output" != *"L900"* ]]
}

@test "gate_lesson_enforcement_level includes PJ lessons with enforcement in distribution and keeps fieldless out-of-scope" {
    cat > "$TEST_TMPDIR/projects/infra/lessons_shogun.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_karo.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_gunshi.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons.yaml" <<'EOF'
lessons:
- id: L001
  title: pj level5 lesson
  enforcement: 'Level5: task YAMLへ事前コンテキスト提供'
- id: L002
  title: pj fieldless lesson
  summary: fieldless remains out of distribution
EOF

    run bash "$SRC_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"infra: 2件 / enforcement記載1件 / L1:0 L2:0 L3:0 L4:0 L5:1 L6:0 / L4未満:0件(0.0%) / field無し:1件"* ]]
    [[ "$output" == *"PJ別enforcement記載合計: 1件 / L1:0 L2:0 L3:0 L4:0 L5:1 L6:0 / field無し:2件"* ]]
    [[ "$output" == *"全enforcement記載合計: 1件 / L1:0 L2:0 L3:0 L4:0 L5:1 L6:0"* ]]
    [[ "$output" != *"L002"* ]]
}

@test "gate_lesson_enforcement_level prefers explicit enforcement_level field over text heuristics (role file)" {
    # 2026-07-08 cmd_reflux_promotion_202607080640_saizo: enforcement_levelフィールドが
    # あるのに、テキストにL/Levelマーカーやキーワードが無いとdefaultのL1へ誤判定されていた
    # 実例(LS-A14: enforcement_level=4だがenforcementテキストに明示マーカー無し)を再現する。
    cat > "$TEST_TMPDIR/projects/infra/lessons_shogun.yaml" <<'EOF'
lessons:
- id: LS-T04
  title: field says level4 but text has no explicit marker or keyword
  enforcement: 'clear_prep_check.sh Check 10で裁定反映漏れをALERTとして検出する'
  enforcement_level: 4
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_karo.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_gunshi.yaml" <<'EOF'
lessons: []
EOF

    run bash "$SRC_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"lessons_shogun.yaml: enforcement記載1件"* ]]
    [[ "$output" == *"L4:1"* ]]
    [[ "$output" != *"LS-T04"* ]]
    [[ "$output" == *"##ENFORCEMENT_LEVEL_BELOW4_COUNT##"$'\n'"0"* ]]
}

@test "gate_lesson_enforcement_level prefers explicit enforcement_level field over text heuristics (PJ file)" {
    cat > "$TEST_TMPDIR/projects/infra/lessons_shogun.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_karo.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_gunshi.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_TMPDIR/projects/dm-signal/lessons.yaml" <<'EOF'
lessons:
- id: L901
  title: pj lesson with field overriding keyword misread as L5
  enforcement: '自動表示されるが実運用ではLevel2相当のドキュメント参照に留まる'
  enforcement_level: 2
EOF

    run bash "$SRC_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dm-signal] L901 (L2:事前予防(doc)): pj lesson with field overriding keyword misread as L5"* ]]
    [[ "$output" == *"##ENFORCEMENT_LEVEL_BELOW4_COUNT##"$'\n'"1"* ]]
}

@test "gate_lesson_enforcement_level lists below-4 PJ lessons with enforcement as candidates" {
    cat > "$TEST_TMPDIR/projects/infra/lessons_shogun.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_karo.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_gunshi.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_TMPDIR/projects/dm-signal/lessons.yaml" <<'EOF'
lessons:
- id: L900
  title: pj doc only lesson
  enforcement: 'ドキュメント記載のみ'
EOF

    run bash "$SRC_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dm-signal: 1件 / enforcement記載1件 / L1:0 L2:1 L3:0 L4:0 L5:0 L6:0 / L4未満:1件(100.0%) / field無し:0件"* ]]
    [[ "$output" == *"[dm-signal] L900 (L2:事前予防(doc)): pj doc only lesson"* ]]
    [[ "$output" == *"##ENFORCEMENT_LEVEL_BELOW4_COUNT##"$'\n'"1"* ]]
}
