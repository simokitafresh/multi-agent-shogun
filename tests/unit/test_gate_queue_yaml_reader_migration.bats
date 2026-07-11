#!/usr/bin/env bats
# test_gate_queue_yaml_reader_migration.bats
# cmd_karo_hotfix_shogun_startup_tech_202607110916 (AC1)
# Purpose: scripts/gates/gate_queue_yaml_reader_migration.sh の挙動を検証する。
# Origin: cmd_karo_hotfix_queue_yaml_atomicity_202607110113 follow-up-2で作成された
#   ゲート本体はテストを欠いたままuntracked状態で残存していた。本ゲートは
#   at-riskなqueue YAML(queue/tasks, queue/reports, queue/inbox等)に触れる
#   bare yaml.safe_load()/yaml.load()呼出しのうちsafe_load_retry()未移行の
#   ものを検出しBLOCKする。ROOT_DIRはBASH_SOURCE基準で算出されるため、
#   ゲート本体をtmpの同一相対位置(<TEST_ROOT>/scripts/gates/)へ複製して
#   本番の未移行214件を巻き込まずに隔離検証する。

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export GATE_SRC="$PROJECT_ROOT/scripts/gates/gate_queue_yaml_reader_migration.sh"
    [ -f "$GATE_SRC" ] || return 1
}

setup() {
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$PROJECT_ROOT/tmp/gate_qyrm_test.XXXXXX")"
    mkdir -p "$TEST_ROOT/scripts/gates" "$TEST_ROOT/.claude/hooks"
    cp "$GATE_SRC" "$TEST_ROOT/scripts/gates/gate_queue_yaml_reader_migration.sh"
    export GATE_SCRIPT="$TEST_ROOT/scripts/gates/gate_queue_yaml_reader_migration.sh"
}

teardown() {
    rm -rf "$TEST_ROOT"
}

@test "at-riskパターンに触れないbare yaml.safe_loadは対象外・exit 0" {
    cat > "$TEST_ROOT/scripts/generic_util.py" <<'EOF'
import yaml
data = yaml.safe_load(open("config/settings.yaml"))
EOF
    run bash "$GATE_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: at-riskなqueue YAML readerは全てsafe_load_retry経由"* ]]
}

@test "at-riskなqueue/tasks/への未移行bare yaml.safe_loadはBLOCK・exit 1" {
    cat > "$TEST_ROOT/scripts/bad_reader.py" <<'EOF'
import yaml
path = "queue/tasks/example.yaml"
with open(path) as f:
    data = yaml.safe_load(f) or {}
EOF
    run bash "$GATE_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: at-riskなqueue YAMLへの未移行reader"* ]]
    [[ "$output" == *"bad_reader.py"* ]]
    [[ "$output" == *"scanned_bare_calls=1 migrated=0 unmigrated=1"* ]]
}

@test "同一ファイル内にsafe_load_retry経路がありこの行だけ未移行の場合は個別事情マーカー付きでBLOCK" {
    cat > "$TEST_ROOT/scripts/mixed_reader.py" <<'EOF'
from yaml_safe_read import safe_load_retry

TASK_PATH = "queue/tasks/foo.yaml"


def helper_a(path):
    return safe_load_retry(path)


def helper_b(path):
    with open(path) as f:
        return yaml.safe_load(f)
EOF
    run bash "$GATE_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"mixed_reader.py"* ]]
    [[ "$output" == *"同ファイル内にsafe_load_retry経路ありだがこの呼出しは未移行"* ]]
}

@test "safe_load_retryへ完全移行済み(bare呼出しが残っていない)ファイルはBLOCK対象外" {
    cat > "$TEST_ROOT/scripts/migrated_reader.py" <<'EOF'
from yaml_safe_read import safe_load_retry

TASK_PATH = "queue/tasks/foo.yaml"


def helper(path):
    return safe_load_retry(path)
EOF
    run bash "$GATE_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: at-riskなqueue YAML readerは全てsafe_load_retry経由"* ]]
}

@test "同一行にsafe_load_retry文字列を含むyaml.safe_load呼出しはmigrated扱いでBLOCKされない" {
    cat > "$TEST_ROOT/scripts/inline_flag_reader.py" <<'EOF'
import yaml
TASK_PATH = "queue/tasks/foo.yaml"
data = safe_load_retry(TASK_PATH) if USE_RETRY else yaml.safe_load(open(TASK_PATH))
EOF
    run bash "$GATE_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"scanned_bare_calls=1, migrated=1"* ]]
}
