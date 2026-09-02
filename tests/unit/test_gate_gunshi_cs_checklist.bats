#!/usr/bin/env bats
# test_necessity: within a single gunshi_review_log.yaml entry that has a
# duplicate gate_result key, gate_gunshi_cs_checklist.sh's L6/L4b checks
# must resolve gate_result to the last-matching value in scan order (YAML
# last-key-wins semantics) — never latch on an earlier value regardless of
# whether CLEAR or BLOCK appears first; violation is a missed BLOCK
# detection (L6) or a false-positive contradiction WARN (L4b).
# cmd_karo_impl_b42_yaml_latch_and_dup_field_20260726 (B42, 疾風偵察
# cmd_karo_recon_cs_lgtm_block_attribution_20260726由来)

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_gunshi_cs_checklist.sh"
    [ -f "$GATE_SCRIPT" ] || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gate_gunshi_cs.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" "$TEST_TMPDIR/logs"
    # REPO_ROOT is derived from the script's own path (../..), so a sandbox
    # copy under TEST_TMPDIR/scripts/gates/ resolves LOG_FILE to
    # TEST_TMPDIR/logs/gunshi_review_log.yaml — fully isolated from the real log.
    cp "$GATE_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_gunshi_cs_checklist.sh"
    cp "$PROJECT_ROOT/scripts/gunshi_log_append.sh" "$TEST_TMPDIR/scripts/gunshi_log_append.sh"
    export LOG_UNDER_TEST="$TEST_TMPDIR/logs/gunshi_review_log.yaml"
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "B42陽性(見逃し側,合成データ): CLEAR→BLOCK順の重複gate_resultはL6(infra_no_verify)を正しく発火させる" {
    # 実データの6件重複キー(HEAD版logs/gunshi_review_log.yaml)は全てCLEAR→CLEARの
    # 同値重複であり、CLEAR→BLOCK順の実例は存在しない(家老・軍師と確認済み)。
    # よってこの陽性対照は合成データである(AC5の要求通り明記する)。
    cat > "$LOG_UNDER_TEST" <<'EOF'
- cmd_id: cmd_synth_miss
  review_type: report
  gate_result: CLEAR
  report_ninja: test
  verdict: LGTM
  observations:
    - scripts/deploy_task.sh looks fine, read only
  gate_result: BLOCK
  brainwash_check: "no numbers here at all"
  timestamp: "2026-07-26T00:00:00+09:00"
EOF
    run bash "$TEST_TMPDIR/scripts/gates/gate_gunshi_cs_checklist.sh"
    [[ "$output" == *"BLOCK(L6-洗脳#2)"* ]]
    [[ "$output" == *"cmd_synth_miss"* ]]
}

@test "B42陰性(誤検知側,実データcmd_4171): BLOCK→CLEAR順の重複gate_resultはL4b(LGTM+BLOCK矛盾)WARNを発火させない" {
    # logs/gunshi_review_log.yaml のHEAD版(git show HEAD)に実在するcmd_4171の
    # エントリ構造をそのまま使う(gate_result BLOCK→CLEARの順、verdict: LGTM、
    # 最終値はCLEARなので verdict=LGTM と矛盾しない)。合成ではなく実データ。
    cat > "$LOG_UNDER_TEST" <<'EOF'
- cmd_id: cmd_4171
  review_type: report
  gate_result: BLOCK
  gate_synced_at: 2026-07-25T15:26:42+09:00
  report_ninja: hayate
  verdict: LGTM
  verified_files:
    - "queue/reports/hayate_report_cmd_4171.yaml:28"
  gate_result: CLEAR
  gate_prediction: CLEAR
  gate_prediction_reason: "precheck all checks passed"
  finding_categories: [assumptions, numbers, simulation, premortem, adversarial, ambiguity]
  brainwash_check: "#1no #2no #3no #4no #5no #6no #7no #8no"
  origin: "[[a]] -> [[b]] -> [[c]]"
  timestamp: "2026-07-25T15:26:42+09:00"
EOF
    run bash "$TEST_TMPDIR/scripts/gates/gate_gunshi_cs_checklist.sh"
    [[ "$output" != *"WARN(L4b-洗脳#4)"* ]]
}

@test "L6 review entry解析は中間field挿入に依存せず既レビュー2件を除外し未レビュー1件だけ検知する" {
    mkdir -p "$TEST_TMPDIR/queue/inbox"
    cat > "$LOG_UNDER_TEST" <<'EOF'
- cmd_id: cmd_4177
  d0_applied: no
  review_type: report
  verdict: LGTM
- review_type: report
  reviewer_note: field order is intentionally different
  cmd_id: cmd_4178
  verdict: LGTM
EOF
    cat > "$TEST_TMPDIR/queue/inbox/gunshi.yaml" <<'EOF'
messages:
- id: reviewed-4177
  type: report_review
  content: "cmd_4177 の報告レビュー"
- id: reviewed-4178
  type: report_review
  content: "cmd_4178 の報告レビュー"
- id: missing-4199
  type: report_review
  content: "cmd_4199 の報告レビュー"
EOF

    run bash "$TEST_TMPDIR/scripts/gates/gate_gunshi_cs_checklist.sh"
    [[ "$output" == *"WARN(L6-洗脳#1)"* ]]
    [[ "$output" == *"cmd_4199"* ]]
    [[ "$output" != *"レビュー未実施: cmd_4177"* ]]
    [[ "$output" != *"レビュー未実施: cmd_4178"* ]]
}

# test_necessity: D0 detector must fail closed for an actionable unresolved
# defect even when d0_applied:no is present, while excluding negative counts
# and knowledge-only descriptions; only yes or structured remediation resolves.
@test "AC1-D0はnoで自己消火せず文脈FPを除外しyesと構造化remediationだけで解消する" {
    cat > "$LOG_UNDER_TEST" <<'EOF'
- cmd_id: cmd_true_positive
  review_type: report
  verdict: FAIL
  findings_summary: "post_verification_headフィールド欠落で再提出"
  d0_applied: no
  timestamp: "2026-07-28T00:00:00+09:00"
- cmd_id: cmd_negative_count
  review_type: report
  verdict: LGTM
  observations:
    - "self_sync観測5項目欠落0"
  d0_applied: no
  timestamp: "2026-07-28T00:01:00+09:00"
- cmd_id: cmd_knowledge_only
  review_type: draft
  verdict: APPROVE
  observations:
    - "枝選択コンテキスト欠落の具体知見"
  d0_applied: no
  timestamp: "2026-07-28T00:02:00+09:00"
- cmd_id: cmd_aggregate_measurement
  review_type: draft
  verdict: REQUEST_CHANGES
  observations:
    - "hole_action欠落5件を計測し、d0_applied 4→3と確認"
  d0_applied: no
  timestamp: "2026-07-28T00:02:30+09:00"
- cmd_id: cmd_yes_resolved
  review_type: report
  verdict: FAIL
  findings_summary: "required field missing"
  d0_applied: yes
  timestamp: "2026-07-28T00:03:00+09:00"
- remediation:
    target_cmd_id: cmd_structured_resolved
    fields:
      d0_applied: yes
    evidence:
      - "queue/reports/worker_report.yaml:42"
  review_type: self_study
  timestamp: "2026-07-28T00:05:00+09:00"
- cmd_id: cmd_structured_resolved
  review_type: report
  verdict: FAIL
  findings_summary: "required field missing"
  d0_applied: no
  timestamp: "2026-07-28T00:04:00+09:00"
EOF

    run bash "$TEST_TMPDIR/scripts/gates/gate_gunshi_cs_checklist.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(AC1-D0未実施): 1件"* ]]
    [[ "$output" == *"cmd_true_positive"* ]]
    [[ "$output" != *"cmd_negative_count: 軽微修正"* ]]
    [[ "$output" != *"cmd_knowledge_only: 軽微修正"* ]]
    [[ "$output" != *"cmd_aggregate_measurement: 軽微修正"* ]]
    [[ "$output" != *"cmd_yes_resolved: 軽微修正"* ]]
    [[ "$output" != *"cmd_structured_resolved: 軽微修正"* ]]
}

# test_necessity: duplicate cmd_id reviews must be remediated by stable review
# identity so one historical finding can never waive its siblings.
@test "append-only remediationは重複cmdをreview_type+reviewed_atでexact 1件だけ解消する" {
    cat > "$LOG_UNDER_TEST" <<'EOF'
- cmd_id: cmd_dup
  review_type: draft
  verdict: REQUEST_CHANGES
  reviewed_at: "2026-08-01T00:01:00+09:00"
  ambiguity_points: none
  brainwash_check: "8/8"
- cmd_id: cmd_dup
  review_type: draft
  verdict: REQUEST_CHANGES
  reviewed_at: "2026-08-01T00:02:00+09:00"
  ambiguity_points: none
  brainwash_check: "8/8"
- cmd_id: cmd_dup
  review_type: draft
  verdict: REQUEST_CHANGES
  reviewed_at: "2026-08-01T00:03:00+09:00"
  ambiguity_points: none
  brainwash_check: "8/8"
- cmd_id: cmd_dup
  review_type: draft
  verdict: REQUEST_CHANGES
  reviewed_at: "2026-08-01T00:04:00+09:00"
  ambiguity_points: none
  brainwash_check: "8/8"
- remediation:
    target_cmd_id: cmd_dup
    target_review_type: draft
    target_reviewed_at: "2026-08-01T00:01:00+09:00"
    fields: {hole_action: d0_implemented}
    evidence: ["queue/reports/evidence.yaml:42"]
  review_type: self_study
EOF
    run bash "$TEST_TMPDIR/scripts/gates/gate_gunshi_cs_checklist.sh"
    [[ "$output" == *"3件のREQUEST_CHANGESにhole_action未記入"* ]]
    [[ "$output" == *"cmd_dup|draft|2026-08-01T00:02:00+09:00"* ]]
    [[ "$output" != *"cmd_dup|draft|2026-08-01T00:01:00+09:00: hole_action"* ]]

    sed -i '/target_review_type:/d; /target_reviewed_at:/d' "$LOG_UNDER_TEST"
    run bash "$TEST_TMPDIR/scripts/gates/gate_gunshi_cs_checklist.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(remediation): invalid structured remediation"* ]]

    cat > "$TEST_TMPDIR/stable_remediation.yaml" <<'EOF'
- cmd_id: remediation_probe
  review_type: self_study
  remediation:
    target_cmd_id: cmd_dup
    target_review_type: draft
    target_reviewed_at: "2026-08-01T00:01:00+09:00"
    fields: {hole_action: d0_implemented}
    evidence: ["queue/reports/evidence.yaml:42"]
  observations:
    - "target exact 1/1"
  cs_checklist: {CS1: one, CS2: two, CS3: three, CS4: four, CS5: five, CS6: six}
  causal_chain: "a -> b -> c"
  operational_simulation: {command: probe, expected: exact, actual: exact, result: PASS}
  brainwash_check: "#1no #2no #3no #4no #5no #6no #7no #8no; 1/1"
EOF
    GUNSHI_VALIDATE_ONLY=1 run bash "$TEST_TMPDIR/scripts/gunshi_log_append.sh" < "$TEST_TMPDIR/stable_remediation.yaml"
    [ "$status" -eq 0 ]

    sed -i '/target_review_type:/d; /target_reviewed_at:/d' "$TEST_TMPDIR/stable_remediation.yaml"
    GUNSHI_VALIDATE_ONLY=1 run bash "$TEST_TMPDIR/scripts/gunshi_log_append.sh" < "$TEST_TMPDIR/stable_remediation.yaml"
    [ "$status" -eq 2 ]
    [[ "$output" == *"invalid remediation target"* ]]
}

# test_necessity: archived review generations and terminal tombstones are the
# durable identity boundary after active-log compaction.
@test "remediationはarchive generationを解決し曖昧・staleをBLOCKしterminal tombstoneへ収束する" {
    mkdir -p "$TEST_TMPDIR/logs/archive"
    cat > "$TEST_TMPDIR/logs/archive/gunshi_review_log_gen1.yaml" <<'EOF'
- cmd_id: cmd_archived
  review_type: draft
  reviewed_at: "2026-08-01T00:01:00+09:00"
  verdict: REQUEST_CHANGES
  hole_action: no
EOF
    cat > "$LOG_UNDER_TEST" <<'EOF'
- cmd_id: remediation_archived
  review_type: self_study
  remediation:
    target_cmd_id: cmd_archived
    target_review_type: draft
    target_reviewed_at: "2026-08-01T00:01:00+09:00"
    target_generation: gunshi_review_log_gen1.yaml
    fields: {hole_action: d0_implemented}
    evidence: ["queue/reports/evidence.yaml:42"]
EOF
    run bash "$TEST_TMPDIR/scripts/gates/gate_gunshi_cs_checklist.sh"
    [[ "$output" != *"BLOCK(remediation)"* ]]

    sed -i 's/gunshi_review_log_gen1.yaml/gunshi_review_log_stale.yaml/' "$LOG_UNDER_TEST"
    run bash "$TEST_TMPDIR/scripts/gates/gate_gunshi_cs_checklist.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(remediation)"* ]]

    cat >> "$LOG_UNDER_TEST" <<'EOF'
- cmd_id: tombstone_archived
  review_type: self_study
  terminal_tombstone:
    target_remediation_cmd_id: remediation_archived
    reason: stale generation is terminal
    evidence: ["logs/archive/gunshi_review_log_gen1.yaml:1"]
EOF
    run bash "$TEST_TMPDIR/scripts/gates/gate_gunshi_cs_checklist.sh"
    [[ "$output" != *"BLOCK(remediation)"* ]]
}

# test_necessity: concurrent gate readers must never observe the partial state
# between append and archive publication of one review-log generation.
@test "append archiveとgate同時実行はgeneration lockでpartial readとlost updateを0にする" {
    mkdir -p "$TEST_TMPDIR/logs/archive"
    cat > "$LOG_UNDER_TEST" <<'EOF'
- cmd_id: cmd_base
  review_type: self_study
  observations:
    - "base"
  cs_checklist: {CS1: one, CS2: two, CS3: three, CS4: four, CS5: five, CS6: six}
  causal_chain: "a -> b -> c"
  operational_simulation: {command: probe, expected: pass, actual: pass, result: PASS}
  brainwash_check: "#1no #2no #3no #4no #5no #6no #7no #8no; 1/1"
EOF
    for i in $(seq 1 20); do
        (bash "$TEST_TMPDIR/scripts/gates/gate_gunshi_cs_checklist.sh" >"$TEST_TMPDIR/gate.$i" 2>&1) &
        pids="$pids $!"
    done
    for i in $(seq 1 10); do
        GUNSHI_VALIDATE_ONLY=0 bash "$TEST_TMPDIR/scripts/gunshi_log_append.sh" <<EOF &
- cmd_id: cmd_append_$i
  review_type: self_study
  observations:
    - "append $i"
  cs_checklist: {CS1: one, CS2: two, CS3: three, CS4: four, CS5: five, CS6: six}
  causal_chain: "a -> b -> c"
  operational_simulation: {command: probe, expected: pass, actual: pass, result: PASS}
  brainwash_check: "#1no #2no #3no #4no #5no #6no #7no #8no; 1/1"
EOF
        pids="$pids $!"
    done
    for pid in $pids; do wait "$pid"; done
    run python3 - "$LOG_UNDER_TEST" <<'PY'
import sys,yaml
x=yaml.safe_load(open(sys.argv[1]))
assert isinstance(x,list)
assert len([v for v in x if isinstance(v,dict) and str(v.get('cmd_id','')).startswith('cmd_append_')]) == 10
PY
    [ "$status" -eq 0 ]
    run grep -l 'Traceback\|YAML parse\|partial' "$TEST_TMPDIR"/gate.*
    [ "$status" -eq 1 ]
}

# test_necessity: The review-log append entrypoint must be discoverable without
# stdin input, must never block on a human terminal, and must preserve the
# existing piped-entry append path.
@test "gunshi_log_append help and tty stdin fail closed while pipe remains supported" {
    local script_under_test="$TEST_TMPDIR/scripts/gunshi_log_append.sh"

    run bash "$script_under_test" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]

    run timeout 5 script -qec "bash '$script_under_test'" /dev/null
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage:"* ]]

    run bash "$script_under_test" <<'EOF'
- cmd_id: cmd_pipe_contract
  review_type: self_study
  observations:
    - "piped input reaches the existing validator"
  cs_checklist: {CS1: one, CS2: two, CS3: three, CS4: four, CS5: five, CS6: six}
  causal_chain: "a -> b -> c"
  operational_simulation: {command: probe, expected: pass, actual: pass, result: PASS}
  brainwash_check: "#1no #2no #3no #4no #5no #6no #7no #8no; 1/1"
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"Appended"* || "$output" == *"appended"* ]]
}
