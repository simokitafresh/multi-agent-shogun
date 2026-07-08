#!/usr/bin/env bats
# test_ninja_monitor_reflux_promotion.bats
# _reflux_promotion_inventory の PD(pending_decisions.yaml)登録済みtarget除外を検証する。
#
# 背景(cmd_reflux_promotion_202607080727_tobisaru): _reflux_promotion_inventory()は
# gate_lesson_enforcement_level.shのbelow4候補一覧から常に先頭(first_item)を選ぶが、
# 家老がdecision_candidateをpending_decisions.yamlへPD登録しても一覧から除外されず、
# 同一対象(LS-A16)がkotaro→saizo→tobisaruと3回連続dispatchされた実害が発生した
# (logs/gunshi_review_log.yaml L2222参照)。本テストは、PD registered=pendingの
# 教訓IDをbelow4先頭選定から除外し、未登録の次点候補を選ぶことを検証する。

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/reflux_promotion.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" "$TEST_TMPDIR/queue" "$TEST_TMPDIR/projects/infra"
    cp "$PROJECT_ROOT/scripts/gates/gate_lesson_enforcement_level.sh" "$TEST_TMPDIR/scripts/gates/"

    cat > "$TEST_TMPDIR/projects/infra/lessons_shogun.yaml" <<'EOF'
lessons:
- id: LS-A16
  title: 本番パリティ必須
  enforcement: 'Guard5実装済み(PostToolUse即時警告)'
  enforcement_level: 3
- id: LS-A99
  title: 別の昇格候補
  enforcement: 'ドキュメント記載のみ'
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_karo.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_gunshi.yaml" <<'EOF'
lessons: []
EOF
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "_reflux_promotion_inventory: pending_decisions.yaml不在なら従来通り先頭候補を選ぶ" {
    run bash -lc '
set -euo pipefail
export NINJA_MONITOR_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="'"$TEST_TMPDIR"'"
_reflux_promotion_inventory
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"LS-A16"* ]]
}

@test "_reflux_promotion_inventory: 先頭候補がPD pending登録済みなら次点候補を選ぶ" {
    cat > "$TEST_TMPDIR/queue/pending_decisions.yaml" <<'EOF'
decisions:
- id: PD-059
  type: action_required
  status: pending
  summary: 'LS-A16 fullrecalculate後parity未確認をLevel4 BLOCK化するか裁定: pending flag状態管理/DM-signal PJ検知/false positive設計が必要'
  source_cmd: cmd_reflux_promotion_202607080715_saizo
EOF
    run bash -lc '
set -euo pipefail
export NINJA_MONITOR_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="'"$TEST_TMPDIR"'"
_reflux_promotion_inventory
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"LS-A99"* ]]
    [[ "$output" != *"LS-A16"* ]]
}

@test "_reflux_promotion_inventory: 全候補がPD pending登録済みなら候補なし(-)を返す" {
    cat > "$TEST_TMPDIR/queue/pending_decisions.yaml" <<'EOF'
decisions:
- id: PD-059
  type: action_required
  status: pending
  summary: 'LS-A16 Level4化は設計判断が必要'
- id: PD-060
  type: action_required
  status: pending
  summary: 'LS-A99も別途裁定待ち'
EOF
    run bash -lc '
set -euo pipefail
export NINJA_MONITOR_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="'"$TEST_TMPDIR"'"
_reflux_promotion_inventory
'
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\t'"-"$'\t'* ]]
}

@test "_reflux_promotion_inventory: PDがresolved状態なら除外せず先頭候補のまま" {
    cat > "$TEST_TMPDIR/queue/pending_decisions.yaml" <<'EOF'
decisions:
- id: PD-059
  type: action_required
  status: resolved
  summary: 'LS-A16 Level4化は設計判断が必要だったが解決済み'
  resolved_at: '2026-07-08T08:00:00'
EOF
    run bash -lc '
set -euo pipefail
export NINJA_MONITOR_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="'"$TEST_TMPDIR"'"
_reflux_promotion_inventory
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"LS-A16"* ]]
}

@test "_reflux_promotion_inventory: below4件数(count)はPD除外の影響を受けない" {
    cat > "$TEST_TMPDIR/queue/pending_decisions.yaml" <<'EOF'
decisions:
- id: PD-059
  type: action_required
  status: pending
  summary: 'LS-A16 Level4化は設計判断が必要'
EOF
    run bash -lc '
set -euo pipefail
export NINJA_MONITOR_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="'"$TEST_TMPDIR"'"
_reflux_promotion_inventory
'
    [ "$status" -eq 0 ]
    [[ "$output" == "2"$'\t'* ]]
}

@test "_reflux_first_pending_insight_id: high fix_known を通常pendingより優先する" {
    cat > "$TEST_TMPDIR/queue/insights.yaml" <<'EOF'
insights:
- id: INS-low-first
  ts: "2026-07-08T10:00:00+09:00"
  insight: "先頭だがlow"
  priority: "low"
  fix_known: false
  status: pending
- id: INS-medium-fix
  ts: "2026-07-08T10:01:00+09:00"
  insight: "fix_knownだがmedium"
  priority: "medium"
  fix_known: true
  status: pending
- id: INS-high-fix
  ts: "2026-07-08T10:02:00+09:00"
  insight: "高優先fix_known"
  priority: "high"
  fix_known: true
  status: pending
EOF
    run bash -lc '
set -euo pipefail
export NINJA_MONITOR_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="'"$TEST_TMPDIR"'"
_reflux_first_pending_insight_id "$SCRIPT_DIR/queue/insights.yaml"
'
    [ "$status" -eq 0 ]
    [ "$output" = "INS-high-fix" ]
}

@test "_reflux_first_pending_insight_id: 同ランクなら既存順を維持する" {
    cat > "$TEST_TMPDIR/queue/insights.yaml" <<'EOF'
insights:
- id: INS-high-fix-first
  priority: "high"
  fix_known: true
  status: pending
- id: INS-high-fix-second
  priority: "high"
  fix_known: true
  status: pending
EOF
    run bash -lc '
set -euo pipefail
export NINJA_MONITOR_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="'"$TEST_TMPDIR"'"
_reflux_first_pending_insight_id "$SCRIPT_DIR/queue/insights.yaml"
'
    [ "$status" -eq 0 ]
    [ "$output" = "INS-high-fix-first" ]
}

@test "_reflux_first_pending_insight_id: nested verification.status は直下statusを上書きしない" {
    cat > "$TEST_TMPDIR/queue/insights.yaml" <<'EOF'
insights:
- id: INS-high-fix-with-verification
  priority: "high"
  fix_known: true
  status: pending
  verification:
    status: "passed"
    exit_code: 0
- id: INS-medium-normal
  priority: "medium"
  fix_known: false
  status: pending
EOF
    run bash -lc '
set -euo pipefail
export NINJA_MONITOR_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="'"$TEST_TMPDIR"'"
_reflux_first_pending_insight_id "$SCRIPT_DIR/queue/insights.yaml"
'
    [ "$status" -eq 0 ]
    [ "$output" = "INS-high-fix-with-verification" ]
}
