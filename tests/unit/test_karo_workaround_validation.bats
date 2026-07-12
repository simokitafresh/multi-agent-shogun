#!/usr/bin/env bats
# test_karo_workaround_validation.bats — cmd_1542 + cmd_karo_env_change_gate 単体テスト
# AC1: validate_ninja_id() — ninja_id有効性チェック
# AC2: root_cause最小長+null/empty拒否

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../scripts" && pwd)/karo_workaround_log.sh"

setup() {
    export TMPDIR="${BATS_TMPDIR:-/tmp}"
    TEST_DIR=$(mktemp -d "$TMPDIR/wa_test.XXXXXX")

    # Create minimal repo structure
    mkdir -p "$TEST_DIR/config" "$TEST_DIR/queue/tasks" "$TEST_DIR/logs" "$TEST_DIR/scripts/lib"

    # settings.yaml with known agents
    cat > "$TEST_DIR/config/settings.yaml" <<'YAML'
roles:
  agents:
    hayate:
      type: claude
      role: ninja
    hanzo:
      type: claude
      role: ninja
    kotaro:
      type: claude
      role: ninja
YAML

    # Task files
    touch "$TEST_DIR/queue/tasks/hayate.yaml"
    touch "$TEST_DIR/queue/tasks/hanzo.yaml"
    touch "$TEST_DIR/queue/tasks/kotaro.yaml"

    # Stub ntfy.sh and insight_write.sh to prevent real notifications
    cat > "$TEST_DIR/scripts/ntfy.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "$TEST_DIR/scripts/ntfy.sh"
    cat > "$TEST_DIR/scripts/insight_write.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "$TEST_DIR/scripts/insight_write.sh"
    cat > "$TEST_DIR/scripts/pending_decision_write.sh" <<'SH'
#!/usr/bin/env bash
echo "PD:$*" >> "${BASH_SOURCE[0]%.sh}.log"
exit 0
SH
    chmod +x "$TEST_DIR/scripts/pending_decision_write.sh"

    cat > "$TEST_DIR/scripts/sample_gate.sh" <<'SH'
#!/usr/bin/env bash
echo "ENV_CHANGE_MARKER"
SH
    chmod +x "$TEST_DIR/scripts/sample_gate.sh"

    # Copy under the fixture repo so the script's own SCRIPT_DIR/REPO_ROOT discovery
    # resolves to TEST_DIR without per-test sed rewrites on /mnt/c.
    cp "$SCRIPT" "$TEST_DIR/scripts/karo_workaround_log.sh"
    cp "$(dirname "$SCRIPT")/lib/known_ninjas.sh" "$TEST_DIR/scripts/lib/known_ninjas.sh"
    cp "$(dirname "$SCRIPT")/memory_db_live_insert.py" "$TEST_DIR/scripts/memory_db_live_insert.py"
    chmod +x "$TEST_DIR/scripts/karo_workaround_log.sh"

    TEST_SCRIPT="$TEST_DIR/scripts/karo_workaround_log.sh"
    export KARO_WA_BRAINWASH_CHECK="洗脳#2検証スキップ防止: 通常記録 0→1件 PASS"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# =============================================
# AC1: validate_ninja_id tests
# =============================================

@test "AC1: valid ninja_id (hayate) — no WARN" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" "test fix description"
    # Should NOT contain WARN about ninja_id
    [[ "$output" != *"有効なエージェント名ではない"* ]]
}

@test "LOG override: KARO_WORKAROUND_LOG_FILE isolates writes" {
    alt_log="$TEST_DIR/logs/alternate_workarounds.yaml"
    alt_lock="$TEST_DIR/logs/alternate_workarounds.lock"

    run env KARO_WORKAROUND_LOG_FILE="$alt_log" KARO_WORKAROUND_LOCK_FILE="$alt_lock" \
        bash "$TEST_SCRIPT" cmd_test hayate "test issue" "test fix description"
    [ "$status" -eq 0 ]

    run grep -n "cmd_id: cmd_test" "$alt_log"
    [ "$status" -eq 0 ]
    run grep -n "cmd_id: cmd_test" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -ne 0 ]
}

@test "AC1: valid ninja_id (unknown) — no error" {
    run bash "$TEST_SCRIPT" cmd_test unknown "test issue" "test fix description"
    [ "$status" -eq 0 ]
    [[ "$output" != *"known_ninjas"* ]]
}

@test "AC1: invalid ninja_id — exits 1" {
    run bash "$TEST_SCRIPT" cmd_test unknown_agent "test issue" "test fix description"
    [ "$status" -eq 1 ]
    [[ "$output" == *"known_ninjas(hayate/kagemaru/hanzo/saizo/kotaro/tobisaru/unknown)"* ]]
    run grep -n "cmd_id: cmd_test" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -ne 0 ]
}

@test "AC1: invalid ninja_id (typo) — exits 1" {
    run bash "$TEST_SCRIPT" cmd_test hayat "test issue" "test fix description"
    [ "$status" -eq 1 ]
    [[ "$output" == *"known_ninjas"* ]]
}

@test "argument auto-swap: validates ninja_id after cmd/ninja reversal is corrected" {
    run bash "$TEST_SCRIPT" hayate cmd_test "test issue" "test fix description"
    [ "$status" -eq 0 ]
    [[ "$output" == *"引数が逆順。自動スワップ実行"* ]]
    [[ "$output" != *"known_ninjas"* ]]
    run grep -n "cmd_id: cmd_test" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 0 ]
    run grep -n "ninja: hayate" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 0 ]
}

@test "AC1: valid ninja_id from tasks dir (kotaro) — no WARN" {
    run bash "$TEST_SCRIPT" cmd_test kotaro "test issue" "test fix description"
    [[ "$output" != *"有効なエージェント名ではない"* ]]
}

# =============================================
# AC2: root_cause (FIX) validation tests
# =============================================

@test "AC2: empty root_cause — emits WARN" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" ""
    [[ "$output" == *"root_causeが無効値"* ]]
}

@test "AC2: null root_cause — emits WARN" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" "null"
    [[ "$output" == *"root_causeが無効値"* ]]
}

@test "AC2: None root_cause — emits WARN" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" "None"
    [[ "$output" == *"root_causeが無効値"* ]]
}

@test "AC2: NULL root_cause — emits WARN" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" "NULL"
    [[ "$output" == *"root_causeが無効値"* ]]
}

@test "AC2: none root_cause — emits WARN" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" "none"
    [[ "$output" == *"root_causeが無効値"* ]]
}

@test "AC2: 1-char root_cause — emits short WARN" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" "x"
    [[ "$output" == *"root_causeが短すぎる"* ]]
}

@test "AC2: 2-char root_cause — emits short WARN" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" "ab"
    [[ "$output" == *"root_causeが短すぎる"* ]]
}

@test "AC2: 3-char root_cause — no WARN (minimum met)" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" "fix"
    [[ "$output" != *"root_causeが短すぎる"* ]]
    [[ "$output" != *"root_causeが無効値"* ]]
}

@test "AC2: valid root_cause — no WARN" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" "report_field_set.shでフォーマット修正"
    [[ "$output" != *"root_causeが短すぎる"* ]]
    [[ "$output" != *"root_causeが無効値"* ]]
}

@test "--wa without brainwash_check blocks before recording" {
    run env -u KARO_WA_BRAINWASH_CHECK \
        bash "$TEST_SCRIPT" --wa cmd_test hayate "test issue" "test root cause" report_yaml_format "" \
        "type=gate; file=scripts/sample_gate.sh; pattern=ENV_CHANGE_MARKER"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: brainwash_check未記入"* ]]

    run grep -n "cmd_id: cmd_test" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -ne 0 ]
}

@test "normal mode without brainwash_check blocks before recording" {
    run env -u KARO_WA_BRAINWASH_CHECK \
        bash "$TEST_SCRIPT" cmd_test hayate "test issue" "test root cause" report_yaml_format
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: brainwash_check未記入"* ]]

    run grep -n "cmd_id: cmd_test" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -ne 0 ]
}

@test "--wa brainwash_check without numbers blocks before recording" {
    run env KARO_WA_BRAINWASH_CHECK="洗脳確認済み" \
        bash "$TEST_SCRIPT" --wa cmd_test hayate "test issue" "test root cause" report_yaml_format "" \
        "type=gate; file=scripts/sample_gate.sh; pattern=ENV_CHANGE_MARKER"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: brainwash_checkに数値なし"* ]]

    run grep -n "cmd_id: cmd_test" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -ne 0 ]
}

@test "brainwash_check with number but no before-after delta blocks before recording" {
    run env KARO_WA_BRAINWASH_CHECK="洗脳#2確認済み" \
        bash "$TEST_SCRIPT" cmd_test hayate "test issue" "test root cause" report_yaml_format
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: brainwash_checkに修正前→後の数値差分なし"* ]]

    run grep -n "cmd_id: cmd_test" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -ne 0 ]
}

@test "--wa brainwash_check with numbers records the check" {
    run env KARO_WA_BRAINWASH_CHECK="洗脳#2検証スキップ防止: gate再実行 0→1件 PASS" \
        bash "$TEST_SCRIPT" --wa cmd_test hayate "test issue" "test root cause" report_yaml_format "" \
        "type=gate; file=scripts/sample_gate.sh; pattern=ENV_CHANGE_MARKER"
    [ "$status" -eq 0 ]

    run grep -n "brainwash_check: '洗脳#2検証スキップ防止: gate再実行 0→1件 PASS'" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 0 ]
}

# =============================================
# Clean mode should skip validation
# =============================================

@test "clean mode: skips root_cause validation" {
    run bash "$TEST_SCRIPT" --clean cmd_test hayate
    [[ "$output" != *"root_causeが無効値"* ]]
    [[ "$output" != *"root_causeが短すぎる"* ]]
    [[ "$output" == *"Clean:"* ]]
}

@test "explicit clean category: 3件目でもALERT/insight/PDを発火しない" {
    run bash "$TEST_SCRIPT" cmd_test_1 hayate "normal detail" "normal root cause" clean
    [ "$status" -eq 0 ]
    [[ "$output" == *"Logged:"* ]]

    run bash "$TEST_SCRIPT" cmd_test_2 hayate "normal detail" "normal root cause" clean
    [ "$status" -eq 0 ]
    [[ "$output" == *"Logged:"* ]]

    run bash "$TEST_SCRIPT" cmd_test_3 hayate "normal detail" "normal root cause" clean
    [ "$status" -eq 0 ]
    [[ "$output" == *"Logged:"* ]]
    [[ "$output" != *"ALERT"* ]]
    # GP-220: category=cleanで通常モード呼出し時はWARNが出る（正しい動作）
    [[ "$output" == *"category=cleanだが--cleanモードでない"* ]]

    [ ! -f "$TEST_DIR/scripts/pending_decision_write.log" ]
}

@test "AC1拡張: 6th arg missed_sg指定時のみYAMLへ出力される" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" "test fix description" report_yaml_format SG4
    [ "$status" -eq 0 ]
    run grep -n "missed_sg: 'SG4'" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 0 ]
}

@test "AC1拡張: missed_sg未指定時はYAMLへ出力しない" {
    run bash "$TEST_SCRIPT" cmd_test hayate "test issue" "test fix description" report_yaml_format
    [ "$status" -eq 0 ]
    run grep -n "missed_sg:" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -ne 0 ]
}

@test "AC3: --wa modeでenvironment_change未記入ならBLOCK" {
    run bash "$TEST_SCRIPT" --wa cmd_test hayate "test issue" "test fix description" report_yaml_format SG4
    [ "$status" -eq 1 ]
    [[ "$output" == *"environment_change未記入"* ]]
    [[ "$output" == *"BLOCK"* ]]
    run grep -n "cmd_id: cmd_test" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -ne 0 ]
}

@test "AC4: --wa modeでstructured environment_changeを検証してYAML記録" {
    run env KARO_WA_BRAINWASH_CHECK="洗脳#2検証スキップ防止: environment_change検証 1/1 PASS" \
        bash "$TEST_SCRIPT" --wa cmd_test hayate "test issue" "test fix description" report_yaml_format SG4 \
        "type=gate; file=scripts/sample_gate.sh; pattern=ENV_CHANGE_MARKER"
    [ "$status" -eq 0 ]
    [[ "$output" == *"environment_change検証OK"* ]]
    run grep -n "environment_change: 'type=gate; file=scripts/sample_gate.sh; pattern=ENV_CHANGE_MARKER'" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 0 ]
}

@test "AC4: --wa modeでstructured environment_change不一致ならBLOCK" {
    run bash "$TEST_SCRIPT" --wa cmd_test hayate "test issue" "test fix description" report_yaml_format SG4 \
        "type=gate; file=scripts/sample_gate.sh; pattern=DOES_NOT_EXIST_2185"
    [ "$status" -eq 1 ]
    [[ "$output" == *"environment_change未実装"* ]]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"DOES_NOT_EXIST_2185"* ]]
    run grep -n "cmd_id: cmd_test" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -ne 0 ]
}

@test "category-first entryもexplicit root_signatureがあれば3件目でALERT" {
    cat > "$TEST_DIR/logs/karo_workarounds.yaml" <<'YAML'
- category: report_yaml_format
  cmd_id: cmd_legacy_1
  detail: 'legacy'
  ninja: hayate
  root_cause: 'legacy root cause'
  timestamp: '2026-04-25T00:00:00Z'
  workaround: true
  root_signature: 'report_yaml_format::general'
  resolved_by_cmd: ''
- cmd_id: cmd_modern_2
  timestamp: '2026-04-25T00:01:00Z'
  ninja: hanzo
  workaround: true
  category: report_yaml_format
  root_signature: 'report_yaml_format::general'
  detail: 'modern'
  root_cause: 'modern root cause'
  resolved_by_cmd: ''
YAML

    run bash "$TEST_SCRIPT" cmd_test_3 kotaro "third issue" "third root cause" report_yaml_format
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: カテゴリ「report_yaml_format」が3件"* ]]
}

@test "alert side effects can be disabled for isolated measurement" {
    cat > "$TEST_DIR/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_modern_1
  timestamp: '2026-04-25T00:00:00Z'
  ninja: hayate
  workaround: true
  category: report_yaml_format
  root_signature: 'report_yaml_format::general'
  detail: 'modern'
  root_cause: 'modern root cause'
  resolved_by_cmd: ''
- cmd_id: cmd_modern_2
  timestamp: '2026-04-25T00:01:00Z'
  ninja: hanzo
  workaround: true
  category: report_yaml_format
  root_signature: 'report_yaml_format::general'
  detail: 'modern'
  root_cause: 'modern root cause'
  resolved_by_cmd: ''
YAML

    run env KARO_WORKAROUND_DISABLE_ALERTS=true \
        bash "$TEST_SCRIPT" cmd_test_3 kotaro "third issue" "third root cause" report_yaml_format
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: カテゴリ「report_yaml_format」が3件"* ]]
    [ ! -f "$TEST_DIR/scripts/pending_decision_write.log" ]
}

@test "legacy key order: --reclassify updates category-first entry" {
    cat > "$TEST_DIR/logs/karo_workarounds.yaml" <<'YAML'
- category: report_yaml_format
  cmd_id: cmd_legacy_target
  detail: 'legacy'
  ninja: hayate
  root_cause: 'legacy root cause'
  timestamp: '2026-04-25T00:00:00Z'
  workaround: true
  resolved_by_cmd: ''
YAML

    run bash "$TEST_SCRIPT" --reclassify cmd_legacy_target verdict_override
    [ "$status" -eq 0 ]
    run grep -n "^- category: verdict_override$" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 0 ]
}

# =============================================
# AC2/AC3 (cmd_karo_hotfix_wa_root_signature_202607121225):
# root_signature auto-attach + N>=3 per-signature alerting
# =============================================

@test "AC2: workaround entry auto-attaches root_signature field" {
    run bash "$TEST_SCRIPT" cmd_test hayate "binary_checksが欠落しquote parseも壊れた" "report_field_set.shで補完" report_yaml_format
    [ "$status" -eq 0 ]
    run grep -n "root_signature: 'report_yaml_format::schema_shape'" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 0 ]
}

@test "AC3: 同一categoryでも異なるroot_signature 3件ではALERT/PDを発火しない" {
    run bash "$TEST_SCRIPT" cmd_1 hayate "report_path/ac_version欠落でYAML構文が壊れた" "task template修復" report_yaml_format
    [ "$status" -eq 0 ]
    [[ "$output" != *"ALERT"* ]]

    run bash "$TEST_SCRIPT" cmd_2 hayate "報告YAML未完了のままidle化して停滞した" "report_field_setで補完" report_yaml_format
    [ "$status" -eq 0 ]
    [[ "$output" != *"ALERT"* ]]

    run bash "$TEST_SCRIPT" cmd_3 hayate "command_files_modified_mismatchでcommit未完了のままBLOCK" "commit証跡を補正" report_yaml_format
    [ "$status" -eq 0 ]
    [[ "$output" != *"ALERT"* ]]
    [ ! -f "$TEST_DIR/scripts/pending_decision_write.log" ]
}

@test "AC3: 同一root_signatureが3件でのみALERT/PDを発火する" {
    run bash "$TEST_SCRIPT" cmd_1 hayate "binary_checksが欠落しquote parseも壊れた" "root_cause1" report_yaml_format
    [ "$status" -eq 0 ]
    [[ "$output" != *"ALERT"* ]]

    run bash "$TEST_SCRIPT" cmd_2 hayate "lessons_usefulが欠落しdict→list変換も壊れた" "root_cause2" report_yaml_format
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: 同一カテゴリ「report_yaml_format」が2件(root_signature=report_yaml_format::schema_shape)"* ]]

    run bash "$TEST_SCRIPT" cmd_3 hayate "knowledge_candidateが欠落しquote parseも壊れた" "root_cause3" report_yaml_format
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: カテゴリ「report_yaml_format」が3件(root_signature=report_yaml_format::schema_shape)"* ]]
    run grep -n "PD:" "$TEST_DIR/scripts/pending_decision_write.log"
    [ "$status" -eq 0 ]
}

@test "AC3: root_signature欠落のlegacy entryは新規の特定root_signatureカウントに混入しない" {
    cat > "$TEST_DIR/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_legacy_1
  timestamp: '2026-04-25T00:00:00Z'
  ninja: hayate
  workaround: true
  category: report_yaml_format
  detail: 'legacy issue without root_signature'
  root_cause: 'legacy root cause'
  resolved_by_cmd: ''
- cmd_id: cmd_legacy_2
  timestamp: '2026-04-25T00:01:00Z'
  ninja: hanzo
  workaround: true
  category: report_yaml_format
  detail: 'another legacy issue'
  root_cause: 'legacy root cause 2'
  resolved_by_cmd: ''
YAML

    run bash "$TEST_SCRIPT" cmd_new_1 hayate "binary_checksが欠落しquote parseも壊れた" "root_cause1" report_yaml_format
    [ "$status" -eq 0 ]
    [[ "$output" != *"ALERT"* ]]
    [[ "$output" != *"WARN: 同一カテゴリ"* ]]

    run bash "$TEST_SCRIPT" cmd_new_2 hayate "lessons_usefulが欠落しdict→list変換も壊れた" "root_cause2" report_yaml_format
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: 同一カテゴリ「report_yaml_format」が2件"* ]]
}

@test "AC3: root_signature欠落のlegacy entryは同根証拠がないためgeneral bucketへ混入しない" {
    cat > "$TEST_DIR/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_legacy_1
  timestamp: '2026-04-25T00:00:00Z'
  ninja: hayate
  workaround: true
  category: report_yaml_format
  detail: 'legacy issue without root_signature'
  root_cause: 'legacy root cause'
  resolved_by_cmd: ''
- cmd_id: cmd_legacy_2
  timestamp: '2026-04-25T00:01:00Z'
  ninja: hanzo
  workaround: true
  category: report_yaml_format
  detail: 'another legacy issue'
  root_cause: 'legacy root cause 2'
  resolved_by_cmd: ''
YAML

    run bash "$TEST_SCRIPT" cmd_new hayate "third generic issue" "third root cause" report_yaml_format
    [ "$status" -eq 0 ]
    [[ "$output" != *"ALERT"* ]]
    [[ "$output" != *"WARN: 同一カテゴリ"* ]]
}

@test "memory DB: workaround record also inserts event_type=workaround when DB exists" {
    db="$TEST_DIR/data/memory.db"
    mkdir -p "$TEST_DIR/data"
    python3 - "$db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
conn.execute(
    """
    CREATE TABLE events (
        id TEXT PRIMARY KEY,
        ts TEXT,
        event_type TEXT,
        agent TEXT,
        target TEXT,
        direction TEXT,
        summary TEXT,
        detail TEXT,
        session_id TEXT,
        cmd_id TEXT,
        concepts TEXT,
        source_file TEXT,
        parent_event_id INTEGER,
        importance TEXT
    )
    """
)
conn.execute("CREATE VIRTUAL TABLE events_fts USING fts5(summary, detail, content='events', content_rowid='rowid')")
conn.commit()
PY

    run env SHOGUN_MEMORY_DB="$db" \
        bash "$TEST_SCRIPT" cmd_test hayate "test issue for DB" "test root cause" report_yaml_format
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
row = conn.execute(
    "SELECT event_type, agent, target, direction, summary, cmd_id FROM events WHERE event_type='workaround'"
).fetchone()
print("|".join(row))
print(conn.execute("SELECT COUNT(*) FROM events_fts").fetchone()[0])
PY
)
    [ "${result[0]}" = "workaround|karo|hayate|report_yaml_format|test issue for DB|cmd_test" ]
    [ "${result[1]}" = "1" ]
}

@test "memory DB: live insert failure does not block workaround YAML recording" {
    mkdir -p "$TEST_DIR/data/not_a_db"

    run env SHOGUN_MEMORY_DB="$TEST_DIR/data/not_a_db" \
        bash "$TEST_SCRIPT" cmd_test hayate "test issue" "test root cause" report_yaml_format
    [ "$status" -eq 0 ]

    run grep -n "cmd_id: cmd_test" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 0 ]
}
