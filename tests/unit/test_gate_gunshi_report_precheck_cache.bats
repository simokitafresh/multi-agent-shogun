#!/usr/bin/env bats
# test_necessity: full_precheckはledger実測で平均5.17秒×555回(cmd_4167台帳集計)。
# report内容hash単位のcacheが無ければ、同一reportの再precheckのたびに全量再検査が走り続け
# レビュー往復のコストが線形に積み上がる不変量を守れない。

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  GATE="$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck.sh"
  TMP_DIR="$(mktemp -d)"
  mkdir -p "$TMP_DIR/tasks"
  export GUNSHI_PRECHECK_CACHE_DIR="$TMP_DIR/cache"
  export GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks"
  cat > "$TMP_DIR/tasks/kagemaru.yaml" <<'YAML'
task:
  binary_checks:
    AC1:
      - check: concrete check
        result: yes
YAML
  cat > "$TMP_DIR/report.yaml" <<'YAML'
worker_id: kagemaru
parent_cmd: cmd_fixture
assumption_check: "未確認前提なし"
task_clarity:
  score: 100
  unclear_points: なし
  discretion_fills: なし
binary_checks:
  AC1:
    - check: concrete check
      result: yes
YAML
}

teardown() {
  # D002: /tmp配下への再帰削除は禁止。fixtureが作る既知階層だけを
  # 非再帰で空にしてからrmdirする。
  rm -f "$TMP_DIR"/tasks/kagemaru.yaml \
        "$TMP_DIR"/report.yaml \
        "$TMP_DIR"/out*.txt \
        "$TMP_DIR"/err*.txt \
        "$TMP_DIR"/cache/*
  rmdir "$TMP_DIR"/cache "$TMP_DIR"/tasks "$TMP_DIR" 2>/dev/null || true
}

@test "unchanged reports are cached and edits invalidate the cached result" {
  rc1=0
  bash "$GATE" "$TMP_DIR/report.yaml" > "$TMP_DIR/out1.txt" 2> "$TMP_DIR/err1.txt" || rc1=$?

  rc2=0
  bash "$GATE" "$TMP_DIR/report.yaml" > "$TMP_DIR/out2.txt" 2> "$TMP_DIR/err2.txt" || rc2=$?

  [ "$rc1" -eq "$rc2" ]
  diff "$TMP_DIR/out1.txt" "$TMP_DIR/out2.txt"
  grep -q "cache応答" "$TMP_DIR/err2.txt"
  ! grep -q "cache応答" "$TMP_DIR/err1.txt"

  cache_entries_before=$(find "$GUNSHI_PRECHECK_CACHE_DIR" -type f | wc -l)
  [ "$cache_entries_before" -eq 1 ]

  # Substantive content change: satisfies SG-PRE34/LG055's operational_simulation
  # contract, which flips one of the two baseline ERRORS from FAIL to PASS.
  cat >> "$TMP_DIR/report.yaml" <<'YAML'
operational_simulation:
  command: "bash scripts/gates/gate_gunshi_report_precheck.sh fixture"
  expected: "exit 0/1"
  actual: "exit 1"
  result: PASS
YAML

  rc3=0
  bash "$GATE" "$TMP_DIR/report.yaml" > "$TMP_DIR/out3.txt" 2> "$TMP_DIR/err3.txt" || rc3=$?

  # Fresh recheck evidence: no cache-hit marker, and the ERRORS tally moved.
  ! grep -q "cache応答" "$TMP_DIR/err3.txt"
  ! diff -q "$TMP_DIR/out1.txt" "$TMP_DIR/out3.txt" > /dev/null
  grep -q "=== 総合: ERRORS=3 ===" "$TMP_DIR/out1.txt"
  grep -q "=== 総合: ERRORS=2 ===" "$TMP_DIR/out3.txt"
  cache_entries_after=$(find "$GUNSHI_PRECHECK_CACHE_DIR" -type f | wc -l)
  [ "$cache_entries_after" -eq 2 ]

  # The new (post-edit) report content is itself now cached and reproducible.
  rc4=0
  bash "$GATE" "$TMP_DIR/report.yaml" > "$TMP_DIR/out4.txt" 2> "$TMP_DIR/err4.txt" || rc4=$?
  [ "$rc3" -eq "$rc4" ]
  diff "$TMP_DIR/out3.txt" "$TMP_DIR/out4.txt"
  grep -q "cache応答" "$TMP_DIR/err4.txt"
}

@test "GUNSHI_PRECHECK_ONLY focused checks bypass the full-precheck cache" {
  run env GUNSHI_PRECHECK_ONLY=SG-PRE9 bash "$GATE" "$TMP_DIR/report.yaml"
  [ "$status" -eq 0 ]
  entries=$(find "$GUNSHI_PRECHECK_CACHE_DIR" -type f 2>/dev/null | wc -l)
  [ "$entries" -eq 0 ]
}
