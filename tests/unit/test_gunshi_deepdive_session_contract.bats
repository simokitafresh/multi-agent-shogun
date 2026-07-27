#!/usr/bin/env bats
# test_necessity: compactionで同一セッションのdeepdive receiptを失効させず、
# fresh sessionの未完了時は軍師startup gateが非0で通常レビューを開始できない契約を守る。

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  FIX="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$FIX/scripts/gates" "$FIX/memory" "$FIX/logs/deepdive_replay"
  cp "$REPO_ROOT/scripts/gates/gate_deepdive_replay.sh" "$FIX/scripts/gates/"
  cp "$REPO_ROOT/memory/deepdive_why_chain_20260321.md" "$FIX/memory/"
}

@test "session marker is renewed only for startup or clear, never resume or compact" {
  run python3 - "$REPO_ROOT/scripts/hooks/session_start_inject.sh" <<'PY'
import pathlib, re, sys
s = pathlib.Path(sys.argv[1]).read_text()
block = s[s.index("# --- deepdive追体験セッションマーカー"):s.index("# --- Timestamp")]
assert 'source_type" == "startup"' in block
assert 'source_type" == "clear"' in block
assert 'source_type" == "resume"' not in block
assert 'source_type" == "compact"' not in block
assert block.count('.session"') == 1
PY
  [ "$status" -eq 0 ]
}

@test "gunshi startup gate converts incomplete deepdive receipt to process BLOCK" {
  run python3 - "$REPO_ROOT/scripts/gates/gate_gunshi_startup.sh" <<'PY'
import pathlib, re, sys
s = pathlib.Path(sys.argv[1]).read_text()
assert '_dd_replay_block=1' in s
assert 'overall="BLOCK"' in s
assert 'if [ "${_dd_replay_block:-0}" -eq 1 ]; then' in s
assert re.search(r'if \[ "\$\{_dd_replay_block:-0\}" -eq 1 \]; then\n\s+exit 2', s)
PY
  [ "$status" -eq 0 ]
}

@test "fresh session is BLOCK1, all phases complete becomes BLOCK0, compaction preservation stays BLOCK0" {
  printf '%s' '2026-07-27T19:00:00+0900' > "$FIX/logs/deepdive_replay/gunshi.session"

  run bash "$FIX/scripts/gates/gate_deepdive_replay.sh" gunshi
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL 未追体験"* ]]

  python3 - "$FIX" <<'PY'
import hashlib, json, pathlib
root = pathlib.Path(__import__("sys").argv[1])
md = root / "memory/deepdive_why_chain_20260321.md"
text = md.read_text()
out = root / "logs/deepdive_replay/gunshi.jsonl"
with out.open("w") as f:
    for p in range(1, 11):
        f.write(json.dumps({"ts":"2026-07-27T19:01:00+0900","agent":"gunshi",
          "file":md.name,"phase":p,"sha256":hashlib.sha256(text.encode()).hexdigest(),
          "self_question":f"Phase {p} の一次結果を確認して通常作業へ進む"}) + "\n")
PY
  run bash "$FIX/scripts/gates/gate_deepdive_replay.sh" gunshi
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]

  # compactはmarkerを更新しない契約なので、同じmarker/receiptで再検証してもPASS。
  run bash "$FIX/scripts/gates/gate_deepdive_replay.sh" gunshi
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}
