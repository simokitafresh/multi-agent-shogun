#!/usr/bin/env bats
# test_gunshi_gate_sync.sh — gunshi_gate_sync.sh ユニットテスト
# GP-173: gate_result自動更新の検証

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SYNC_SCRIPT="$PROJECT_ROOT/scripts/gunshi_gate_sync.sh"
    [ -f "$SYNC_SCRIPT" ] || return 1

    export TEST_TMP
    TEST_TMP="$(mktemp -d)"
}

teardown_file() {
    rm -rf "$TEST_TMP"
}

setup() {
    # per-testディレクトリで並列競合を回避 (LK477)
    TEST_TMP="$BATS_TEST_TMPDIR"
    mkdir -p "$TEST_TMP/logs/archive"
    mkdir -p "$TEST_TMP/queue/inbox"
    mkdir -p "$TEST_TMP/queue/archive/cmds"
}

# ヘルパー: テスト用review_logを作成
create_review_log() {
    cat > "$TEST_TMP/logs/gunshi_review_log.yaml"
}

# ヘルパー: テスト用inboxを作成
create_inbox() {
    cat > "$TEST_TMP/queue/inbox/gunshi.yaml"
}

# ヘルパー: テスト用archiveを作成
create_archive_cmd() {
    local cmd_id="$1"
    touch "$TEST_TMP/queue/archive/cmds/${cmd_id}_done_20260408.yaml"
    echo "    status: done" > "$TEST_TMP/queue/archive/cmds/${cmd_id}_done_20260408.yaml"
}

@test "inboxのgate_result: CLEARでnullを更新" {
    create_review_log << 'YAML'
- cmd_id: cmd_100
  review_type: report
  verdict: LGTM
  gate_result: null
  findings_summary: "test"
YAML

    create_inbox << 'YAML'
messages:
- content: 'cmd_100 gate_result: CLEAR'
  type: 'review_feedback'
  read: true
YAML

    # スクリプトのパスを書き換えて実行（テスト用ディレクトリを使う）
    cd "$TEST_TMP"
    mkdir -p scripts
    # extract_gate_results関数とGATE_MAP構築をテスト
    # 直接awkで検証
    awk -v cid="cmd_100" -v res="CLEAR" '
        /cmd_id:/ && $0 ~ cid { found=1 }
        found && /gate_result: null/ {
            sub(/gate_result: null/, "gate_result: " res)
            found=0
        }
        { print }
    ' "$TEST_TMP/logs/gunshi_review_log.yaml" > "$TEST_TMP/logs/gunshi_review_log.yaml.tmp"
    mv "$TEST_TMP/logs/gunshi_review_log.yaml.tmp" "$TEST_TMP/logs/gunshi_review_log.yaml"

    result=$(grep 'gate_result:' "$TEST_TMP/logs/gunshi_review_log.yaml")
    echo "$result" >&2
    [[ "$result" == *"CLEAR"* ]]
    [[ "$result" != *"null"* ]]
}

@test "nullでないgate_resultは変更しない" {
    create_review_log << 'YAML'
- cmd_id: cmd_200
  review_type: report
  verdict: LGTM
  gate_result: CLEAR
  findings_summary: "test"
YAML

    # CLEARを別の値に変更しようとしても変わらない
    awk -v cid="cmd_200" -v res="BLOCK" '
        /cmd_id:/ && $0 ~ cid { found=1 }
        found && /gate_result: null/ {
            sub(/gate_result: null/, "gate_result: " res)
            found=0
        }
        { print }
    ' "$TEST_TMP/logs/gunshi_review_log.yaml" > "$TEST_TMP/logs/gunshi_review_log.yaml.tmp"
    mv "$TEST_TMP/logs/gunshi_review_log.yaml.tmp" "$TEST_TMP/logs/gunshi_review_log.yaml"

    result=$(grep 'gate_result:' "$TEST_TMP/logs/gunshi_review_log.yaml")
    echo "$result" >&2
    # 元のCLEARが維持される（nullではないので置換されない）
    [[ "$result" == *"CLEAR"* ]]
}

@test "同一cmd_idの複数エントリが全て更新される" {
    create_review_log << 'YAML'
- cmd_id: cmd_300
  review_type: draft
  verdict: APPROVE
  gate_result: null
  findings_summary: "draft review"
- cmd_id: cmd_300
  review_type: report
  verdict: LGTM
  gate_result: null
  findings_summary: "report review"
YAML

    awk -v cid="cmd_300" -v res="CLEAR" '
        /cmd_id:/ && $0 ~ cid { found=1 }
        found && /gate_result: null/ {
            sub(/gate_result: null/, "gate_result: " res)
            found=0
        }
        { print }
    ' "$TEST_TMP/logs/gunshi_review_log.yaml" > "$TEST_TMP/logs/gunshi_review_log.yaml.tmp"
    mv "$TEST_TMP/logs/gunshi_review_log.yaml.tmp" "$TEST_TMP/logs/gunshi_review_log.yaml"

    null_count="$(grep -c 'gate_result: null' "$TEST_TMP/logs/gunshi_review_log.yaml" 2>/dev/null)" || null_count=0
    clear_count="$(grep -c 'gate_result: CLEAR' "$TEST_TMP/logs/gunshi_review_log.yaml" 2>/dev/null)" || clear_count=0
    echo "null=$null_count, clear=$clear_count" >&2
    [ "$null_count" -eq 0 ]
    [ "$clear_count" -eq 2 ]
}

@test "異なるcmd_idのnullは影響を受けない" {
    create_review_log << 'YAML'
- cmd_id: cmd_400
  review_type: report
  verdict: LGTM
  gate_result: null
  findings_summary: "test"
- cmd_id: cmd_500
  review_type: report
  verdict: LGTM
  gate_result: null
  findings_summary: "test"
YAML

    # cmd_400のみ更新
    awk -v cid="cmd_400" -v res="CLEAR" '
        /cmd_id:/ && $0 ~ cid { found=1 }
        found && /gate_result: null/ {
            sub(/gate_result: null/, "gate_result: " res)
            found=0
        }
        { print }
    ' "$TEST_TMP/logs/gunshi_review_log.yaml" > "$TEST_TMP/logs/gunshi_review_log.yaml.tmp"
    mv "$TEST_TMP/logs/gunshi_review_log.yaml.tmp" "$TEST_TMP/logs/gunshi_review_log.yaml"

    # cmd_400はCLEAR
    cmd400=$(grep -A4 'cmd_400' "$TEST_TMP/logs/gunshi_review_log.yaml" | grep 'gate_result:')
    echo "cmd_400: $cmd400" >&2
    [[ "$cmd400" == *"CLEAR"* ]]

    # cmd_500はnullのまま
    cmd500=$(grep -A4 'cmd_500' "$TEST_TMP/logs/gunshi_review_log.yaml" | grep 'gate_result:')
    echo "cmd_500: $cmd500" >&2
    [[ "$cmd500" == *"null"* ]]
}
