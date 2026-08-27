#!/usr/bin/env bats
# test_necessity: done検知(check_and_update_done_task)はdeploy_ninja_<worker>.lockでdeployと
# 直列化され(同時に走らない)、直列化が機能した回だけkaro_snapshotへ同一世代のsource timestampを
# 即時反映する。実装の表現(波括弧かサブシェルか・関数名の綴り)には依存させない。
# 旧実装はninja_monitor.shのソースをt.index("check_and_update_done_task() {")で文字列切出し
# していたが、commit 4dd2c9c7c(2026-07-19)で `() {` が `() (` (サブシェル化)へ変わり、
# かつ以降の還流/snapshot高速化リファクタで呼出し関数名も変わったためValueErrorでFAILしていた
# (将軍裁定 掲示板blt_20260726_184004)。

setup() {
    ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

# check_and_update_done_taskを実行環境から隔離して呼び出し、
# 「deploy lockが競合中はauto-doneが退避し、解放後にのみ同一世代SRCでkaro_snapshotへ
# 即時公開する」不変量を検証する。$1に検証対象のninja_monitor.shパスを渡す。
_run_serialize_scenario() {
    run env PROJECT_ROOT="$ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1
        source "$1"
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"
        STATE_DIR="$BATS_TEST_TMPDIR/state"
        LOG="$BATS_TEST_TMPDIR/log"
        KARO_SNAPSHOT_LOCK_FILE="$BATS_TEST_TMPDIR/karo_snapshot.lock"
        mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/locks" "$STATE_DIR"
        ln -s "$PROJECT_ROOT/scripts" "$SCRIPT_DIR/scripts"
        : >"$LOG"
        report_monitor_state() { printf "pass_terminal\n"; }
        _reflux_promotion_record_completion_detached() { :; }
        task="$SCRIPT_DIR/queue/tasks/alpha.yaml"
        report="$SCRIPT_DIR/queue/reports/alpha_report_cmd_x.yaml"
        printf "task:\n  parent_cmd: cmd_x\n  task_id: task_x\n  status: in_progress\n" > "$task"
        printf "parent_cmd: cmd_x\ntask_id: task_x\nstatus: done\ntimestamp: 2026-07-26T18:00:00+09:00\n" > "$report"
        find_matching_report_file() { printf "%s\n" "$report"; }
        # deploy_task.shが同一忍者へ配備中であることを模す(同一lockパスを外部保持)
        flock "$SCRIPT_DIR/queue/locks/deploy_ninja_alpha.lock" -c "sleep 1" & holder=$!
        sleep 0.2
        if check_and_update_done_task alpha; then rc1=0; else rc1=$?; fi
        if grep -q "status: in_progress" "$task"; then still_in_progress=0; else still_in_progress=1; fi
        wait "$holder"
        if check_and_update_done_task alpha; then rc2=0; else rc2=$?; fi
        expected_src=$(date -r "$task" "+%Y-%m-%dT%H:%M:%S")
        actual_line=$(grep "^ninja|alpha|" "$SCRIPT_DIR/queue/karo_snapshot.txt" 2>/dev/null || true)
        printf "rc1=%s still_in_progress=%s rc2=%s expected_src=%s line=%s\n" "$rc1" "$still_in_progress" "$rc2" "$expected_src" "$actual_line"
        # 直列化: lock競合中はskipし、task/snapshotのどちらも書き換えない
        [ "$rc1" -eq 1 ] || exit 1
        [ "$still_in_progress" -eq 0 ] || exit 1
        # lock解放後はauto-doneが成功し、taskがdoneへ遷移する
        [ "$rc2" -eq 0 ] || exit 1
        grep -q "status: done" "$task" || exit 1
        # 即時公開: 同一呼び出しの中でkaro_snapshotが更新され、SRCがtask fileの現世代mtimeと一致する
        printf "%s" "$actual_line" | grep -q "TASK:done" || exit 1
        printf "%s" "$actual_line" | grep -q "SRC:${expected_src}" || exit 1
        exit 0
    ' _ "$1"
}

@test "positive: deploy-lock serialization defers auto-done while busy, then publishes fresh same-generation snapshot once free" {
    _run_serialize_scenario "$ROOT/scripts/ninja_monitor.sh"
    [ "$status" -eq 0 ]
}

@test "negative: mutating away the deploy-lock guard lets auto-done race a concurrent deploy (regression is caught)" {
    shadow_root="$BATS_TEST_TMPDIR/shadow_repo"
    mkdir -p "$shadow_root/scripts"
    ln -s "$ROOT/lib" "$shadow_root/lib"
    for f in "$ROOT"/scripts/*; do
        base="$(basename "$f")"
        [ "$base" = "ninja_monitor.sh" ] && continue
        ln -s "$f" "$shadow_root/scripts/$base"
    done
    # 直列化ガード(flock -n busy判定)そのものを無効化する変異
    sed 's/if ! flock -n "\$deploy_lock_fd"; then/if false; then/' "$ROOT/scripts/ninja_monitor.sh" > "$shadow_root/scripts/ninja_monitor.sh"
    grep -q 'if false; then' "$shadow_root/scripts/ninja_monitor.sh"

    _run_serialize_scenario "$shadow_root/scripts/ninja_monitor.sh"
    [ "$status" -ne 0 ]
}

# test_necessity: a content-identical snapshot whose Generated age exceeds the
# 600-second freshness contract must be atomically regenerated on the next
# publication, even when no source row changed.
@test "stale content-identical snapshot is forcibly regenerated" {
    run bash -c '
set -euo pipefail
ROOT="'"$ROOT"'"
TMP="'"$BATS_TEST_TMPDIR"'/stale-refresh"
mkdir -p "$TMP/queue/tasks" "$TMP/queue/inbox"
printf "task:\n  task_id: task_x\n  status: idle\n  project: infra\n" > "$TMP/queue/tasks/saizo.yaml"
printf "messages:\n" > "$TMP/queue/inbox/karo.yaml"
OLD=$(date -d "20 minutes ago" +%Y-%m-%dT%H:%M:%S)
NINJA_MONITOR_LIB_ONLY=1 SHOGUN_TEST_ROOT="$TMP" KARO_SNAPSHOT_STALE_THRESHOLD_SEC=600 bash -c '\''
  source "'"$ROOT"'/scripts/ninja_monitor.sh"
  SCRIPT_DIR="$SHOGUN_TEST_ROOT"
  LOG="$SHOGUN_TEST_ROOT/monitor.log"
  NINJA_NAMES=(saizo)
  PANE_TARGETS=()
  refresh_karo_snapshot_generation
  sed -i "s/^# Generated:.*/# Generated: '"$OLD"'/" "$SHOGUN_TEST_ROOT/queue/karo_snapshot.txt"
  refresh_karo_snapshot_generation
'\''
before=$OLD
after=$(sed -n "s/^# Generated: //p" "$TMP/queue/karo_snapshot.txt")
age=$(( $(date +%s) - $(date -d "$after" +%s) ))
[ "$before" != "$after" ]
[ "$age" -ge 0 ] && [ "$age" -le 600 ]
grep -q "SNAPSHOT-STALE-REFRESH: content_diff=0 source_diff=0" "$TMP/monitor.log"
printf "stale_refresh=1 age_sec=%s threshold_sec=600\n" "$age"
'
    if [ "$status" -ne 0 ]; then
        printf '%s\n' "$output"
        false
    fi
}
