#!/usr/bin/env bats

# test_necessity: snapshot候補をtask/pane一次状態で照合し、grace中FP・処理済みescalation・同一署名再通知を恒久的に0へ保つ境界契約。

setup() {
  ROOT="$BATS_TEST_TMPDIR/root"; mkdir -p "$ROOT/queue/inbox" "$ROOT/queue/tasks" "$ROOT/logs" "$BATS_TEST_TMPDIR/bin"
  cp "$BATS_TEST_DIRNAME/../../.claude/hooks/post-shogun-inbox-check.sh" "$ROOT/hook.sh"
  touch "$ROOT/logs/shogun_recovery_complete"
  cat > "$BATS_TEST_TMPDIR/bin/tmux" <<'SH'
#!/bin/sh
case "$*" in *list-panes*) echo "hayate|${TEST_PANE_STATE:-idle}"; echo "hanzo|${TEST_PANE_STATE:-idle}";; *'# {@agent_id}'*) echo shogun;; *) echo shogun;; esac
SH
  sed -i 's/# {@/#\{@/g' "$BATS_TEST_TMPDIR/bin/tmux"
  chmod +x "$BATS_TEST_TMPDIR/bin/tmux"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH" TMUX_PANE=%99 SHOGUN_ROOT="$ROOT" SHOGUN_ALERT_NOW=2000000000 SHOGUN_SNAPSHOT_GRACE_SEC=120
  export SHOGUN_SNAPSHOT_DEDUP_FILE="$BATS_TEST_TMPDIR/snap.dedup" SHOGUN_ESCALATION_DEDUP_FILE="$BATS_TEST_TMPDIR/esc.dedup"
  printf 'messages: []\n' > "$ROOT/queue/inbox/shogun.yaml"
}

@test "fresh snapshot candidate is quiet, post-grace real stall remains detected" {
  printf 'ninja|hayate|t|assigned|infra|CTX:0%%|RUNTIME:busy\n' > "$ROOT/queue/karo_snapshot.txt"
  printf "task:\n  status: assigned\n  deployed_at: '%s'\n" "$(date -d @1999999940 -Is)" > "$ROOT/queue/tasks/hayate.yaml"
  run dash "$ROOT/hook.sh"; [[ "$output" != *"陣形図異常"* ]]
  printf "task:\n  status: assigned\n  deployed_at: '%s'\n" "$(date -d @1999999800 -Is)" > "$ROOT/queue/tasks/hayate.yaml"
  run dash "$ROOT/hook.sh"; [[ "$output" == *"stall疑い=[hayate]"* ]]
}

@test "snapshot failed requires task failed and detects the true failure once" {
  printf 'ninja|hanzo|t|failed|infra|CTX:20%%|RUNTIME:idle\n' > "$ROOT/queue/karo_snapshot.txt"
  printf "task:\n  status: in_progress\n  deployed_at: '%s'\n" "$(date -d @1999999800 -Is)" > "$ROOT/queue/tasks/hanzo.yaml"
  run dash "$ROOT/hook.sh"; [[ "$output" != *"failed=[hanzo]"* ]]
  sed -i 's/in_progress/failed/' "$ROOT/queue/tasks/hanzo.yaml"
  run dash "$ROOT/hook.sh"; [[ "$output" == *"failed=[hanzo]"* ]]
}

@test "escalation signature is critical once, processed is quiet, new signature alerts" {
  cat > "$ROOT/queue/inbox/shogun.yaml" <<'YAML'
messages:
- {type: escalation, read: false, from: karo, action: fix, content: same warning}
YAML
  run dash "$ROOT/hook.sh"; [[ "$output" == *"CRITICAL 新規エスカレーション1件"* ]]
  run dash "$ROOT/hook.sh"; [[ "$output" != *"CRITICAL 新規エスカレーション"* ]]
  sed -i 's/read: false/read: true/' "$ROOT/queue/inbox/shogun.yaml"
  run dash "$ROOT/hook.sh"; [[ "$output" != *"未対処エスカレーション"* ]]
  sed -i 's/read: true/read: false/; s/same warning/new warning/' "$ROOT/queue/inbox/shogun.yaml"
  run dash "$ROOT/hook.sh"; [[ "$output" == *"CRITICAL 新規エスカレーション1件"* ]]
}
