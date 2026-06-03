#!/usr/bin/env bats
# test_cmd_save_warn_logging.bats — cmd_2208: WARN_COUNT加算経路とWARN notes記録の回帰

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SAVE_SCRIPT" ] || return 1

    eval "$(sed -n '/^extract_acceptance_criteria_block()/,/^}/p' "$SAVE_SCRIPT")"
    eval "$(sed -n '4066,4209p' "$SAVE_SCRIPT")"
    eval "$(sed -n '/^build_warn_note()/,/^}/p' "$SAVE_SCRIPT")"
    eval "$(sed -n '/^warn_note_key()/,/^}/p' "$SAVE_SCRIPT")"
    eval "$(sed -n '/^warn_note_message()/,/^}/p' "$SAVE_SCRIPT")"
    eval "$(sed -n '/^record_warn_reason()/,/^}/p' "$SAVE_SCRIPT")"
    eval "$(sed -n '4173,4209p' "$SAVE_SCRIPT")"

    cmd_block_get_field() {
        local field="${1:-}"
        local fallback="${2:-}"
        awk -v key="$field" -v fallback="$fallback" '
            $0 ~ "^[[:space:]]*" key ":" {
                sub("^[[:space:]]*" key ":[[:space:]]*", "")
                gsub(/^"|"$/, "")
                print
                found=1
                exit
            }
            END { if (!found) print fallback }
        ' <<< "${CMD_BLOCK_NC:-}"
    }

    count_same_warn_pattern() {
        local warn_pattern="${1:-}"
        [[ -n "$warn_pattern" && -f "$QUALITY_LOG_FILE" ]] || { echo 0; return 0; }
        python3 - "$QUALITY_LOG_FILE" "$warn_pattern" <<'PY'
import sys
import yaml

path, warn_pattern = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}
count = 0
for entry in data.get("entries", []):
    if not isinstance(entry, dict):
        continue
    note = str(entry.get("notes", "") or "")
    key = note.split("|", 1)[0].strip()
    if (
        entry.get("source") == "cmd_save_warn"
        and entry.get("gate_result") == "WARN"
        and not entry.get("resolved_by")
        and "[resolved:" not in note
        and (key == warn_pattern or warn_pattern in note)
    ):
        count += 1
print(count)
PY
    }

    export -f extract_acceptance_criteria_block emit_ac_param_candidate_hints
    export -f build_warn_note warn_note_key warn_note_message record_warn_reason
    run_ac_param_check_body() {
        check_ac_param_sufficiency
        if [ "${WARN_COUNT:-0}" -gt 0 ]; then
            {
                printf 'entries:\n'
                local warn_note
                for warn_note in "${WARN_REASONS[@]}"; do
                    printf '  - cmd_id: "cmd_warn"\n'
                    printf '    gate_result: "WARN"\n'
                    printf '    source: "cmd_save_warn"\n'
                    printf '    notes: "%s"\n' "$warn_note"
                done
            } >> "$TEST_QUALITY_LOG"
        fi
        return 0
    }

    export -f check_ac_param_sufficiency cmd_block_get_field count_same_warn_pattern
    export -f run_ac_param_check_body
}

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR
    export TEST_QUEUE="$TEST_TMPDIR/shogun_to_karo.yaml"
    export TEST_ARCHIVE_DIR="$TEST_TMPDIR/archive"
    export TEST_QUALITY_LOG="$TEST_TMPDIR/cmd_design_quality.yaml"
    export TEST_LAST_CMD="$TEST_TMPDIR/cmd_save_last_cmd.txt"
    export TEST_LESSONS="$TEST_TMPDIR/lessons_shogun.yaml"
    mkdir -p "$TEST_ARCHIVE_DIR"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

write_warn_cmd_queue() {
    cat > "$TEST_QUEUE" <<'YAML'
commands:
  cmd_warn:
    id: cmd_warn
    title: "infra — AC数量指定WARN記録テスト"
    purpose: "AC数量指定WARNを発火し、cmd_design_quality.yamlへnotesが残ることを検証する"
    project: infra
    task_type: impl
    command: |
      既存WARN記録経路を検証する
    acceptance_criteria:
      - 'AC1: 以下の3項目を満たすこと'
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "WARN理由が記録される"
      q3_next_quality: "次回のWARN分析がしやすくなる"
      q4_depth: "shallow"
      q5_verified_source: "code_reading + isolated_test"
      q6_not_hiding: "no — WARN logging回帰確認であり問題の隠蔽ではない"
      q7_definition_verified: "yes — WARN notesは type 名で記録される"
      q8_why_what: "WHY: WARNの原因がnotesへ残らないと分析不能 / WHAT: cmd_save_warnのnotes記録を検証 / WHEN: 即時 / WHERE: scripts/cmd_save.sh / WHO: 家老 / HOW: テスト実行で検証。複利: 正の複利"
      q10_knowledge_boundary: "tests/unit/test_cmd_save_warn_logging.bats の検証範囲のみ使用"
      q11_not_already_done: "未達成。WARN notes記録の回帰テストを追加していない"
      q_ambiguity: "none"
    origin: "[[cmd_test]] -> [[WARN記録検証]] -> [[check_ac_param_sufficiency]]"
    assumptions:
      - claim: "AC数量指定WARNは cmd_save.sh の check_ac_param_sufficiency で検出される"
        source: "scripts/cmd_save.sh code_reading"
        trust: "verified"
YAML
}

write_warn_cmd_queue_with_candidate_context() {
    mkdir -p "$TEST_TMPDIR/context"
    cat > "$TEST_TMPDIR/context/ac-candidates.md" <<'MD'
# AC候補値
- WARN候補抽出の3項目: context候補 / projects候補 / semantic候補
MD

    cat > "$TEST_QUEUE" <<YAML
commands:
  cmd_warn:
    id: cmd_warn
    title: "infra — AC数量指定候補値表示テスト"
    purpose: "AC数量指定WARN時に関連contextから候補値を表示する"
    project: infra
    task_type: impl
    command: |
      関連資料: $TEST_TMPDIR/context/ac-candidates.md
    acceptance_criteria:
      - 'AC1: WARN候補抽出の3項目を満たすこと'
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "WARN時に候補値を自動表示する"
      q3_next_quality: "忍者がN項目を独自補完しない"
      q4_depth: "shallow"
      q5_verified_source: "isolated_test"
      q6_not_hiding: "no — 候補表示の追加であり問題を隠さない"
      q7_definition_verified: "yes — context候補表示をstderrで確認する"
      q8_why_what: "WHY: N項目未列挙は独自補完を誘発 / WHAT: 関連contextから候補値を提示 / WHEN: 即時 / WHERE: scripts/cmd_save.sh / WHO: 家老 / HOW: context自動抽出で提示。複利: 正の複利"
      q10_knowledge_boundary: "$TEST_TMPDIR/context/ac-candidates.md のみ"
      q11_not_already_done: "未達成。候補値表示テストがない"
      q_ambiguity: "none"
    origin: "[[cmd_test]] -> [[候補値表示検証]] -> [[check_ac_param_sufficiency]]"
    assumptions:
      - claim: "候補値は関連contextから抽出できる"
        source: "$TEST_TMPDIR/context/ac-candidates.md"
        trust: "verified"
YAML
}

run_ac_param_check() {
    CMD_BLOCK_NC="$(sed -n '/^  cmd_warn:/,$p' "$TEST_QUEUE")"
    CMD_BLOCK="$CMD_BLOCK_NC"
    CMD_ID="cmd_warn"
    PROJECT_DIR="$PROJECT_ROOT"
    QUALITY_LOG_FILE="$TEST_QUALITY_LOG"
    QUEUE_FILE="$TEST_QUEUE"
    ARCHIVE_CMD_DIR="$TEST_ARCHIVE_DIR"
    CMD_SAVE_SHOGUN_LESSONS_FILE="$TEST_LESSONS"
    WARN_COUNT=0
    WARN_REASONS=()

    run run_ac_param_check_body
}

@test "AC1: record_warn_reason以外のbare WARN_COUNT++は存在しない" {
    run awk '
        /^record_warn_reason\(\)/ { in_fn=1 }
        in_fn && /^}/ { in_fn=0; next }
        !in_fn && /WARN_COUNT=\$\(\(WARN_COUNT \+ 1\)\)/ { print NR ":" $0 }
    ' "$SAVE_SCRIPT"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "AC2: WARN発生時にcmd_save_warn entryへnotesが記録される" {
    write_warn_cmd_queue

    run_ac_param_check
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: ACに数量指定があるが具体値が列挙されていません"* ]]

    run grep -n 'source: "cmd_save_warn"' "$TEST_QUALITY_LOG"
    [ "$status" -eq 0 ]

    run grep -n 'ac_param_sufficiency' "$TEST_QUALITY_LOG"
    [ "$status" -eq 0 ]

    run grep -n 'check=check_ac_param_sufficiency' "$TEST_QUALITY_LOG"
    [ "$status" -eq 0 ]

    run python3 -c "import yaml; yaml.safe_load(open('$TEST_QUALITY_LOG', encoding='utf-8'))"
    [ "$status" -eq 0 ]
}

@test "AC3: 同一WARN type 2回目以降はSession Stateにgrep -n結果が表示される" {
    write_warn_cmd_queue

    cat > "$TEST_QUALITY_LOG" <<'YAML'
entries:
  - cmd_id: "cmd_hist"
    gate_result: "WARN"
    source: "cmd_save_warn"
    notes: "ac_param_sufficiency|check=check_ac_param_sufficiency|ACに数量指定があるが具体値が列挙されていません"
YAML

    run_ac_param_check
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"このWARN(ac_param_sufficiency)は過去1回出現"* ]]
    [[ "$output" == *"★ Session State: 検出ロジック該当行"* ]]
    [[ "$output" == *"check=check_ac_param_sufficiency"* ]]
}

@test "AC3b: resolved_by付きWARN履歴は同一WARN累計から除外される" {
    write_warn_cmd_queue

    cat > "$TEST_QUALITY_LOG" <<'YAML'
entries:
  - cmd_id: "cmd_hist"
    gate_result: "WARN"
    source: "cmd_save_warn"
    resolved_by: "cmd_2703"
    notes: "ac_param_sufficiency|check=check_ac_param_sufficiency|ACに数量指定があるが具体値が列挙されていません"
YAML

    run_ac_param_check
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"このWARN(ac_param_sufficiency)は過去1回出現"* ]]
    [[ "$output" != *"BLOCK: WARN累計昇格"* ]]
}

@test "AC4: AC数量指定WARN時に関連contextから候補値が表示される" {
    write_warn_cmd_queue_with_candidate_context

    run_ac_param_check
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: ACに数量指定があるが具体値が列挙されていません"* ]]
    [[ "$output" == *"候補値ヒント（関連context/projectsから自動抽出）"* ]]
    [[ "$output" == *"ac-candidates.md"* ]]
    [[ "$output" == *"context候補 / projects候補 / semantic候補"* ]]
}
