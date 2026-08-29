#!/usr/bin/env bats
# test_necessity: Idle task placeholders are excluded from live report parsing; active malformed/missing reports and non-transient I/O errors remain BLOCK.
# test_gate_queue_yaml_parse.bats
# cmd_karo_hotfix_queue_yaml_atomicity_202607110113
# Purpose: scripts/gates/gate_queue_yaml_parse.sh の挙動を検証する。
# Origin: 2026-07-11 01:09 queue/tasks/kagemaru.yaml破損(queue YAML parse error)。
#   本ゲートはqueue/配下の運用YAMLを横断parseし、破損を検出してALERTを出す。
#   yaml_field_set.sh修正後もWSL2 drvfs越しのrename(2)は瞬間的なENOENTを
#   生じうる(POSIX完全準拠ではない)ため、FileNotFoundErrorのみ1回だけ短い
#   待機を挟んで再読込し、真の破損(YAMLError)や恒久的な不在は即ALERTのままとする。

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_queue_yaml_parse.sh"
    [ -f "$GATE_SCRIPT" ] || return 1
}

setup() {
    export TEST_ROOT
    # CI clean checkoutではtmp/(.gitignore対象)が存在しない。WSL2 drvfs越しの
    # rename(2)挙動を再現するため$BATS_TMPDIR(別filesystemのことがある)ではなく
    # 本番queue/と同一filesystem上の$PROJECT_ROOT/tmpを使う必要があり、
    # mktemp -dの前に親dirの存在を保証する。
    mkdir -p "$PROJECT_ROOT/tmp"
    TEST_ROOT="$(mktemp -d "$PROJECT_ROOT/tmp/gate_qyp_test.XXXXXX")"
    mkdir -p "$TEST_ROOT/queue/tasks" "$TEST_ROOT/queue/reports" "$TEST_ROOT/queue/inbox"
    cat > "$TEST_ROOT/queue/shogun_to_karo.yaml" <<'EOF'
commands: []
EOF
    cat > "$TEST_ROOT/queue/pending_decisions.yaml" <<'EOF'
decisions: []
EOF
    cat > "$TEST_ROOT/queue/insights.yaml" <<'EOF'
insights: []
EOF
    cat > "$TEST_ROOT/queue/tasks/kagemaru.yaml" <<'EOF'
task:
  status: idle
  report_path: queue/reports/live.yaml
EOF
    printf 'report:\n  status: ready\n' > "$TEST_ROOT/queue/reports/live.yaml"
}

teardown() {
    rm -rf "$TEST_ROOT"
}

@test "全ファイルが有効なYAMLならOK・exit 0" {
    run env QUEUE_YAML_PARSE_ROOT="$TEST_ROOT" bash "$GATE_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: queue YAML parse clean"* ]]
}

@test "queue/tasks/配下に構造外裸テキストが混入するとALERT・exit 1" {
    printf 'task:\n  status: line1\nline2 malformed\n' > "$TEST_ROOT/queue/tasks/kagemaru.yaml"
    run env QUEUE_YAML_PARSE_ROOT="$TEST_ROOT" bash "$GATE_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ALERT: queue YAML parse error"* ]]
    [[ "$output" == *"queue/tasks/kagemaru.yaml"* ]]
}

@test "taskが指すlive reportのYAML破損はALERT・exit 1" {
    printf 'task:\n  status: acknowledged\n  report_path: queue/reports/live.yaml\n' > "$TEST_ROOT/queue/tasks/kagemaru.yaml"
    printf 'report: [broken\n' > "$TEST_ROOT/queue/reports/live.yaml"
    run env QUEUE_YAML_PARSE_ROOT="$TEST_ROOT" bash "$GATE_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"queue/reports/live.yaml"* ]]
}

@test "idle taskのplaceholder report_path欠落はparse集合へ追加せずOKになる" {
    printf 'task:\n  task_id: idle\n  status: idle\n  report_path: queue/reports/placeholder.yaml\n' > "$TEST_ROOT/queue/tasks/sasuke.yaml"
    rm -f "$TEST_ROOT/queue/reports/placeholder.yaml"
    run env QUEUE_YAML_PARSE_ROOT="$TEST_ROOT" bash "$GATE_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: queue YAML parse clean"* ]]
}

@test "一時的なFileNotFoundError(rename直後の瞬間的ENOENT)は20回反復で吸収されOKになる" {
    # yaml_field_set.shのmv(atomic rename)がWSL2 drvfs越しで一瞬destinationを
    # 消す挙動(実測済み)を20回模擬する。ゲートの有界リトライが毎回吸収するはず。
    local target="$TEST_ROOT/queue/tasks/kagemaru.yaml"
    local i
    for i in $(seq 1 20); do
        printf 'task:\n  status: idle\n' > "$target"
        (
            rm -f "$target"
            sleep 0.01
            printf 'task:\n  status: idle\n' > "$target"
        ) &
        run env QUEUE_YAML_PARSE_ROOT="$TEST_ROOT" bash "$GATE_SCRIPT"
        wait
        [ "$status" -eq 0 ]
        [[ "$output" == *"OK: queue YAML parse clean"* ]]
    done
}

@test "active taskの欠落reportはALERT・exit 1を維持する" {
    printf 'task:\n  status: acknowledged\n  report_path: queue/reports/missing.yaml\n' > "$TEST_ROOT/queue/tasks/kagemaru.yaml"
    rm -f "$TEST_ROOT/queue/reports/missing.yaml"
    run env QUEUE_YAML_PARSE_ROOT="$TEST_ROOT" bash "$GATE_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"queue/reports/missing.yaml"* ]]
}

@test "FileNotFoundError以外のOSError(ディレクトリをファイルとしてopen)はリトライで握りつぶされずALERT・exit 1" {
    # リトライはFileNotFoundErrorのみが対象。IsADirectoryError等の他のOSErrorまで
    # 一律リトライ/マスクしてしまうと真の異常(権限・I/Oエラー等)を隠す退行になるため、
    # ファイルの代わりにディレクトリを置いて即時ALERTになることを確認する。
    rm -f "$TEST_ROOT/queue/tasks/kagemaru.yaml"
    mkdir -p "$TEST_ROOT/queue/tasks/kagemaru.yaml"
    run env QUEUE_YAML_PARSE_ROOT="$TEST_ROOT" bash "$GATE_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ALERT: queue YAML parse error"* ]]
    [[ "$output" == *"io_error"* ]]
}
