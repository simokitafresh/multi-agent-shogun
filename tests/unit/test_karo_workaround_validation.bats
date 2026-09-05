#!/usr/bin/env bats
# test_necessity: karo workaround ledger must atomically and idempotently resolve exact entries, reject workaround=true/category=clean before write, fail closed on blank/conflicting resolution and missing brainwash evidence, trigger root-signature immunity at N=3, and preserve primary logging when memory DB is unavailable.
# test_karo_workaround_validation.bats — cmd_1542 + cmd_karo_env_change_gate 単体テスト
# AC1: validate_ninja_id() — ninja_id有効性チェック
# AC2: root_cause最小長+null/empty拒否

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../scripts" && pwd)/karo_workaround_log.sh"

setup_file() {
    # Cache immutable production inputs once per file.  Copying them from the
    # /mnt/c worktree in every test is disproportionately expensive on WSL2.
    export SHARED_INPUTS="$BATS_FILE_TMPDIR/karo-workaround-inputs"
    mkdir -p "$SHARED_INPUTS/lib"
    cp "$SCRIPT" "$SHARED_INPUTS/karo_workaround_log.sh"
    cp "$(dirname "$SCRIPT")/lib/known_ninjas.sh" "$SHARED_INPUTS/lib/known_ninjas.sh"
    cp "$(dirname "$SCRIPT")/memory_db_live_insert.py" "$SHARED_INPUTS/memory_db_live_insert.py"
}

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
echo "PD_DEDUP_KEY:${PD_DEDUP_KEY:-}" >> "${BASH_SOURCE[0]%.sh}.log"
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
    cp "$SHARED_INPUTS/karo_workaround_log.sh" "$TEST_DIR/scripts/karo_workaround_log.sh"
    cp "$SHARED_INPUTS/lib/known_ninjas.sh" "$TEST_DIR/scripts/lib/known_ninjas.sh"
    cp "$SHARED_INPUTS/memory_db_live_insert.py" "$TEST_DIR/scripts/memory_db_live_insert.py"
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

@test "resolve mode atomically closes one exact entry and is idempotent" {
    log="$TEST_DIR/logs/karo_workarounds.yaml"
    cat > "$log" <<'YAML'
- cmd_id: cmd_target
  ninja: hayate
  workaround: true
  missed_sg: operational_simulation_missing
  resolved_by_cmd: ''
- cmd_id: cmd_other
  ninja: hanzo
  workaround: true
  missed_sg: operational_simulation_missing
  resolved_by_cmd: ''
YAML

    run bash "$TEST_SCRIPT" --resolve cmd_target shared_upstream_defence
    [ "$status" -eq 0 ]
    [[ "$output" == *"updated=1"* ]]
    run python3 - "$log" <<'PY'
import sys, yaml
rows = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
assert rows[0]["resolved_by_cmd"] == "shared_upstream_defence"
assert rows[1]["resolved_by_cmd"] == ""
PY
    [ "$status" -eq 0 ]

    run bash "$TEST_SCRIPT" --resolve cmd_target shared_upstream_defence
    [ "$status" -eq 0 ]
    [[ "$output" == *"unchanged=1"* ]]
}

@test "resolve mode rejects whitespace resolution and conflicting overwrite" {
    log="$TEST_DIR/logs/karo_workarounds.yaml"
    cat > "$log" <<'YAML'
- cmd_id: cmd_target
  ninja: hayate
  workaround: true
  missed_sg: operational_simulation_missing
  resolved_by_cmd: existing_defence
YAML

    run bash "$TEST_SCRIPT" --resolve cmd_target "   "
    [ "$status" -ne 0 ]
    run bash "$TEST_SCRIPT" --resolve cmd_target different_defence
    [ "$status" -ne 0 ]
    grep -q "resolved_by_cmd: existing_defence" "$log"
}

@test "event schema backfill adds manual defaults to every legacy entry" {
    cat > "$TEST_DIR/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_legacy_1
  workaround: true
  category: report_yaml_format
- cmd_id: cmd_legacy_2
  workaround: false
  category: clean
YAML
    run bash "$TEST_SCRIPT" --backfill-event-fields
    [ "$status" -eq 0 ]
    [[ "$output" == *"entries=2 backfilled=2"* ]]
    run grep -c '^  event_kind: manual_wa$' "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 0 ]
    [ "$output" -eq 2 ]
    run grep -c '^  auto_captured: false$' "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 0 ]
    [ "$output" -eq 2 ]
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

@test "explicit clean category in normal and --wa modes blocks before write" {
    log="$TEST_DIR/logs/karo_workarounds.yaml"
    before=0
    if [ -f "$log" ]; then
        before=$(awk '/^- cmd_id:/{count++} END{print count+0}' "$log")
    fi

    run bash "$TEST_SCRIPT" cmd_test_1 hayate "normal detail" "normal root cause" clean
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK: category=cleanは--cleanモード専用"* ]]
    [[ "$output" == *"--clean cmd_test_1 hayate"* ]]

    run bash "$TEST_SCRIPT" --wa cmd_test_2 hayate "normal detail" "normal root cause" clean "" \
        "type=gate; file=scripts/sample_gate.sh; pattern=ENV_CHANGE_MARKER"
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK: category=cleanは--cleanモード専用"* ]]
    [[ "$output" == *"--clean cmd_test_2 hayate"* ]]

    after=0
    if [ -f "$log" ]; then
        after=$(awk '/^- cmd_id:/{count++} END{print count+0}' "$log")
    fi
    [ "$before" -eq "$after" ]
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
  root_signature: 'report_yaml_format::schema_shape'
  resolved_by_cmd: ''
- cmd_id: cmd_modern_2
  timestamp: '2026-04-25T00:01:00Z'
  ninja: hanzo
  workaround: true
  category: report_yaml_format
  root_signature: 'report_yaml_format::schema_shape'
  detail: 'modern'
  root_cause: 'modern root cause'
  resolved_by_cmd: ''
YAML

    run bash "$TEST_SCRIPT" cmd_test_3 kotaro "third binary_checks issue" "third root cause" report_yaml_format
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
  root_signature: 'report_yaml_format::schema_shape'
  detail: 'modern'
  root_cause: 'modern root cause'
  resolved_by_cmd: ''
- cmd_id: cmd_modern_2
  timestamp: '2026-04-25T00:01:00Z'
  ninja: hanzo
  workaround: true
  category: report_yaml_format
  root_signature: 'report_yaml_format::schema_shape'
  detail: 'modern'
  root_cause: 'modern root cause'
  resolved_by_cmd: ''
YAML

    run env KARO_WORKAROUND_DISABLE_ALERTS=true \
        bash "$TEST_SCRIPT" cmd_test_3 kotaro "third binary_checks issue" "third root cause" report_yaml_format
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

@test "--reclassify updates root_signature family atomically and preserves suffix" {
    cat > "$TEST_DIR/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_target
  ninja: hayate
  workaround: true
  category: report_yaml_format
  root_signature: 'report_yaml_format::schema_shape'
  detail: 'first distinct issue'
  root_cause: 'first root cause'
  resolved_by_cmd: ''
- cmd_id: cmd_target
  ninja: hayate
  workaround: true
  category: uncategorized
  root_signature: 'uncategorized::general'
  detail: 'second distinct issue'
  root_cause: 'second root cause'
  resolved_by_cmd: ''
YAML

    run bash "$TEST_SCRIPT" --reclassify '^cmd_target$' report_yaml_format
    [ "$status" -eq 0 ]
    run grep -c '^  category: report_yaml_format$' "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 0 ]
    [ "$output" -eq 2 ]
    run grep -c "root_signature: 'report_yaml_format::schema_shape'" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
    run grep -c "root_signature: 'report_yaml_format::general'" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
    run grep -c "root_signature: 'uncategorized::" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 1 ]
    [ "$output" -eq 0 ]
}

@test "--reclassify can set an evidence-based root_signature explicitly" {
    cat > "$TEST_DIR/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_variation
  ninja: hayate
  workaround: true
  category: uncategorized
  root_signature: 'uncategorized::general'
  detail: 'variation_checksが空で報告証跡なし'
  root_cause: '5セルをexact yesへ正規化'
  resolved_by_cmd: ''
YAML

    run bash "$TEST_SCRIPT" --reclassify '^cmd_variation$' report_yaml_format report_yaml_format::verification_evidence
    [ "$status" -eq 0 ]
    run grep -n "root_signature: 'report_yaml_format::verification_evidence'" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 0 ]
}

@test "--reclassify detail filter updates only the matching same-cmd entry and inserts missing signature" {
    cat > "$TEST_DIR/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_same
  category: uncategorized
  detail: 'staging広域差分が混入'
  root_cause: 'scope限定commitへ修正'
- cmd_id: cmd_same
  category: report_yaml_format
  root_signature: 'report_yaml_format::schema_shape'
  detail: 'commit_hash欠落'
  root_cause: 'commit証跡を補正'
YAML

    run bash "$TEST_SCRIPT" --reclassify '^cmd_same$' commit_scope_contamination \
        commit_scope_contamination::commit_provenance 'staging広域差分'
    [ "$status" -eq 0 ]
    run grep -c "root_signature: 'commit_scope_contamination::commit_provenance'" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
    run grep -c "root_signature: 'report_yaml_format::schema_shape'" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

@test "variation_checks and report evidence classify canonically" {
    run bash "$TEST_SCRIPT" cmd_variation hayate \
        "FAIL報告variation_checksが空、報告証跡も未実施扱い" \
        "5セルをexact yesへ正規化"
    [ "$status" -eq 0 ]
    run grep -n '^  category: report_yaml_format$' "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 0 ]
    run grep -n "root_signature: 'report_yaml_format::verification_evidence'" "$TEST_DIR/logs/karo_workarounds.yaml"
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

# test_necessity: every manual WA must publish its lesson-reflux decision in
# the same canonical append; otherwise a clear/new can erase the learning
# before the startup gate notices the daily count mismatch.
@test "manual WA atomically records lesson reflux decision" {
    export KARO_WA_LESSON_REQUIRED=true
    export KARO_WA_LESSON_REFERENCE=LK-A11

    run bash "$TEST_SCRIPT" cmd_lesson_reflux hanzo \
        "task contract contradicted the required output" \
        "integrated the contract rule into the existing lesson" \
        task_design_precondition none
    [ "$status" -eq 0 ]
    run python3 - "$TEST_DIR/logs/karo_workarounds.yaml" <<'PY'
import sys, yaml
rows = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
row = next(item for item in rows if item.get("cmd_id") == "cmd_lesson_reflux")
assert row["lesson_required"] is True
assert row["lesson_reference"] == "LK-A11"
PY
    [ "$status" -eq 0 ]
}

# test_necessity: a legacy ledger backfill must fail closed on an unmapped
# manual signature and publish a complete, machine-countable disposition for
# both manual WAs and automatic observations.
@test "reflux backfill closes every mapped cluster and rejects unmapped clusters" {
    cat > "$TEST_DIR/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_auto
  ninja: system
  workaround: false
  category: rework_auto_capture
  resolved_by_cmd: ''
- cmd_id: cmd_manual
  ninja: hanzo
  workaround: true
  category: task_design_precondition
  root_signature: 'task_design_precondition::general'
  resolved_by_cmd: ''
YAML

    run env KARO_WORKAROUND_LOG_FILE="$TEST_DIR/logs/karo_workarounds.yaml" \
        KARO_WORKAROUND_LOCK_FILE="$TEST_DIR/logs/karo_workarounds.lock" \
        bash "$TEST_SCRIPT" --backfill-reflux cmd_reflux \
        'report_yaml_format::general=L311'
    [ "$status" -ne 0 ]
    [[ "$output" == *"no lesson mapping for task_design_precondition::general"* ]]
    [ "$(grep -c "^  resolved_by_cmd: ''$" "$TEST_DIR/logs/karo_workarounds.yaml")" -eq 2 ]

    run env KARO_WORKAROUND_LOG_FILE="$TEST_DIR/logs/karo_workarounds.yaml" \
        KARO_WORKAROUND_LOCK_FILE="$TEST_DIR/logs/karo_workarounds.lock" \
        bash "$TEST_SCRIPT" --backfill-reflux cmd_reflux \
        'task_design_precondition::general=LK-A11'
    [ "$status" -eq 0 ]
    [[ "$output" == *"updated=2 not_applicable=1 integrated_existing=1"* ]]
    run python3 - "$TEST_DIR/logs/karo_workarounds.yaml" <<'PY'
import sys, yaml
rows = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
assert sum(not row.get("resolved_by_cmd") for row in rows) == 0
assert rows[0]["lesson_disposition"] == "not_applicable"
assert rows[0]["resolved_by_cmd"] == "cmd_auto"
assert rows[1]["lesson_disposition"] == "integrated_existing"
assert rows[1]["lesson_reference"] == "LK-A11"
assert rows[1]["resolved_by_cmd"] == "cmd_reflux"
PY
    [ "$status" -eq 0 ]
}

# test_necessity: reflux completion must replace legacy placeholder values in
# the same atomic publication as resolved_by_cmd, while preserving explicit
# not_applicable rows and remaining idempotent after the first publication.
@test "reflux backfill replaces placeholders, inserts missing fields, preserves not_applicable, and is idempotent" {
    cat > "$TEST_DIR/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: cmd_placeholder
  workaround: true
  category: deploy_task_ac
  root_signature: 'deploy_task_ac::general'
  lesson_disposition: new_lesson_required
  lesson_reference: ''
  resolved_by_cmd: 'cmd_placeholder'
- cmd_id: cmd_missing
  workaround: true
  category: deploy_task_ac
  root_signature: 'deploy_task_ac::general'
  resolved_by_cmd: ''
- cmd_id: cmd_not_applicable
  workaround: false
  category: rework_auto_capture
  lesson_disposition: not_applicable
  lesson_reference: 'not_applicable'
  resolved_by_cmd: ''
YAML

    run env KARO_WORKAROUND_LOG_FILE="$TEST_DIR/logs/karo_workarounds.yaml" \
        KARO_WORKAROUND_LOCK_FILE="$TEST_DIR/logs/karo_workarounds.lock" \
        bash "$TEST_SCRIPT" --backfill-reflux cmd_reflux \
        'deploy_task_ac::general=LK-A13'
    [ "$status" -eq 0 ]
    [[ "$output" == *"updated=3 not_applicable=1 integrated_existing=2"* ]]

    run python3 - "$TEST_DIR/logs/karo_workarounds.yaml" <<'PY'
import sys, yaml
rows = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
assert [(row["lesson_disposition"], row["lesson_reference"], row["resolved_by_cmd"]) for row in rows] == [
    ("integrated_existing", "LK-A13", "cmd_reflux"),
    ("integrated_existing", "LK-A13", "cmd_reflux"),
    ("not_applicable", "not_applicable", "cmd_not_applicable"),
]
PY
    [ "$status" -eq 0 ]

    first_hash="$(sha256sum "$TEST_DIR/logs/karo_workarounds.yaml" | awk '{print $1}')"
    run env KARO_WORKAROUND_LOG_FILE="$TEST_DIR/logs/karo_workarounds.yaml" \
        KARO_WORKAROUND_LOCK_FILE="$TEST_DIR/logs/karo_workarounds.lock" \
        bash "$TEST_SCRIPT" --backfill-reflux cmd_reflux \
        'deploy_task_ac::general=LK-A13'
    [ "$status" -eq 0 ]
    [[ "$output" == *"updated=0 not_applicable=0 integrated_existing=0"* ]]
    [ "$(sha256sum "$TEST_DIR/logs/karo_workarounds.yaml" | awk '{print $1}')" = "$first_hash" ]
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

@test "AC2: 現存general履歴11件を構造signatureへ全量分離する" {
    local -a categories=(
        gate_logic_gap gate_logic_gap gate_logic_gap gate_logic_gap
        gate_logic_gap gate_logic_gap gate_logic_gap gate_logic_gap
        deploy_contract deploy_contract deploy_contract
    )
    local -a issues=(
        "normalize_report.shのexit2を握り潰し未正規化completed公開を許した"
        "quality contractがflow-style投影を評価せずaction/fp missing"
        "report_receivedがuncommitted gateでBLOCKし後続integrator commit確認が必要"
        "merge中にninja_scope_commitがpartial commit不可で停止"
        "非lock OperationalErrorもlock deadlineへ誤変換した"
        "SQL readonly・credential allowlist・backup dry-run restore境界を拒否"
        "direct taskの辞書型ACを品質契約射影がcommand以外で評価しない"
        "completed報告への追記helper BLOCK後も複合shellが続行し時期尚早な再レビュー依頼"
        "karo_direct配備YAMLの自然境界契約とestimated_minutesが不足"
        "cmdにestimated_minutesと長時間契約構造がない"
        "QUALITY_CONTRACT投影が複数行commandのaction/fpを評価しない"
    )
    local -a expected=(
        error_handling contract_projection commit_provenance merge_hook
        exception_taxonomy safety_boundary contract_projection operator_orchestration
        natural_boundary natural_boundary contract_projection
    )

    local i
    for i in "${!issues[@]}"; do
        run bash "$TEST_SCRIPT" "cmd_fixture_$i" hayate "${issues[$i]}" "fixture root cause" "${categories[$i]}"
        [ "$status" -eq 0 ]
        run grep -F "root_signature: '${categories[$i]}::${expected[$i]}'" "$TEST_DIR/logs/karo_workarounds.yaml"
        [ "$status" -eq 0 ]
    done

    run grep -c "root_signature: '.*::general'" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 1 ]
    [ "$output" -eq 0 ]
}

@test "AC2: 構造的に同根のcontract projection 3件はWARNからALERTへ到達する" {
    run bash "$TEST_SCRIPT" cmd_projection_1 hayate "quality contractのflow-style投影でaction/fp missing" "root cause 1" gate_logic_gap
    [ "$status" -eq 0 ]
    [[ "$output" != *"ALERT"* ]]

    run bash "$TEST_SCRIPT" cmd_projection_2 hayate "辞書型ACを品質契約射影がcommand以外で評価しない" "root cause 2" gate_logic_gap
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: 同一カテゴリ「gate_logic_gap」が2件(root_signature=gate_logic_gap::contract_projection)"* ]]

    run bash "$TEST_SCRIPT" cmd_projection_3 hayate "QUALITY_CONTRACT投影が複数行commandのaction/fpを評価しない" "root cause 3" gate_logic_gap
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: カテゴリ「gate_logic_gap」が3件(root_signature=gate_logic_gap::contract_projection)"* ]]
}

# test_necessity: PD-141's four historical infra mechanisms must never share
# the general bucket; the exact signature is the production alert aggregation
# key and therefore must remain mechanism-specific.
@test "AC1: PD-141 four infra mechanisms do not collapse into infra::general" {
    local -a issues=(
        "main checkoutのindex残渣と旧 blobをread-treeで復元"
        "gate_worker.failed.json残存後にgate再起動せずfallback BLOCK"
        "top-level file AGENTS.mdのfiles_modified path契約とmanifest厳密一致が矛盾"
        "docs-only taskのreceipt必須とowned path契約がnested guardで衝突"
    )
    local -a signatures=(
        worktree_index_sync gate_lifecycle_restart path_contract receipt_contract
    )
    local i
    for i in "${!issues[@]}"; do
        run bash "$TEST_SCRIPT" "cmd_pd141_fixture_$i" hayate "${issues[$i]}" "構造的な機構修正を適用" infra
        [ "$status" -eq 0 ]
        run grep -F "root_signature: 'infra::${signatures[$i]}'" "$TEST_DIR/logs/karo_workarounds.yaml"
        [ "$status" -eq 0 ]
    done

    run grep -c "root_signature: 'infra::general'" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 1 ]
    [ "$output" -eq 0 ]
}

@test "AC2: unknown mechanism uses distinct evidence signature, never general" {
    run bash "$TEST_SCRIPT" cmd_unknown_a hayate "opaque mechanism alpha" "alpha mechanism repair" infra
    [ "$status" -eq 0 ]
    run bash "$TEST_SCRIPT" cmd_unknown_b hayate "opaque mechanism beta" "beta mechanism repair" infra
    [ "$status" -eq 0 ]
    run grep -E "root_signature: 'infra::evidence_[0-9a-f]{16}'" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 0 ]
    run grep -c "root_signature: 'infra::general'" "$TEST_DIR/logs/karo_workarounds.yaml"
    [ "$status" -eq 1 ]
    [ "$output" -eq 0 ]
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

# test_necessity: ALERT時のPD起票は同一root_signatureをdedup keyとして渡す（重複PD増殖の禁止）。
@test "ALERT passes PD_DEDUP_KEY so repeated same-signature workarounds aggregate into one PD" {
    run bash "$TEST_SCRIPT" cmd_d1 hayate "binary_checksが欠落しquote parseも壊れた" "rc1" report_yaml_format
    [ "$status" -eq 0 ]
    run bash "$TEST_SCRIPT" cmd_d2 hayate "lessons_usefulが欠落しdict→list変換も壊れた" "rc2" report_yaml_format
    [ "$status" -eq 0 ]
    run bash "$TEST_SCRIPT" cmd_d3 hayate "knowledge_candidateが欠落しquote parseも壊れた" "rc3" report_yaml_format
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT"* ]]

    run grep -c "^PD_DEDUP_KEY:wa_escalation:report_yaml_format::report_yaml_format::schema_shape$" \
        "$TEST_DIR/scripts/pending_decision_write.log"
    [ "$output" -eq 1 ]
}
