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
