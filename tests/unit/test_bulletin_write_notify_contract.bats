#!/usr/bin/env bats

# test_necessity: bulletin通知が宛先pane状態に依らず1回配送される不変量

setup() {
    TEST_ROOT="$(mktemp -d)"
    mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/queue" "$TEST_ROOT/logs"
    cp "$BATS_TEST_DIRNAME/../../scripts/bulletin_write.sh" "$TEST_ROOT/scripts/bulletin_write.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/escalation_evidence.sh" "$TEST_ROOT/scripts/escalation_evidence.sh"
    mkdir -p "$TEST_ROOT/scripts/lib"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/escalation_evidence.sh" "$TEST_ROOT/scripts/lib/escalation_evidence.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/publisher_single_flag.sh" "$TEST_ROOT/scripts/lib/publisher_single_flag.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/lock_path.sh" "$TEST_ROOT/scripts/lib/lock_path.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/bulletin_archive.sh" "$TEST_ROOT/scripts/bulletin_archive.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/ledger_writer.sh" "$TEST_ROOT/scripts/ledger_writer.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/yaml_auto_archive.sh" "$TEST_ROOT/scripts/yaml_auto_archive.sh"
    mkdir -p "$TEST_ROOT/config" "$TEST_ROOT/queue/archive" "$TEST_ROOT/queue/flags"
    printf 'queue/bulletin_board.yaml\t2\tentries\t^\\s*-\\s+id:\tqueue/archive/bulletin_board_archive.yaml\n' \
        > "$TEST_ROOT/config/yaml_auto_archive.tsv"
    cat > "$TEST_ROOT/scripts/inbox_write_fixture.sh" <<'SH'
#!/bin/bash
printf '%s\n' "$1|$3|$4|$5" >> "$BULLETIN_NOTIFY_CAPTURE"
SH
    chmod +x "$TEST_ROOT/scripts/inbox_write_fixture.sh"
    export BULLETIN_NOTIFY_CAPTURE="$TEST_ROOT/capture"
}

# 3 fixture共通: root tracked porcelain増分0 (PUBLISHER_SINGLE 中は root を直接書き換えない)を
# 検証するために、旧entry(24h超過+確認不要=archive対象)を含む掲示板をgit管理下に置く。
_publisher_single_write_old_board() {
    local path="$1" count="${2:-3}"
    python3 - "$path" "$count" <<'PY'
import sys
path = sys.argv[1]
count = int(sys.argv[2])
lines = ["entries:\n"]
for i in range(count):
    lines.append(
        "- id: 'blt_old_%d'\n"
        "  content: |-\n"
        "    old fixture entry %d\n"
        "  posted_by: 'karo'\n"
        "  posted_at: '2000-01-01T00:00:%02d'\n"
        "  requires_confirmation: false\n"
        "  action_type: 'info'\n"
        "  actioned_by: ''\n"
        "  notify_targets: []\n"
        "  confirmed_by: []\n"
        "  status: 'open'\n" % (i, i, i % 60)
    )
open(path, "w", encoding="utf-8").write("".join(lines))
PY
}

_publisher_single_git_init() {
    local root="$1"
    git -C "$root" init -q
    git -C "$root" -c user.email=fixture@test -c user.name=fixture add -A
    git -C "$root" -c user.email=fixture@test -c user.name=fixture commit -qm init
    mkdir -p "$root/queue/flags"
    printf 'enabled_at: fixture\nby: test\n' > "$root/queue/flags/publisher_single"
}

teardown() {
    rm -r -- "$TEST_ROOT"
}

@test "typed escalation bulletin rejects incomplete evidence and accepts complete evidence" {
    run env \
        BULLETIN_ROOT_OVERRIDE="$TEST_ROOT" \
        BULLETIN_NOTIFY=shogun \
        BULLETIN_INBOX_WRITE="$TEST_ROOT/scripts/inbox_write_fixture.sh" \
        BULLETIN_NOTIFY_FAILURE_LOG="$TEST_ROOT/logs/failures.yaml" \
        bash "$TEST_ROOT/scripts/bulletin_write.sh" karo 'CRITICAL escalation' false escalation
    [ "$status" -eq 2 ]
    [[ "$output" == *'Template:'* ]]
    [ ! -e "$BULLETIN_NOTIFY_CAPTURE" ]

    local good=$'試行コマンド: bash scripts/check.sh\nexit_code: 1\n特定した不足: gate state remains open\n次の行動: 家老レーンで是正する\n実行者: karo'
    run env \
        BULLETIN_ROOT_OVERRIDE="$TEST_ROOT" \
        BULLETIN_NOTIFY=shogun \
        BULLETIN_INBOX_WRITE="$TEST_ROOT/scripts/inbox_write_fixture.sh" \
        BULLETIN_NOTIFY_FAILURE_LOG="$TEST_ROOT/logs/failures.yaml" \
        bash "$TEST_ROOT/scripts/bulletin_write.sh" karo "$good" false escalation
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$BULLETIN_NOTIFY_CAPTURE")" -eq 1 ]
}

@test "bulletin BLOCK prose in info lane is not an escalation false positive" {
    run env \
        BULLETIN_ROOT_OVERRIDE="$TEST_ROOT" \
        BULLETIN_NOTIFY=shogun \
        BULLETIN_INBOX_WRITE="$TEST_ROOT/scripts/inbox_write_fixture.sh" \
        BULLETIN_NOTIFY_FAILURE_LOG="$TEST_ROOT/logs/failures.yaml" \
        bash "$TEST_ROOT/scripts/bulletin_write.sh" saizo 'gate BLOCK通知' false info
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$BULLETIN_NOTIFY_CAPTURE")" -eq 1 ]
}

@test "ninja-authored bulletins use trusted transport identity and each deliver once" {
    for fixture_id in $(seq 1 13); do
        run env \
            BULLETIN_NOTIFY=shogun \
            BULLETIN_INBOX_WRITE="$TEST_ROOT/scripts/inbox_write_fixture.sh" \
            BULLETIN_NOTIFY_FAILURE_LOG="$TEST_ROOT/logs/failures.yaml" \
            bash "$TEST_ROOT/scripts/bulletin_write.sh" saizo "contract probe $fixture_id" false info
        [ "$status" -eq 0 ]
    done

    [ "$(wc -l < "$BULLETIN_NOTIFY_CAPTURE")" -eq 13 ]
    [ "$(sort -u "$BULLETIN_NOTIFY_CAPTURE")" = "shogun|bulletin_notify|bulletin_write|bulletin_notify" ]
    [ ! -s "$TEST_ROOT/logs/failures.yaml" ]
}

# test_necessity: 数値を含むレビュー依頼は途中laneであり、最終計測報告の3点セットを要求しない。
@test "commander review request with numeric references is delivered without measurement evidence bundle" {
    run env \
        BULLETIN_NOTIFY=shogun \
        BULLETIN_INBOX_WRITE="$TEST_ROOT/scripts/inbox_write_fixture.sh" \
        BULLETIN_NOTIFY_FAILURE_LOG="$TEST_ROOT/logs/failures.yaml" \
        bash "$TEST_ROOT/scripts/bulletin_write.sh" karo \
        "関連: cmd_simple_review。将軍レビュー依頼。v3.9の実測7項目を検分されたし。" false info

    [ "$status" -eq 0 ]
    [ "$(wc -l < "$BULLETIN_NOTIFY_CAPTURE")" -eq 1 ]
}

# test_necessity: レビュー依頼でない数値結果報告には従来どおり3点セットを要求する。
@test "commander numeric result report still requires measurement evidence bundle" {
    run env \
        BULLETIN_NOTIFY=shogun \
        BULLETIN_INBOX_WRITE="$TEST_ROOT/scripts/inbox_write_fixture.sh" \
        BULLETIN_NOTIFY_FAILURE_LOG="$TEST_ROOT/logs/failures.yaml" \
        bash "$TEST_ROOT/scripts/bulletin_write.sh" karo \
        "関連: cmd_numeric_result。修正後5件PASS。" false info

    [ "$status" -ne 0 ]
    [[ "$output" == *"3点セットの欠落要素あり"* ]]
    [ ! -e "$BULLETIN_NOTIFY_CAPTURE" ]
}

# test_necessity: 閉じた指揮官チャネルでは既成結果の表示コマンドも証拠導線として受理する不変量。
@test "commander numeric evidence accepts display command without semantic policing" {
    run env \
        BULLETIN_NOTIFY=shogun \
        BULLETIN_INBOX_WRITE="$TEST_ROOT/scripts/inbox_write_fixture.sh" \
        BULLETIN_NOTIFY_FAILURE_LOG="$TEST_ROOT/logs/failures.yaml" \
        bash "$TEST_ROOT/scripts/bulletin_write.sh" karo \
        "関連: cmd_numeric_result。5件PASS。集計コマンド: sed -n '1,20p' result.md。出力行(生): pass=5。1件の定義: 結果表の1行。" false info

    [ "$status" -eq 0 ]
    [ "$(wc -l < "$BULLETIN_NOTIFY_CAPTURE")" -eq 1 ]
}

# test_necessity: 見出しだけで空値・プレースホルダの証拠を受理しない不変量。
@test "commander numeric evidence rejects empty or placeholder values" {
    run env \
        BULLETIN_NOTIFY=shogun \
        BULLETIN_INBOX_WRITE="$TEST_ROOT/scripts/inbox_write_fixture.sh" \
        BULLETIN_NOTIFY_FAILURE_LOG="$TEST_ROOT/logs/failures.yaml" \
        bash "$TEST_ROOT/scripts/bulletin_write.sh" karo \
        "関連: cmd_numeric_result。5件PASS。集計コマンド: N/A。出力行(生): N/A。1件の定義: TODO。" false info

    [ "$status" -ne 0 ]
    [[ "$output" == *"集計コマンドの値が空またはプレースホルダ"* ]]
    [[ "$output" == *"出力行の値が空またはプレースホルダ"* ]]
    [[ "$output" == *"1件の定義が空またはプレースホルダ"* ]]
    [ ! -e "$BULLETIN_NOTIFY_CAPTURE" ]
}

# test_necessity: 3見出しがあっても各欄が空なら後続欄の値を誤取得せず拒否する不変量。
@test "commander numeric evidence rejects marker-only empty fields" {
    run env \
        BULLETIN_NOTIFY=shogun \
        BULLETIN_INBOX_WRITE="$TEST_ROOT/scripts/inbox_write_fixture.sh" \
        BULLETIN_NOTIFY_FAILURE_LOG="$TEST_ROOT/logs/failures.yaml" \
        bash "$TEST_ROOT/scripts/bulletin_write.sh" karo \
        "関連: cmd_numeric_result。5件PASS。集計コマンド: 。出力行(生): 。1件の定義: 。" false info

    [ "$status" -ne 0 ]
    [[ "$output" == *"集計コマンドの値が空またはプレースホルダ"* ]]
    [[ "$output" == *"出力行の値が空またはプレースホルダ"* ]]
    [[ "$output" == *"1件の定義が空またはプレースホルダ"* ]]
    [ ! -e "$BULLETIN_NOTIFY_CAPTURE" ]
}

# test_necessity: 実集計コマンド・生出力・具体的単位定義を揃えた数値報告を配送する不変量。
@test "commander numeric evidence accepts substantive measurement bundle" {
    run env \
        BULLETIN_NOTIFY=shogun \
        BULLETIN_INBOX_WRITE="$TEST_ROOT/scripts/inbox_write_fixture.sh" \
        BULLETIN_NOTIFY_FAILURE_LOG="$TEST_ROOT/logs/failures.yaml" \
        bash "$TEST_ROOT/scripts/bulletin_write.sh" karo \
        "関連: cmd_numeric_result。5件PASS。集計コマンド: awk -F, 'NR>1 {n++} END {print n}' result.csv。出力行(生): pass=5 fail=0。1件の定義: CSVのヘッダを除くデータ行。" false info

    [ "$status" -eq 0 ]
    [ "$(wc -l < "$BULLETIN_NOTIFY_CAPTURE")" -eq 1 ]
}

# test_necessity: PUBLISHER_SINGLE中、bulletin_write経路はroot boardを直接書き換えず
# (yaml_auto_archive.shの汎用count-basedトリムを起動しない)、新規投稿はledger append opを
# 発行するのみである。publisher apply後に初めてroot boardへ反映される。
@test "PUBLISHER_SINGLE ON: bulletin_write route never trims root board; ledger apply materializes the write" {
    _publisher_single_write_old_board "$TEST_ROOT/queue/bulletin_board.yaml"
    _publisher_single_git_init "$TEST_ROOT"
    LEDGER_STATE="$BATS_TEST_TMPDIR/ledger_state_bw"
    mkdir -p "$LEDGER_STATE"

    run env \
        BULLETIN_ROOT_OVERRIDE="$TEST_ROOT" \
        BULLETIN_NOTIFY=shogun \
        BULLETIN_INBOX_WRITE="$TEST_ROOT/scripts/inbox_write_fixture.sh" \
        BULLETIN_NOTIFY_FAILURE_LOG="$TEST_ROOT/logs/failures.yaml" \
        BULLETIN_AUTO_ARCHIVE_SYNC=1 \
        SHOGUN_ROOT="$TEST_ROOT" \
        SHOGUN_STATE_DIR="$LEDGER_STATE" \
        bash "$TEST_ROOT/scripts/bulletin_write.sh" saizo "PUBLISHER_SINGLE fixture post" false info
    [ "$status" -eq 0 ]

    # AC2: root tracked porcelain増分0 — bulletin_write.sh自身はrootを一切書き換えない
    [ -z "$(git -C "$TEST_ROOT" status --porcelain -- queue/bulletin_board.yaml)" ]

    local append_op
    append_op="$(grep -l '"op": "append"' "$LEDGER_STATE"/ledger_inbox/bulletin/*.yaml | head -1)"
    [ -n "$append_op" ]
    [[ "$(cat "$append_op")" == *'PUBLISHER_SINGLE fixture post'* ]]

    # publisher apply後: 新規投稿がroot boardへ materialize する
    run env SHOGUN_STATE_DIR="$LEDGER_STATE" bash "$TEST_ROOT/scripts/ledger_writer.sh" apply "$append_op"
    [ "$status" -eq 0 ]
    grep -q 'PUBLISHER_SINGLE fixture post' "$TEST_ROOT/queue/bulletin_board.yaml"
}

# test_necessity: PUBLISHER_SINGLE中、ninja_monitorの定期経路(check_bulletin_archive)は
# root boardを直接trimせず、期限超過エントリのcloseをledger update opとして発行する。
@test "PUBLISHER_SINGLE ON: ninja_monitor periodic bulletin archive route never trims root board; ledger apply closes eligible entries" {
    # check_bulletin_archiveはentry_count>30の時のみbulletin_archive.shを起動する
    _publisher_single_write_old_board "$TEST_ROOT/queue/bulletin_board.yaml" 35
    _publisher_single_git_init "$TEST_ROOT"
    LEDGER_STATE="$BATS_TEST_TMPDIR/ledger_state_nm"
    mkdir -p "$LEDGER_STATE"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

    DRIVER="$TEST_ROOT/nm_driver.sh"
    cat > "$DRIVER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export NINJA_MONITOR_LIB_ONLY=1 NINJA_MONITOR_FUNCTION_TIMING_LOG=disabled
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="$TEST_ROOT"
LOG="$TEST_ROOT/logs/monitor.log"
BULLETIN_ARCHIVE_INTERVAL=0
LAST_BULLETIN_ARCHIVE=0
export SHOGUN_STATE_DIR="$LEDGER_STATE"
check_bulletin_archive
EOF
    chmod +x "$DRIVER"

    run "$DRIVER"
    [ "$status" -eq 0 ]

    # AC2: root tracked porcelain増分0 — 定期routeもrootを直接trimしない
    [ -z "$(git -C "$TEST_ROOT" status --porcelain -- queue/bulletin_board.yaml)" ]

    local update_op
    update_op="$(grep -l '"op": "update"' "$LEDGER_STATE"/ledger_inbox/bulletin/*.yaml | head -1)"
    [ -n "$update_op" ]
    [[ "$(cat "$update_op")" == *'"status": "closed"'* ]]

    # publisher apply後: 対象entryがclosedへ更新される(archive成立)
    run env SHOGUN_STATE_DIR="$LEDGER_STATE" bash "$TEST_ROOT/scripts/ledger_writer.sh" apply "$update_op"
    [ "$status" -eq 0 ]
    grep -q 'status: "closed"' "$TEST_ROOT/queue/bulletin_board.yaml"
}

# test_necessity: PUBLISHER_SINGLE中、yaml_auto_archive.sh(汎用count-basedトリム)自体も
# queue/bulletin_board.yamlをroot trimせず、bulletin_archive.shのledger routeへ委譲する
# (2026-09-03 23:27 -11行prune事故の実writerに対する直接regression test)。
@test "PUBLISHER_SINGLE ON: generic yaml_auto_archive.sh delegates bulletin_board.yaml to the ledger route instead of trimming root" {
    _publisher_single_write_old_board "$TEST_ROOT/queue/bulletin_board.yaml"
    _publisher_single_git_init "$TEST_ROOT"
    LEDGER_STATE="$BATS_TEST_TMPDIR/ledger_state_yaa"
    mkdir -p "$LEDGER_STATE"

    run env SHOGUN_ROOT="$TEST_ROOT" SHOGUN_STATE_DIR="$LEDGER_STATE" \
        bash "$TEST_ROOT/scripts/yaml_auto_archive.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP queue/bulletin_board.yaml"*"PUBLISHER_SINGLE ON"* ]]

    # AC2: root tracked porcelain増分0 — 汎用archiverもrootを直接trimしない
    [ -z "$(git -C "$TEST_ROOT" status --porcelain -- queue/bulletin_board.yaml)" ]

    local update_op
    update_op="$(grep -l '"op": "update"' "$LEDGER_STATE"/ledger_inbox/bulletin/*.yaml | head -1)"
    [ -n "$update_op" ]
}

# test_necessity: AC1「全caller」要件の直接証跡。cmd_save.sh(quality logがrepository既定の
# 場合に無条件でyaml_auto_archive.shを呼ぶ、target_pathに含まれる別caller)からの起動でも
# root boardを直接trimしないことを、cmd_save.shが実際に使う呼出し形(引数なしbash起動)で確認する。
@test "PUBLISHER_SINGLE ON: cmd_save.sh's unconditional yaml_auto_archive.sh call never trims root board" {
    _publisher_single_write_old_board "$TEST_ROOT/queue/bulletin_board.yaml"
    _publisher_single_git_init "$TEST_ROOT"
    LEDGER_STATE="$BATS_TEST_TMPDIR/ledger_state_cmdsave"
    mkdir -p "$LEDGER_STATE"

    # scripts/cmd_save.sh:3146 の呼出し形を再現: `bash "$SCRIPT_DIR/yaml_auto_archive.sh"`
    # (引数なし・SHOGUN_ROOT未設定・SCRIPT_DIRのみ既知)。
    run env SHOGUN_STATE_DIR="$LEDGER_STATE" \
        bash "$TEST_ROOT/scripts/yaml_auto_archive.sh"
    [ "$status" -eq 0 ]

    # AC1: cmd_save.sh経由でもroot tracked porcelain増分0
    [ -z "$(git -C "$TEST_ROOT" status --porcelain -- queue/bulletin_board.yaml)" ]

    local update_op
    update_op="$(grep -l '"op": "update"' "$LEDGER_STATE"/ledger_inbox/bulletin/*.yaml 2>/dev/null | head -1)"
    [ -n "$update_op" ]
}

# test_necessity: PUBLISHER_SINGLE中、bulletin_archive.shの直接呼び出し経路もroot boardを
# trimせず、期限超過エントリのcloseをledger update opとして発行する。
@test "PUBLISHER_SINGLE ON: direct bulletin_archive.sh route never trims root board; ledger apply closes eligible entries" {
    _publisher_single_write_old_board "$TEST_ROOT/queue/bulletin_board.yaml"
    _publisher_single_git_init "$TEST_ROOT"
    LEDGER_STATE="$BATS_TEST_TMPDIR/ledger_state_direct"
    mkdir -p "$LEDGER_STATE"

    run env \
        BULLETIN_ROOT_OVERRIDE="$TEST_ROOT" \
        SHOGUN_STATE_DIR="$LEDGER_STATE" \
        bash "$TEST_ROOT/scripts/bulletin_archive.sh"
    [ "$status" -eq 0 ]

    # AC2: root tracked porcelain増分0 — 直接呼び出しでもrootを直接trimしない
    [ -z "$(git -C "$TEST_ROOT" status --porcelain -- queue/bulletin_board.yaml)" ]

    local update_op
    update_op="$(grep -l '"op": "update"' "$LEDGER_STATE"/ledger_inbox/bulletin/*.yaml | head -1)"
    [ -n "$update_op" ]

    # publisher apply後: 対象entryがclosedへ更新される(archive成立)
    run env SHOGUN_STATE_DIR="$LEDGER_STATE" bash "$TEST_ROOT/scripts/ledger_writer.sh" apply "$update_op"
    [ "$status" -eq 0 ]
    grep -q 'status: "closed"' "$TEST_ROOT/queue/bulletin_board.yaml"
}
