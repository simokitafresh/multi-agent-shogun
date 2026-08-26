#!/usr/bin/env bats
# test_necessity: 殿裁定2026-07-23(提案A)で撤去された教訓件数capが、cmd_save と cmd_publish の
# どちらの実行経路にも復活していないこと(片側だけ復活する非対称が過去の実害である)。
#
# 経緯(cmd_karo_cifix_cmd_publish_preflight_invariant_20260726):
#   本ファイルは元々『cmd_save と cmd_publish が同一の共有preflight(lesson_cap)を呼ぶ』を
#   守っていたが、commit 4f4aae961(2026-07-23)が殿裁定 提案A により cmd_shared_preflight の
#   呼出しを両方から撤去した。∴capそのものは契約として消滅しており、旧assertionは
#   撤去済み契約を守り続けてCIをFAILさせていた(実装は正しくテストが古い側)。
#   撤去は startup gate / cmd_save / cmd_publish の3箇所に適用される裁定であり、
#   将軍が当初 startup gate のみを直して cmd_save 側を残したため cmd_4125 の保存が
#   BLOCKされる空転が実際に再発した。∴守るべき不変量は『対称に撤去されたままであること』。
#   参照: LS106(閾値は当時の実数からの逆算=根拠なき数値ゆえ従うのでなく撤去せよ)。

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SAVE="$PROJECT_ROOT/scripts/cmd_save.sh"
    PUBLISH="$PROJECT_ROOT/scripts/cmd_publish.sh"
    STARTUP_GATE="$PROJECT_ROOT/scripts/gates/gate_shogun_startup.sh"
    TEST_TMPDIR="$(mktemp -d)"
    # 旧cap境界(33件でBLOCK/上限35)を大きく超える件数。capが生きていれば必ず発火する。
    write_lessons 60
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

write_lessons() {
    local count="$1" i
    : > "$TEST_TMPDIR/lessons.yaml"
    for ((i = 1; i <= count; i++)); do
        printf -- '- id: LS%03d\n  summary: active\n' "$i" >> "$TEST_TMPDIR/lessons.yaml"
    done
}

# capが発火したときにのみ現れる文言。実装の内部構造ではなく利用者に見える出力で判定する。
assert_no_lesson_cap_block() {
    [[ "$output" != *"lessons_shogun.yaml が"* ]]
    [[ "$output" != *"active件数を"* ]]
    [[ "$output" != *"件以上でBLOCK"* ]]
}

@test "AC1: cmd_save --preflight の実行経路で教訓件数capが発火しない" {
    # 存在しないcmd_idを渡すことで、cmd_save側はブロック未検出WARNで止まる。
    # capが生きていれば、その前段のlesson-cap BLOCKが出力に現れる。
    run env \
        CMD_SAVE_SHOGUN_LESSONS_FILE="$TEST_TMPDIR/lessons.yaml" \
        CMD_SAVE_LAST_CMD_FILE="$TEST_TMPDIR/last.txt" \
        CMD_SAVE_BLOCK_DIR="$TEST_TMPDIR" \
        CMD_SAVE_PREFLIGHT_AUTOLEARN_FILE="$TEST_TMPDIR/autolearn.txt" \
        bash "$SAVE" --preflight cmd_absent_probe_for_cap_invariant
    # 陽性marker: cmd_save が実際に走ったことを示す。これが無いと、対象が不在で何も
    # 実行されなかった場合に『cap文言が無い』が空PASSする(異常系variation実測で判明)。
    # 文言は環境で変わる(主worktree=「のブロックが…見つかりません」/ linked worktree=
    # queue不在で「…が存在しません」)ため、shogun_to_karo.yaml への言及で判定する。
    [ -r "$SAVE" ]
    [[ "$output" == *"shogun_to_karo.yaml"* ]]
    assert_no_lesson_cap_block
}

@test "AC2: cmd_publish の実行経路で教訓件数capが発火しない" {
    # LAST_CMD_FILE を不在にすることで run_publish_preflight は自動ack経路へ入らず即returnする
    # (書込み副作用なし)。cmd_id不在のため昇格・委任へ進む前に exit する。
    run env \
        CMD_PUBLISH_SHOGUN_LESSONS_FILE="$TEST_TMPDIR/lessons.yaml" \
        CMD_PUBLISH_LAST_CMD_FILE="$TEST_TMPDIR/absent_last.txt" \
        bash "$PUBLISH" cmd_absent_probe_for_cap_invariant "probe"
    [[ "$output" == *"cmd_publish pre-flight"* ]]
    assert_no_lesson_cap_block
}

@test "AC3: 撤去は3箇所すべてで対称である(片側復活の検出)" {
    # 対象が不在なら grep -c は 0 を返し『呼出し0件』が空PASSする。先に実在を要求する
    # (異常系variation実測で判明した本テスト自身の穴)。
    [ -r "$SAVE" ]
    [ -r "$PUBLISH" ]
    [ -r "$STARTUP_GATE" ]
    # 呼出し0件を3箇所で確認する。1箇所だけ復活する非対称が過去の実害であった。
    [ "$(grep -c 'cmd_shared_preflight ' "$SAVE")" -eq 0 ]
    [ "$(grep -c 'cmd_shared_preflight ' "$PUBLISH")" -eq 0 ]
    run grep -nE '(lessons_shogun\.yaml が|active件数を)' "$STARTUP_GATE"
    [ "$status" -ne 0 ]
    # 撤去の根拠(殿裁定)がコード上に残っていること。理由なき再追加を防ぐ。
    run grep -F '殿裁定2026-07-23 提案A' "$SAVE"
    [ "$status" -eq 0 ]
    run grep -F '殿裁定2026-07-23 提案A' "$PUBLISH"
    [ "$status" -eq 0 ]
}

# test_necessity: cmd_publishの外側経路を既存defense_overhead台帳へ恒久記録し、
# 成功時の段別wall_msとpublish_totalが欠落しない不変量を守る。
@test "AC1 contract: cmd_publish emits durable phase timing for the full publish path" {
    local queue_file="$TEST_TMPDIR/shogun_to_karo.yaml"
    local ledger="$TEST_TMPDIR/defense_overhead.jsonl"
    local index="$TEST_TMPDIR/defense_overhead.sqlite3"
    local save_stub="$TEST_TMPDIR/save_stub.sh"
    local delegate_stub="$TEST_TMPDIR/delegate_stub.sh"
    cat > "$queue_file" <<'YAML'
cmd_publish_phase_probe:
  status: draft
  title: phase probe
YAML
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$save_stub"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$delegate_stub"

    run env \
        CMD_PUBLISH_QUEUE_FILE="$queue_file" \
        CMD_PUBLISH_LAST_CMD_FILE="$TEST_TMPDIR/absent_last.txt" \
        CMD_PUBLISH_CMD_SAVE_SCRIPT="$save_stub" \
        CMD_PUBLISH_CMD_DELEGATE_SCRIPT="$delegate_stub" \
        DEFENSE_OVERHEAD_LEDGER="$ledger" \
        DEFENSE_OVERHEAD_INDEX="$index" \
        bash "$PUBLISH" cmd_publish_phase_probe "probe"
    [ "$status" -eq 0 ]
    [ -s "$ledger" ]

    run python3 - "$ledger" <<'PY'
import json
import sys

rows = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
ids = {row["check_id"] for row in rows if row.get("source") == "cmd_publish"}
required = {"preflight", "save_gate", "promotion", "delegate", "publish_total"}
assert required <= ids, (required, ids)
assert all(row["wall_ms"] >= 0 for row in rows if row.get("source") == "cmd_publish")
assert all(row["verdict"] == "PASS" for row in rows if row.get("source") == "cmd_publish")
PY
    [ "$status" -eq 0 ]
}
