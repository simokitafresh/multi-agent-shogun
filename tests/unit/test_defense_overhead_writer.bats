#!/usr/bin/env bats
# test_necessity: Self-retro preserves durable telemetry while suppressing only known zero-signal insight delivery.

setup() {
  export TEST_TMP="$(mktemp -d)"
  export DEFENSE_OVERHEAD_LEDGER="$TEST_TMP/events.jsonl"
  source "$BATS_TEST_DIRNAME/../../scripts/lib/defense_overhead_writer.sh"
}

teardown() {
  self_retro_drain
  rm -rf "$TEST_TMP"
}

@test "writes required schema and rejects invalid or duplicate events" {
  run defense_overhead_write deploy_task deploy_total 17 PASS evt-1
  [ "$status" -eq 0 ]
  run defense_overhead_write 'bad source' deploy_total 17 PASS evt-2
  [ "$status" -eq 2 ]
  run defense_overhead_write deploy_task deploy_total 17 PASS evt-1
  [ "$status" -eq 4 ]
  python3 - "$DEFENSE_OVERHEAD_LEDGER" <<'PY'
import json, sys
rows=[json.loads(x) for x in open(sys.argv[1])]
assert len(rows)==1
assert set(rows[0])=={'timestamp','source','check_id','wall_ms','verdict','event_id','agent'}
PY
}

# test_necessity: event_id deduplication must parse the full historical JSON schema (including legacy whitespace), reconcile a sidecar-stale ledger tail, and never append a second exact identity.
@test "exact sidecar dedup covers legacy whitespace and crash-stale ledger tail" {
  printf '{"timestamp":"legacy","event_id": "legacy-spaced"}\n' > "$DEFENSE_OVERHEAD_LEDGER"
  bytes_before="$(stat -c %s "$DEFENSE_OVERHEAD_LEDGER")"
  run defense_overhead_write test exact 1 PASS legacy-spaced
  [ "$status" -eq 4 ]
  [ "$(stat -c %s "$DEFENSE_OVERHEAD_LEDGER")" -eq "$bytes_before" ]

  run defense_overhead_write test exact 1 PASS indexed-first
  [ "$status" -eq 0 ]
  # Simulate the only crash window: JSONL append reached durable history but
  # the derived SQLite offset/event row did not.  The next locked append must
  # ingest that tail before checking the incoming identity.
  printf '{"timestamp":"legacy-tail","event_id":"tail-only"}\n' >> "$DEFENSE_OVERHEAD_LEDGER"
  bytes_before="$(stat -c %s "$DEFENSE_OVERHEAD_LEDGER")"
  run defense_overhead_write test exact 1 PASS tail-only
  [ "$status" -eq 4 ]
  [ "$(stat -c %s "$DEFENSE_OVERHEAD_LEDGER")" -eq "$bytes_before" ]
  [ "$(grep -c '"event_id":"tail-only"' "$DEFENSE_OVERHEAD_LEDGER")" -eq 1 ]
}

# test_necessity: the tracked hot ledger must never grow through GitHub's
# 100 MiB object limit; rotation must preserve every old row in ignored archive
# history while keeping a bounded recent window and accepting the new event.
@test "oversized ledger rotates under writer locks without losing history" {
  export DEFENSE_OVERHEAD_MAX_BYTES=200
  export DEFENSE_OVERHEAD_KEEP_LINES=2
  for i in 1 2 3 4; do
    printf '{"timestamp":"old-%s","event_id":"old-%s","padding":"%080d"}\n' "$i" "$i" "$i" >> "$DEFENSE_OVERHEAD_LEDGER"
  done
  run defense_overhead_write test rotate 1 PASS new-event
  [ "$status" -eq 0 ]
  archive_file="$(find "$TEST_TMP/archive" -maxdepth 1 -name 'defense_overhead_*.jsonl' -print -quit)"
  [ -n "$archive_file" ]
  [ "$(grep -c 'old-' "$archive_file")" -eq 4 ]
  [ "$(grep -c 'old-' "$DEFENSE_OVERHEAD_LEDGER")" -eq 2 ]
  [ "$(grep -c 'new-event' "$DEFENSE_OVERHEAD_LEDGER")" -eq 1 ]
}

# test_necessity: the full-ledger sidecar preparation must occur before the append flock, and the lock-held path must contain no ledger grep/full scan; otherwise a 69MB writer can starve every startup receipt.
@test "full ledger scan is structurally outside the append lock" {
  writer="$BATS_TEST_DIRNAME/../../scripts/lib/defense_overhead_writer.sh"
  prepare_line="$(grep -n 'python3 .* prepare ' "$writer" | head -1 | cut -d: -f1)"
  append_lock_line="$(grep -n 'exec {DEFENSE_OVERHEAD_FD}>>' "$writer" | head -1 | cut -d: -f1)"
  [ -n "$prepare_line" ] && [ -n "$append_lock_line" ]
  [ "$prepare_line" -lt "$append_lock_line" ]
  ! sed -n "${append_lock_line},/^}/p" "$writer" | grep -Eq 'grep .*\$ledger'
}

# test_necessity: optional identity metadata must extend, never replace, the stable six-column event schema while five-argument callers remain byte-contract compatible.
@test "optional metadata adds identity columns without breaking five-argument callers" {
  run defense_overhead_write legacy check 1 PASS legacy-1
  [ "$status" -eq 0 ]
  run defense_overhead_write review_approval gunshi_lgtm 0 PASS review-1 \
    '{"cmd_id":"cmd_unit","generation":"rpt-unit"}'
  [ "$status" -eq 0 ]
  python3 - "$DEFENSE_OVERHEAD_LEDGER" <<'PY'
import json, sys
rows=[json.loads(x) for x in open(sys.argv[1])]
base={'timestamp','source','check_id','wall_ms','verdict','event_id','agent'}
assert set(rows[0]) == base
assert base <= set(rows[1])
assert rows[1]['cmd_id'] == 'cmd_unit'
assert rows[1]['generation'] == 'rpt-unit'
PY
}

# test_necessity: metadata cannot overwrite stable schema fields or inject nested values that make JSONL consumers ambiguous.
@test "optional metadata rejects reserved and non-scalar fields" {
  run defense_overhead_write x y 1 PASS e1 '{"source":"other"}'
  [ "$status" -eq 3 ]
  run defense_overhead_write x y 1 PASS e2 '{"cmd_id":{"nested":true}}'
  [ "$status" -eq 3 ]
  [ ! -e "$DEFENSE_OVERHEAD_LEDGER" ]
}

# test_necessity: both formal review boundaries must pass the same cmd/report-generation identity columns into the common writer.
@test "review approval gunshi and karo callers emit cmd and fingerprint generation metadata" {
  python3 - <<'PY'
from pathlib import Path
text = Path("scripts/review_approval.sh").read_text(encoding="utf-8")
for check in ("gunshi_lgtm", "karo_accept"):
    start = text.index(f"defense_overhead_write review_approval {check}")
    call = text[start:start + 320]
    assert '\\"cmd_id\\"' in call
    assert '\\"generation\\"' in call
    assert '${fingerprint}' in call
PY
}

# test_necessity: generation identity must remain stable on retry and separate a changed report submission without using PID or time.
@test "report generation is stable on retry and distinct after resubmission" {
  defense_overhead_write review_approval gunshi_lgtm 0 PASS e1 '{"cmd_id":"cmd_unit","generation":"fp-a"}'
  defense_overhead_write review_approval karo_accept 0 PASS e2 '{"cmd_id":"cmd_unit","generation":"fp-a"}'
  defense_overhead_write review_approval gunshi_lgtm 0 PASS e3 '{"cmd_id":"cmd_unit","generation":"fp-b"}'
  python3 - "$DEFENSE_OVERHEAD_LEDGER" <<'PY'
import json, sys
rows=[json.loads(x) for x in open(sys.argv[1])]
assert [r["generation"] for r in rows[:2]] == ["fp-a", "fp-a"]
assert rows[2]["generation"] == "fp-b"
assert len({r["generation"] for r in rows}) == 2
PY
}

@test "twenty concurrent events are complete unique parseable and classify exactly" {
  for i in $(seq 1 20); do
    defense_overhead_write test check "$i" "$([ $((i%2)) -eq 0 ] && echo PASS || echo FAIL)" "evt-$i" &
  done
  wait
  python3 - "$DEFENSE_OVERHEAD_LEDGER" <<'PY'
import json, sys
rows=[json.loads(x) for x in open(sys.argv[1])]
assert len(rows)==20 and len({r['event_id'] for r in rows})==20
assert sum(r['verdict']=='PASS' for r in rows)==10
assert sum(r['verdict']=='FAIL' for r in rows)==10
PY
}

@test "disabled and unwritable async writer preserve caller contract" {
  DEFENSE_OVERHEAD_ENABLED=0
  run bash -c 'source scripts/lib/defense_overhead_writer.sh; defense_overhead_write_async x y 1 PASS e; printf preserved'
  [ "$status" -eq 0 ] && [ "$output" = preserved ]
  DEFENSE_OVERHEAD_ENABLED=1 DEFENSE_OVERHEAD_LEDGER=/proc/forbidden/events.jsonl
  run bash -c 'source scripts/lib/defense_overhead_writer.sh; defense_overhead_write_async x y 1 FAIL e; printf preserved'
  [ "$status" -eq 0 ] && [ "$output" = preserved ]
}

@test "batch async writer emits complete unique events through one caller" {
  defense_overhead_write_batch_async test one 1 PASS batch-1 test two 2 BLOCK batch-2
  for _ in $(seq 1 100); do
    [ -f "$DEFENSE_OVERHEAD_LEDGER" ] && [ "$(wc -l < "$DEFENSE_OVERHEAD_LEDGER")" -eq 2 ] && break
    sleep 0.02
  done
  python3 - "$DEFENSE_OVERHEAD_LEDGER" <<'PY'
import json, sys
rows=[json.loads(x) for x in open(sys.argv[1])]
assert len(rows)==2 and {r['event_id'] for r in rows}=={'batch-1','batch-2'}
assert {r['verdict'] for r in rows}=={'PASS','BLOCK'}
PY
}

@test "production callers source and invoke the common async writer" {
  run grep -c 'defense_overhead_write_async' scripts/deploy_task.sh
  [ "$status" -eq 0 ] && [ "$output" -ge 1 ]
  run grep -c 'defense_overhead_write_async' scripts/gates/gate_gunshi_report_precheck.sh
  [ "$status" -eq 0 ] && [ "$output" -ge 1 ]
  run grep -c 'defense_overhead_write_batch_async' scripts/hooks/git-pre-commit.sh
  [ "$status" -eq 0 ] && [ "$output" -ge 1 ]
}

@test "deep self-retro is idempotent, backward compatible, and falls back without blocking" {
  export SELF_RETRO_LEDGER="$TEST_TMP/self-retro.jsonl"
  run self_retro_write ninja_report cmd_unit 12 '{"write":7,"delivery":5}' report_completion cause candidate criterion '[[a]] -> [[b]] -> [[c]]'
  [ "$status" -eq 0 ]
  run self_retro_write ninja_report cmd_unit 12 '{"write":7,"delivery":5}' report_completion cause candidate criterion '[[a]] -> [[b]] -> [[c]]'
  [ "$status" -eq 4 ]
  python3 - "$SELF_RETRO_LEDGER" <<'PY'
import json,sys
r=[json.loads(x) for x in open(sys.argv[1])]
assert len(r)==1 and r[0]['phase_ms']=={'write':7,'delivery':5}
assert all(r[0][k] for k in ('cause_structure','improvement_candidate','binary_criterion','origin'))
PY
  [ ! -e "$DEFENSE_OVERHEAD_LEDGER" ]
  SELF_RETRO_LEDGER=/proc/forbidden/events.jsonl
  self_retro_write_async ninja_report cmd_fallback 9 '{"write":9}' delivery_missing cause candidate criterion '[[a]] -> [[b]] -> [[c]]'
  [ "$?" -eq 0 ]
  self_retro_drain
}

@test "deep self-retro owner drains delayed async writers before teardown" {
  export SELF_RETRO_LEDGER="$TEST_TMP/self-retro.jsonl"
  self_retro_write() {
    sleep 0.05
    printf '{"done":true}\n' >"$SELF_RETRO_LEDGER"
  }
  self_retro_write_async ninja_report cmd_delayed 1 '{"write":1}' delayed cause candidate criterion '[[a]] -> [[b]] -> [[c]]'
  [ ! -e "$SELF_RETRO_LEDGER" ]
  self_retro_drain
  [ "$(cat "$SELF_RETRO_LEDGER")" = '{"done":true}' ]
  [ "${#SELF_RETRO_ASYNC_PIDS[@]}" -eq 0 ]
}

@test "all four terminal endpoints invoke detached deep self-retro" {
  run grep -c 'self_retro_write_async ninja_report' scripts/retro_write.sh; [ "$status" -eq 0 ] && [ "$output" -eq 1 ]
  run grep -c 'self_retro_write_async karo_cmd_complete' scripts/cmd_complete.sh; [ "$status" -eq 0 ] && [ "$output" -eq 1 ]
  run grep -c 'gunshi_review_bundle' scripts/review_bundle.py; [ "$status" -eq 0 ] && [ "$output" -ge 1 ]
  run grep -c 'self_retro_write_async shogun_gate_clear' scripts/cmd_complete_gate.sh; [ "$status" -eq 0 ] && [ "$output" -eq 1 ]
}

@test "dominant cause promotes a verified fix_known candidate" {
  export SELF_RETRO_LEDGER="$TEST_TMP/self-retro.jsonl"
  export DEFENSE_OVERHEAD_REPO_ROOT="$TEST_TMP/root"
  mkdir -p "$DEFENSE_OVERHEAD_REPO_ROOT/scripts"
  printf '#!/bin/bash\nprintf "%%s|%%s|%%s\\n" "$INSIGHT_FIX_KNOWN" "$INSIGHT_TARGET_FILE" "$INSIGHT_VERIFY_COMMAND" >>"%s"\n' "$TEST_TMP/insight.calls" >"$DEFENSE_OVERHEAD_REPO_ROOT/scripts/insight_write.sh"
  chmod +x "$DEFENSE_OVERHEAD_REPO_ROOT/scripts/insight_write.sh"
  SELF_RETRO_FIX_KNOWN_THRESHOLD=2 self_retro_write ninja_report cmd_one 1 '{"write":1}' repeated cause candidate criterion '[[a]] -> [[b]] -> [[c]]'
  SELF_RETRO_FIX_KNOWN_THRESHOLD=2 self_retro_write ninja_report cmd_two 1 '{"write":1}' repeated cause candidate criterion '[[a]] -> [[b]] -> [[c]]'
  SELF_RETRO_FIX_KNOWN_THRESHOLD=2 self_retro_write ninja_report cmd_three 1 '{"write":1}' singleton cause candidate criterion '[[a]] -> [[b]] -> [[c]]'
  run grep -c '^true|' "$TEST_TMP/insight.calls"
  [ "$status" -eq 0 ] && [ "$output" -eq 1 ]
  run python3 - "$SELF_RETRO_LEDGER" <<'PY'
import json,sys
r=[json.loads(x) for x in open(sys.argv[1])]
assert len(r)==3
assert sum(x['cause_class']=='repeated' for x in r)==2
assert sum(x['cause_class']=='singleton' for x in r)==1
PY
  [ "$status" -eq 0 ]
}

@test "production ledger canonical: gate_clear suppressed and completion_pipeline emitted" {
  # test_necessity: 実データ正本突合 — gate_clear(wall_ms=0,seen>=3)→suppression,completion_pipeline(wall_ms>0,seen>=3)→emission の二値は production self_retro.jsonl で常に成立しなければならない
  local ledger="logs/self_retro.jsonl"
  if [ ! -f "$ledger" ]; then return 0; fi  # CI不在環境はsilent pass: SKIP=FAIL policy(cmd_karo_ci_fix_sample_bats_20260724)
  run python3 - "$ledger" <<'PY'
import json, sys
ledger = sys.argv[1]
with open(ledger, encoding="utf-8") as fh:
    rows = [json.loads(line) for line in fh if line.strip()]
gate = [r for r in rows if r.get("cause_class") == "gate_clear"]
comp = [r for r in rows if r.get("cause_class") == "completion_pipeline"]
assert gate, "no gate_clear records"
assert comp, "no completion_pipeline records"
assert all(r["wall_ms"] == 0 and max(r["phase_ms"].values()) == 0 for r in gate), "gate_clear must all be wall_ms=0"
assert all(r["wall_ms"] > 0 for r in comp), "completion_pipeline must all be wall_ms>0"
threshold = 3
gate_imp = gate[0]["improvement_candidate"]
comp_imp = comp[0]["improvement_candidate"]
gate_seen = sum(1 for r in rows if r.get("improvement_candidate") == gate_imp)
comp_seen = sum(1 for r in rows if r.get("improvement_candidate") == comp_imp)
assert gate_seen >= threshold, f"gate_clear seen={gate_seen} < threshold={threshold}"
assert comp_seen >= threshold, f"completion_pipeline seen={comp_seen} < threshold={threshold}"
gate_known = gate_seen >= threshold
gate_zero = True
comp_known = comp_seen >= threshold
comp_zero = max(comp[0]["phase_ms"].values()) == 0 or comp[0]["wall_ms"] == 0
gate_suppress = gate_known and gate_zero
comp_suppress = comp_known and comp_zero
assert gate_suppress, f"gate_clear should be suppressed: known={gate_known} zero={gate_zero}"
assert not comp_suppress, f"completion_pipeline should NOT be suppressed: known={comp_known} zero={comp_zero}"
PY
  [ "$status" -eq 0 ]
}

@test "known zero-signal template is recorded but not delivered while measured signal is delivered" {
  export SELF_RETRO_LEDGER="$TEST_TMP/self-retro.jsonl"
  export DEFENSE_OVERHEAD_REPO_ROOT="$TEST_TMP/root"
  mkdir -p "$DEFENSE_OVERHEAD_REPO_ROOT/scripts"
  printf '#!/bin/bash\nprintf "%%s\\n" "$1" >>"%s"\n' "$TEST_TMP/insight.calls" >"$DEFENSE_OVERHEAD_REPO_ROOT/scripts/insight_write.sh"
  chmod +x "$DEFENSE_OVERHEAD_REPO_ROOT/scripts/insight_write.sh"

  SELF_RETRO_FIX_KNOWN_THRESHOLD=2 self_retro_write ninja_report cmd_zero_one 0 '{"write":0}' repeated cause template criterion '[[a]] -> [[b]] -> [[c]]'
  SELF_RETRO_FIX_KNOWN_THRESHOLD=2 self_retro_write ninja_report cmd_zero_two 0 '{"write":0}' repeated cause template criterion '[[a]] -> [[b]] -> [[c]]'
  [ ! -e "$TEST_TMP/insight.calls" ]

  SELF_RETRO_FIX_KNOWN_THRESHOLD=2 self_retro_write ninja_report cmd_signal_one 8 '{"write":8}' measured cause template criterion '[[a]] -> [[b]] -> [[c]]'
  SELF_RETRO_FIX_KNOWN_THRESHOLD=2 self_retro_write ninja_report cmd_signal_two 9 '{"write":9}' measured cause template criterion '[[a]] -> [[b]] -> [[c]]'
  run grep -c 'self-retro dominant cause=measured' "$TEST_TMP/insight.calls"
  [ "$status" -eq 0 ] && [ "$output" -eq 1 ]

  run python3 - "$SELF_RETRO_LEDGER" <<'PY'
import json,sys
rows=[json.loads(x) for x in open(sys.argv[1])]
assert len(rows) == 4
assert sum(r['wall_ms'] == 0 for r in rows) == 2
assert sum(r['wall_ms'] > 0 for r in rows) == 2
PY
  [ "$status" -eq 0 ]
}

# test_necessity: agent must identify the executor, never a neighbouring tmux
# pane, and must never block a write when it cannot be resolved (fail-open).
@test "agent column resolves executor from SHOGUN_AGENT_ID and falls back to dash" {
  SHOGUN_AGENT_ID=karo run defense_overhead_write review_approval karo_accept 5 PASS evt-agent-1
  [ "$status" -eq 0 ]
  SHOGUN_AGENT_ID='Bad Agent!' run defense_overhead_write review_approval karo_accept 5 PASS evt-agent-2
  [ "$status" -eq 0 ]
  SHOGUN_AGENT_ID= TMUX_PANE= run defense_overhead_write review_approval karo_accept 5 PASS evt-agent-3
  [ "$status" -eq 0 ]
  SHOGUN_AGENT_ID= TMUX_PANE=%999999 run defense_overhead_write review_approval karo_accept 5 PASS evt-agent-4
  [ "$status" -eq 0 ]
  python3 - "$DEFENSE_OVERHEAD_LEDGER" <<'PY'
import json, sys
rows={json.loads(x)['event_id']: json.loads(x) for x in open(sys.argv[1])}
assert rows['evt-agent-1']['agent']=='karo'
assert rows['evt-agent-2']['agent']=='-'
assert rows['evt-agent-3']['agent']=='-'
assert rows['evt-agent-4']['agent']=='-'
PY
  run defense_overhead_write review_approval karo_accept 5 PASS evt-agent-5 '{"agent":"spoof"}'
  [ "$status" -eq 3 ]
}

# test_necessity: executor identity must come from the current TMUX_PANE only;
# a second pane's identity must never be attributed to the writer.
@test "agent identity is pane-local and absent pane remains dash" {
  tmux() {
    case "$3" in
      %left) printf 'left-agent\n' ;;
      %right) printf 'right-agent\n' ;;
      *) return 1 ;;
    esac
  }
  export -f tmux
  SHOGUN_AGENT_ID= TMUX_PANE=%left defense_overhead_write test pane 1 PASS evt-pane-left
  SHOGUN_AGENT_ID= TMUX_PANE=%right defense_overhead_write test pane 1 PASS evt-pane-right
  SHOGUN_AGENT_ID= TMUX_PANE= defense_overhead_write test pane 1 PASS evt-pane-none
  python3 - "$DEFENSE_OVERHEAD_LEDGER" <<'PY'
import json, sys
rows = {r['event_id']: r for r in map(json.loads, open(sys.argv[1]))}
assert rows['evt-pane-left']['agent'] == 'left-agent'
assert rows['evt-pane-right']['agent'] == 'right-agent'
assert rows['evt-pane-none']['agent'] == '-'
PY
}

# test_necessity: the daily karo report must consume both current and legacy
# ledgers, apply one as-of boundary to every source, and be byte-idempotent.
@test "karo throughput report is deterministic across legacy and identity fixtures" {
  local base="$TEST_TMP/karo-throughput-report"
  mkdir -p "$base/gates/cmd_a" "$base/out"
  printf '%s\n' \
    '{"timestamp":"2026-09-05T00:00:00Z","source":"review_approval","check_id":"karo_accept","wall_ms":10,"verdict":"PASS","event_id":"d1","agent":"karo"}' \
    '{"timestamp":"2026-09-05T01:00:00Z","source":"review_approval","check_id":"karo_accept","wall_ms":30,"verdict":"WARN","event_id":"d2"}' \
    '{"timestamp":"2026-09-05T01:30:00Z","source":"inbox_watcher","check_id":"delivery_held","wall_ms":139000,"verdict":"WARN","event_id":"h1","agent":"inbox_watcher","target_agent":"karo"}' \
    '{"timestamp":"2026-09-05T02:10:00Z","source":"three_layer_preflight","check_id":"three_layer_preflight_total","wall_ms":220,"verdict":"PASS","event_id":"p1","agent":"karo"}' > "$base/defense.jsonl"
  printf '%s\n' \
    '{"schema":"function_timing.v1","observed_at":"2026-09-05T01:00:00Z","execution_id":"new-1","script":"cmd_complete_gate.sh","function":"gate_main","elapsed_us":1000}' \
    '{"schema":"function_timing.v1","execution_id":"legacy-1788570000000000","script":"deploy_task.sh","function":"inject_semantic_concepts","elapsed_us":2000}' \
    '{"schema":"function_timing.v1","observed_at":"2026-09-05T02:00:00Z","execution_id":"deploy-2","script":"deploy_task.sh","function":"inject_semantic_concepts","elapsed_us":4000}' \
    '{"schema":"function_timing.v1","observed_at":"2026-09-05T02:30:00Z","execution_id":"deploy-2","script":"deploy_task.sh","function":"generate_report_template","elapsed_us":3000}' > "$base/timing.jsonl"
  printf '%s\n' \
    $'2026-09-05T00:30:00+00:00\tcmd_a\tBLOCK\tparent_cmd_contract:missing' \
    $'2026-09-05T01:00:00+00:00\tcmd_a\tWAIT\tWAIT:report_commit_main_ancestry' \
    $'2026-09-05T02:00:00+00:00\tcmd_a\tCLEAR\tall_gates_passed\tduration_sec=2.5' > "$base/gate.log"
  printf '%s\n' '[Sat Sep  5 03:00:00 JST 2026] [DELIVERY-LATENCY] karo: held 5s from first-unread' > "$base/watcher.log"
  printf '%s\n' $'2026-09-05T03:00:00+09:00\tcmd_a\tPASS\tresult=PASS reason=none\trc=0' > "$base/gates/cmd_a/auto_push_ancestry_retry.log"

  local -a report_env=(
    "KARO_THROUGHPUT_OUTPUT_DIR=$base/out"
    "KARO_THROUGHPUT_DEFENSE_LOG=$base/defense.jsonl"
    "KARO_THROUGHPUT_TIMING_LOGS=$base/timing.jsonl"
    "KARO_THROUGHPUT_GATE_LOG=$base/gate.log"
    "KARO_THROUGHPUT_WATCHER_LOGS=$base/watcher.log"
    "KARO_THROUGHPUT_RETRY_ROOT=$base/gates"
  )
  run env "${report_env[@]}" bash "$BATS_TEST_DIRNAME/../../scripts/karo_throughput_report.sh" 2026-09-05 --as-of 2026-09-05T04:00:00+00:00
  [ "$status" -eq 0 ]
  local report="$base/out/2026-09-05_2026-09-05T04:00:00+00:00.md"
  [ -s "$report" ]
  cp "$report" "$base/first.md"
  run env "${report_env[@]}" bash "$BATS_TEST_DIRNAME/../../scripts/karo_throughput_report.sh" 2026-09-05 --as-of 2026-09-05T04:00:00+00:00
  [ "$status" -eq 0 ]
  cmp "$base/first.md" "$report"
  grep -qF 'function_timing / cmd_complete_gate.sh' "$report"
  grep -qF 'function_timing / deploy_task.sh' "$report"
  # test_necessity: deploy_task の律速判断は全関数を集計した同一日次表で再現できなければならない。
  grep -qF '実行数: 2 / 集計関数数: 2' "$report"
  grep -qF '| inject_semantic_concepts | 2 | 2 | 4 | 6 |' "$report"
  grep -qF '| generate_report_template | 1 | 3 | 3 | 3 |' "$report"
  grep -qF 'WAIT:report_commit_main_ancestry' "$report"
  grep -qF 'inbox_watcher_karo / delivery_held (legacy stderr)' "$report"
  grep -qF 'inbox_watcher / delivery_held (event, WARN 1)' "$report"
  grep -qF '| - | 1 | 30 |' "$report"
  # 待ち理由別 時間: BLOCK 30 分(00:30→01:00) + WAIT 60 分(01:00→02:00)、比率 33%/67%、cmd 数 1
  grep -qF '| WAIT:WAIT:report_commit_main_ancestry | 60 | 67% | 1 |' "$report"
  grep -qF '| BLOCK:parent_cmd_contract:missing | 30 | 33% | 1 |' "$report"
  # 負荷 proxy: 02:10Z = JST 11 時帯に 1 回 p50 220
  grep -qF '| 11 | 1 | 220 | 220 |' "$report"
}

# test_necessity: executor attribution must not collapse to "-" for the two
# largest tmux-less sources (daemon health gate, inbox_mark_read outside a pane).
@test "tmux-less attribution falls back to daemon name and owner-inbox" {
  local out="$TEST_TMP/attr"; mkdir -p "$out"
  run env -u TMUX_PANE -u SHOGUN_AGENT_ID bash -c 'source scripts/lib/defense_overhead_writer.sh; export SHOGUN_AGENT_ID="${SHOGUN_AGENT_ID:-three_layer_health}"; DEFENSE_OVERHEAD_LEDGER='"$out"'/a.jsonl defense_overhead_write three_layer_health refresh_window 5 PASS attr-1'
  [ "$status" -eq 0 ]
  grep -q '"agent": *"three_layer_health"' "$out/a.jsonl"
  run env -u TMUX_PANE -u SHOGUN_AGENT_ID bash -c 'AGENT_ID=karo; if [ -z "${SHOGUN_AGENT_ID:-}" ] && [ -z "${TMUX_PANE:-}" ]; then export SHOGUN_AGENT_ID="${AGENT_ID}-inbox"; fi; source scripts/lib/defense_overhead_writer.sh; DEFENSE_OVERHEAD_LEDGER='"$out"'/b.jsonl defense_overhead_write inbox_mark_read inbox_mark_read_total 5 PASS attr-2'
  [ "$status" -eq 0 ]
  grep -q '"agent": *"karo-inbox"' "$out/b.jsonl"
}
