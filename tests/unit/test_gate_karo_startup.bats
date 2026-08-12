#!/usr/bin/env bats
# test_necessity: startup escalationの一案件一通知・terminal・再発generation契約を固定する。

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMPDIR_CASE="$(mktemp -d)"
  STATE="$TMPDIR_CASE/state.tsv"
  ALERTS="$TMPDIR_CASE/alerts.txt"
  PY="$TMPDIR_CASE/transition.py"
  sed -n '/^import os, re, sys, tempfile$/,/^os.replace(tmp, state_path)$/p' \
    "$ROOT/scripts/gates/gate_karo_startup.sh" > "$PY"
}

teardown() { rm -rf "$TMPDIR_CASE"; }

transition() { python3 "$PY" "$STATE" "$ALERTS" "${1:-}" "${2:-3600}"; }

@test "migration receipt duplicate is durable success while write failures remain blocked" {
  # test_necessity: 同一秒の並行startupが既存receiptを欠損と誤判定して起動をBLOCKしない契約を固定する。
  local source="$ROOT/scripts/gates/gate_karo_startup_migrated_checks.sh"
  run python3 - "$source" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
assert 'migration_write_rc=$?' in text
assert '"$migration_write_rc" -ne 0 && "$migration_write_rc" -ne 4' in text
assert 'BLOCK: defense_overhead receipt write failed' in text
PY
  [ "$status" -eq 0 ]
}

@test "同一keyは最初の一件だけ送信し可変率・件数・順序差を正規化する" {
  printf '%s\n' \
    '先送りCRITICAL: WA率 12.5% / 未処理 3件 が3セッション連続' \
    '先送りCRITICAL: WA率 99% / 未処理 88件 が4セッション連続' > "$ALERTS"
  run transition
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^SEND')" -eq 1 ]
  run transition
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(wc -l < "$STATE")" -eq 1 ]
}

@test "解決後の実再発は新generationとして一件だけ送信する" {
  echo '先送りCRITICAL: 未処理 3件 が3セッション連続' > "$ALERTS"
  run transition; [[ "$output" == *$'SEND\t未処理 #\t1\t'* ]]
  python3 - "$STATE" <<'PY'
from datetime import datetime, timedelta
from pathlib import Path
import sys

path = Path(sys.argv[1])
parts = path.read_text().rstrip('\n').split('\t')
parts[4] = (datetime.now().astimezone() - timedelta(hours=2)).isoformat(timespec='seconds')
path.write_text('\t'.join(parts) + '\n')
PY
  : > "$ALERTS"
  run transition; [ -z "$output" ]
  grep -q $'\t1\tresolved\t1\t' "$STATE"
  echo '先送りCRITICAL: 未処理 9件 が8セッション連続' > "$ALERTS"
  run transition; [[ "$output" == *$'SEND\t未処理 #\t2\t'* ]]
}

@test "同一keyの一時消失と復帰はgrace内で再送しない" {
  echo '先送りCRITICAL: 未処理 3件 が3セッション連続' > "$ALERTS"
  run transition; [[ "$output" == *$'SEND\t未処理 #\t1\t'* ]]
  : > "$ALERTS"
  run transition; [ -z "$output" ]
  grep -q $'\t1\topen\t1\t' "$STATE"
  echo '先送りCRITICAL: 未処理 9件 が8セッション連続' > "$ALERTS"
  run transition
  [ -z "$output" ]
  grep -q $'\t1\topen\t1\t' "$STATE"
}

@test "正当抑制はterminal suppressedを記録し通知しない" {
  echo '先送りCRITICAL: 閾値見直し対象 2件 が3セッション連続' > "$ALERTS"
  run transition '閾値見直し対象'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q $'\t1\tsuppressed\t0\t' "$STATE"
}

@test "同時startupはflock下で一件だけ送信する" {
  echo '先送りCRITICAL: 並行案件 7件 が3セッション連続' > "$ALERTS"
  LOCK="$TMPDIR_CASE/lock"
  (flock -x 9; python3 "$PY" "$STATE" "$ALERTS" '' 3600) 9>"$LOCK" > "$TMPDIR_CASE/out1" &
  p1=$!
  (flock -x 9; python3 "$PY" "$STATE" "$ALERTS" '' 3600) 9>"$LOCK" > "$TMPDIR_CASE/out2" &
  p2=$!
  wait "$p1"; wait "$p2"
  [ "$(cat "$TMPDIR_CASE/out1" "$TMPDIR_CASE/out2" | grep -c '^SEND')" -eq 1 ]
}

@test "破損stateはfail closedで上書きしない" {
  printf 'bad\tnot-an-int\topen\t0\tbefore\n' > "$STATE"
  cp "$STATE" "$TMPDIR_CASE/before"
  echo '先送りCRITICAL: 異常系 1件 が3セッション連続' > "$ALERTS"
  run transition
  [ "$status" -ne 0 ]
  cmp "$STATE" "$TMPDIR_CASE/before"
}

@test "実装は状態遷移と送信を同一flock区間に置く" {
  run awk '/_deferred_lock=.*karo_startup_escalation.lock/{seen=1} seen && /flock -x 9/{locked=1} locked && /inbox_write.sh.*shogun/{sent=1} END{exit !(seen&&locked&&sent)}' "$ROOT/scripts/gates/gate_karo_startup.sh"
  [ "$status" -eq 0 ]
}

# test_necessity: startup escalation must expose the Karo-lane corrective
# command receipt and never emit the former blame-shifting instruction.
@test "startup escalation is gated by non-zero corrective command evidence" {
  ! grep -q '家老が対処できないため将軍cmd起票を検討せよ' "$ROOT/scripts/gates/gate_karo_startup.sh"
  grep -q '試行コマンド:' "$ROOT/scripts/gates/gate_karo_startup.sh"
  grep -q 'exit_code:' "$ROOT/scripts/gates/gate_karo_startup.sh"
  grep -q '特定した不足:' "$ROOT/scripts/gates/gate_karo_startup.sh"
  grep -q '次の行動:' "$ROOT/scripts/gates/gate_karo_startup.sh"
  grep -q '実行者: karo' "$ROOT/scripts/gates/gate_karo_startup.sh"
  grep -q '\[ "\$_correction_rc" -ne 0 \] || continue' "$ROOT/scripts/gates/gate_karo_startup.sh"
}

@test "assigned CTX0はSTALL加算前にpane一次再照合しWorking中を除外する" {
  helper="$TMPDIR_CASE/pane-active.sh"
  sed -n '/^karo_startup_pane_is_active()/,/^}/p' \
    "$ROOT/scripts/gates/gate_karo_startup.sh" > "$helper"
  source "$helper"

  run karo_startup_pane_is_active '• Working (1m 2s • esc to interrupt)'
  [ "$status" -eq 0 ]
  run karo_startup_pane_is_active '› Run /review on my current changes'
  [ "$status" -ne 0 ]

  run awk '/_stall_pane_output=.*tmux capture-pane/{recapture=1} recapture && /karo_startup_pane_is_active/{active=1} recapture && /stall_count=\$\(\(stall_count \+ 1\)\)/{counted=1} END{exit !(recapture&&active&&counted)}' "$ROOT/scripts/gates/gate_karo_startup.sh"
  [ "$status" -eq 0 ]
}

@test "deepdive起動直後FAILは表示のみでstreak対象外" {
  helper="$TMPDIR_CASE/deepdive-grace.sh"
  sed -n '/^karo_startup_deepdive_replay_within_grace()/,/^}/p' \
    "$ROOT/scripts/gates/gate_karo_startup.sh" > "$helper"
  source "$helper"
  printf '%s\n' "$(date -d '5 minutes ago' '+%Y-%m-%dT%H:%M:%S%z')" > "$TMPDIR_CASE/marker"

  run env KARO_INBOX_UNREAD_DWELL_MIN=30 bash -c \
    'source "$1"; KARO_INBOX_UNREAD_DWELL_MIN="$2"; karo_startup_deepdive_replay_within_grace "$3" "$(date +%s)"' \
    _ "$helper" 30 "$TMPDIR_CASE/marker"
  [ "$status" -eq 0 ]
}

@test "deepdive滞留超過FAILはstreak対象にできる" {
  helper="$TMPDIR_CASE/deepdive-grace.sh"
  sed -n '/^karo_startup_deepdive_replay_within_grace()/,/^}/p' \
    "$ROOT/scripts/gates/gate_karo_startup.sh" > "$helper"
  source "$helper"
  printf '%s\n' "$(date -d '31 minutes ago' '+%Y-%m-%dT%H:%M:%S%z')" > "$TMPDIR_CASE/marker"

  run env KARO_INBOX_UNREAD_DWELL_MIN=30 bash -c \
    'source "$1"; KARO_INBOX_UNREAD_DWELL_MIN="$2"; karo_startup_deepdive_replay_within_grace "$3" "$(date +%s)"' \
    _ "$helper" 30 "$TMPDIR_CASE/marker"
  [ "$status" -ne 0 ]
}

@test "startup gate keeps failed unclosed visible and excludes formal FAIL close" {
  fixture="$TMPDIR_CASE/failed-unclosed"
  mkdir -p "$fixture/queue/tasks" "$fixture/queue/reports" "$fixture/queue/archive/reports" "$fixture/scripts/lib"
  cp "$ROOT/scripts/lib/report_terminal_state.sh" "$fixture/scripts/lib/"
  cp "$ROOT/scripts/lib/task_cmd_match.sh" "$fixture/scripts/lib/"
  awk '/^# --- Check 9.2:/{copy=1} /^# --- Check 9.3:/{copy=0} copy' \
    "$ROOT/scripts/gates/gate_karo_startup.sh" > "$fixture/check.sh"
  cat > "$fixture/queue/tasks/alpha.yaml" <<'YAML'
task:
  status: failed
  task_id: cmd_unclosed
  report_path: queue/reports/alpha_report_cmd_unclosed.yaml
YAML
  printf 'status: pending\nverdict: FAIL\n' > "$fixture/queue/reports/alpha_report_cmd_unclosed.yaml"
  run bash -c 'SCRIPT_DIR="$1"; _KARO_NINJA_NAMES=alpha; overall=OK; alerts=(); source "$1/scripts/lib/report_terminal_state.sh"; source "$1/scripts/lib/task_cmd_match.sh"; source "$1/check.sh"' _ "$fixture"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'ALERT: alpha failed_unclosed task=cmd_unclosed report_state=OPEN action=review_failed_task')" -eq 1 ]

  printf 'status: completed\nverdict: FAIL\nstatus_detail: BLOCKED\n' > "$fixture/queue/reports/alpha_report_cmd_unclosed.yaml"
  run bash -c 'SCRIPT_DIR="$1"; _KARO_NINJA_NAMES=alpha; overall=OK; alerts=(); source "$1/scripts/lib/report_terminal_state.sh"; source "$1/scripts/lib/task_cmd_match.sh"; source "$1/check.sh"' _ "$fixture"
  [ "$status" -eq 0 ]
  [[ "$output" == *'OK: failed_unclosed 0件'* ]]
}

# test_necessity: completed/pass task generations with a live report remain
# visible until the archive marker is paired with the ordered terminal tail.
@test "startup gate reports completed_unarchived once and clears after terminal archive" {
  fixture="$TMPDIR_CASE/completed-unarchived"
  mkdir -p "$fixture/queue/tasks" "$fixture/queue/reports" "$fixture/queue/gates/cmd_done" \
    "$fixture/scripts/lib"
  awk '/^# --- Check 9.2b:/{copy=1} /^# --- Check 9.3:/{copy=0} copy' \
    "$ROOT/scripts/gates/gate_karo_startup.sh" > "$fixture/check.sh"
  cat > "$fixture/queue/tasks/alpha.yaml" <<'YAML'
task:
  status: done
  task_id: task_done
  parent_cmd: cmd_done
YAML
  printf 'status: completed\nverdict: PASS\n' > "$fixture/queue/reports/alpha_report_cmd_done.yaml"

  run bash -c 'SCRIPT_DIR="$1"; _KARO_NINJA_NAMES=alpha; overall=OK; alerts=(); source "$1/check.sh"' _ "$fixture"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'ALERT: alpha completed_unarchived task=cmd_done')" -eq 1 ]

  : > "$fixture/queue/gates/cmd_done/archive.done"
  printf '%s\n' '[cmd_complete] COMPLETE cmd_done' > "$fixture/queue/gates/cmd_done/completion_tail.log"
  run bash -c 'SCRIPT_DIR="$1"; _KARO_NINJA_NAMES=alpha; overall=OK; alerts=(); source "$1/check.sh"' _ "$fixture"
  [ "$status" -eq 0 ]
  [[ "$output" == *'OK: completed_unarchived 0件'* ]]
}

# test_necessity: completed_unarchived is a mechanical archive transition owned
# by Karo; a successful archive must not become a Shogun escalation.
@test "startup gate auto-archives completed report and stays clear on success" {
  fixture="$TMPDIR_CASE/completed-unarchived-success"
  mkdir -p "$fixture/queue/tasks" "$fixture/queue/reports" "$fixture/queue/gates/cmd_auto" \
    "$fixture/scripts/lib" "$fixture/scripts"
  awk '/^# --- Check 9.2b:/{copy=1} /^# --- Check 9.3:/{copy=0} copy' \
    "$ROOT/scripts/gates/gate_karo_startup.sh" > "$fixture/check.sh"
  cat > "$fixture/queue/tasks/alpha.yaml" <<'YAML'
task:
  status: done
  task_id: task_auto
  parent_cmd: cmd_auto
YAML
  printf 'status: completed\nverdict: PASS\n' > "$fixture/queue/reports/alpha_report_cmd_auto.yaml"
  cat > "$fixture/scripts/archive_completed.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
touch "$ARCHIVE_COMPLETED_PROJECT_DIR/queue/gates/cmd_auto/archive.done"
EOF
  chmod +x "$fixture/scripts/archive_completed.sh"

  run env ARCHIVE_COMPLETED_PROJECT_DIR="$fixture" bash -c \
    'SCRIPT_DIR="$1"; _KARO_NINJA_NAMES=alpha; overall=OK; alerts=(); source "$1/check.sh"' \
    _ "$fixture"
  [ "$status" -eq 0 ]
  [[ "$output" == *'OK: alpha completed_unarchived task=cmd_auto auto_archived'* ]]
  [[ "$output" == *'OK: completed_unarchived 0件'* ]]
  [[ "$output" != *'ALERT: alpha completed_unarchived'* ]]
}

@test "startup gate excludes an older failed generation after same task_id reassignment" {
  fixture="$TMPDIR_CASE/failed-reassigned"
  mkdir -p "$fixture/queue/tasks" "$fixture/queue/reports" "$fixture/queue/archive/reports" "$fixture/scripts/lib"
  cp "$ROOT/scripts/lib/report_terminal_state.sh" "$fixture/scripts/lib/"
  cp "$ROOT/scripts/lib/task_cmd_match.sh" "$fixture/scripts/lib/"
  awk '/^# --- Check 9.2:/{copy=1} /^# --- Check 9.3:/{copy=0} copy' \
    "$ROOT/scripts/gates/gate_karo_startup.sh" > "$fixture/check.sh"
  cat > "$fixture/queue/tasks/alpha.yaml" <<'YAML'
task:
  status: failed
  task_id: cmd_reassigned_full
  parent_cmd: cmd_reassigned
  deployed_at: '2026-08-03T03:04:56'
  report_path: queue/reports/alpha_report_cmd_reassigned.yaml
YAML
  cat > "$fixture/queue/tasks/beta.yaml" <<'YAML'
task:
  status: in_progress
  task_id: cmd_reassigned_full
  parent_cmd: cmd_reassigned
  deployed_at: '2026-08-03T03:06:08'
  report_path: queue/reports/beta_report_cmd_reassigned.yaml
YAML
  run bash -c 'SCRIPT_DIR="$1"; _KARO_NINJA_NAMES="alpha beta"; overall=OK; alerts=(); source "$1/scripts/lib/report_terminal_state.sh"; source "$1/scripts/lib/task_cmd_match.sh"; source "$1/check.sh"' _ "$fixture"
  [ "$status" -eq 0 ]
  [[ "$output" == *'INFO: alpha failed task=cmd_reassigned_full は新しい同一task_id世代へ再配備済みのため未閉鎖対象外'* ]]
  [[ "$output" == *'OK: failed_unclosed 0件'* ]]
  [[ "$output" != *'ALERT: alpha failed_unclosed'* ]]
}

# test_necessity: review品質WARNを実装修正失敗と終端検証ギャップへ分解し、
# 同型4件を可視化しつつレビュー専用cmdと無関係な実装FAILを誤検知しない契約を固定する。
@test "review quality summary exposes terminal verification gaps without false positives" {
  fixture="$TMPDIR_CASE/review-quality"
  mkdir -p "$fixture"
  cat > "$fixture/review.yaml" <<'YAML'
- cmd_id: cmd_impl_prod_rerun
  review_type: report
  verdict: FAIL
  findings_summary: "production rerun未確認でFAIL"
- cmd_id: cmd_impl_preflight
  review_type: report
  verdict: FAIL
  findings_summary: "test_results: FAIL_PRECONDITION"
- cmd_id: cmd_impl_tests
  review_type: report
  verdict: FAIL
  findings_summary: "既存test未達、commit=no"
- cmd_id: cmd_impl_parity
  review_type: report
  verdict: FAIL
  findings_summary: "production parity検証未完了"
- cmd_id: cmd_impl_logic
  review_type: report
  verdict: FAIL
  findings_summary: "実装結果が期待値と不一致"
- cmd_id: cmd_recon2_review_only
  review_type: report
  verdict: FAIL
  findings_summary: "関連unit未達のreadonly偵察"
YAML
  : > "$fixture/status.yaml"
  : > "$fixture/metrics.log"

  # 修正前: 同じfixtureはWARN率だけを返し、終端ギャップ件数を可視化しない。
  run bash -c \
    'eval "$(git -C "$1" cat-file blob 0dc09272c7c0dbda79feef617f5394c6fa78ff98 | sed -n "/^review_quality_scale_summary()/,/^if .*GATE_KARO_STARTUP_LIB_ONLY/p" | head -n -1)"; review_quality_scale_summary "$2" 20 "$3" "$4"' \
    _ "$ROOT" "$fixture/review.yaml" "$fixture/status.yaml" "$fixture/metrics.log"
  [ "$status" -eq 0 ]
  [[ "$output" != *" 4 "* ]]

  run bash -c \
    'GATE_KARO_STARTUP_LIB_ONLY=1 source "$1/scripts/gates/gate_karo_startup.sh" >/dev/null; review_quality_scale_summary "$2" 20 "$3" "$4"' \
    _ "$ROOT" "$fixture/review.yaml" "$fixture/status.yaml" "$fixture/metrics.log"
  [ "$status" -eq 0 ]
  [[ "$output" == *" 4 "* ]]
  [[ "$output" == *"cmd_impl_preflight:FAIL"* ]]
  [[ "$output" == *"cmd_impl_parity:FAIL"* ]]
  [[ "$output" == *"cmd_impl_prod_rerun:FAIL"* ]]
  [[ "$output" == *"cmd_impl_tests:FAIL"* ]]
  [[ "$output" != *"cmd_impl_logic:FAIL"* ]]
  gap_output="${output#* 4 }"
  [[ "$gap_output" != *"cmd_recon2_review_only:FAIL"* ]]
}
