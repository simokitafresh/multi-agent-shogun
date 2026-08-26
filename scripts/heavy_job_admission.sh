#!/usr/bin/env bash
# heavy_job_admission.sh — host-wide 単一admission契約(重量テストジョブ最大同時1)。
# cmd_karo_hotfix_heavy_job_admission_202607121348
# cmd_karo_hotfix_test_runner_drvfs_admission_20260723_normal
# receipt schema and admission contract share this task identity.
#
# 使い方: bash scripts/heavy_job_admission.sh -- <実際に実行したいコマンド> [引数...]
#
# 設計:
#   - lockファイルは /tmp 配下(ext4)に固定配置する。WSL2 /mnt/c(NTFS/DrvFs)上の
#     flockは不安定(scripts/lib/lock_path.sh既知知見)なため、hostのfilesystem種別に
#     依存せず安定するext4上の /tmp を使う。lockファイルは1つのみ=host-wide単一
#     semaphore(SSOT)。/tmpはWSL2再起動でクリアされるため、stale lockがホスト
#     再起動を跨いで残留することもない。
#   - `flock -w TIMEOUT LOCKFILE CMD ARGS...` はflock(1)自身がlock取得→exec→
#     解放までを1プロセスで完結させるため、kernelのadvisory lockとしてプロセス
#     異常終了時も自動解放される(busy pollingではなくkernelのブロッキング待機)。
#     flock(1)は独自のgetopt終端記号("--")をサポートしないため、wrapper側の
#     "--"は shift で消費してからflockへは渡さない。
#   - 再入防止: 既にこのプロセスツリー内でadmissionを通過済み(環境変数で明示)なら
#     二重にflockを取得しようとせず素通りする。これによりwrapper経由で起動された
#     重量ジョブの内部から、さらにwrapper経由で別の重量ステップを呼んでも
#     self-deadlockしない(nested呼出しdeadlock対策)。
set -euo pipefail

# cmd_4175: opt-in check_id-granular timing (queue_wait / execution) so the
# git_pre_commit affected_tests dominant term (台帳実測 n=183 mean=113s
# max=1303s) can be split into "waiting for the host-wide semaphore" vs.
# "actually running tests" without guessing. Off by default: this wrapper is
# also invoked directly, unwrapped, by test fixtures that copy only this file
# (no scripts/lib/ alongside) and by other callers (semantic_causal_post_clear.sh)
# that have no stake in this ledger. Only run_tests.sh's self-reexec opts in
# (SHOGUN_HEAVY_JOB_ADMISSION_METRICS=1) so this can never write duplicate/
# unrelated noise into a caller's own ledger context by accident.
_hja_metrics_enabled=0
_hja_metrics_pids=()
if [[ "${SHOGUN_HEAVY_JOB_ADMISSION_METRICS:-0}" == "1" ]]; then
    _hja_self="${BASH_SOURCE[0]:-$0}"
    _hja_lib="$(cd "$(dirname "$_hja_self")" && pwd)/lib/defense_overhead_writer.sh"
    if [[ -f "$_hja_lib" ]]; then
        # shellcheck disable=SC1090,SC1091
        source "$_hja_lib"
        _hja_metrics_enabled=1
    fi
    unset _hja_self _hja_lib
fi

_hja_drain_metrics() {
    local pid
    for pid in "${_hja_metrics_pids[@]}"; do
        wait "$pid" || true
    done
    _hja_metrics_pids=()
}

_hja_leader_pid=""
_hja_on_signal() {
    trap - TERM INT EXIT
    if [[ -n "$_hja_leader_pid" ]]; then
        kill -TERM -- "-$_hja_leader_pid" 2>/dev/null || true
        wait "$_hja_leader_pid" 2>/dev/null || true
    fi
    exit 128
}
trap _hja_on_signal TERM INT

# v2: 2026-07-15、旧lockのFDがdurable背景workerへ継承され、そのworkerが
# SHOGUN_HEAVY_JOB_LOCK_HELD=0で再入して自己デッドロックした。現在の旧inodeを
# 自然timeoutへ隔離しつつ、修正済み契約を即時復旧するためlock世代も更新する。
LOCK_FILE="${SHOGUN_HEAVY_JOB_LOCK_FILE:-/tmp/shogun_heavy_job_admission_v2.lock}"
# 通常のgolden regression(実測550.82s)を大幅に超える上限。真の無期限だと
# 万一のlock leak(理論上あり得ないはずだが)でホストが永久停止するため、
# 実務上「無期限」相当の長さを保ちつつ保険的な上限として3600sを設定する。
TIMEOUT="${SHOGUN_HEAVY_JOB_ADMISSION_TIMEOUT:-3600}"
HEARTBEAT_SECONDS="${SHOGUN_HEAVY_JOB_ADMISSION_HEARTBEAT_SECONDS:-5}"
OWNER_FILE="${SHOGUN_HEAVY_JOB_OWNER_FILE:-${LOCK_FILE}.owner}"
WAITER_DIR="${SHOGUN_HEAVY_JOB_WAITER_DIR:-${LOCK_FILE}.waiters}"
WAITER_MUTEX="${SHOGUN_HEAVY_JOB_WAITER_MUTEX:-${LOCK_FILE}.waiters.lock}"
PRIORITY="${SHOGUN_HEAVY_JOB_PRIORITY:-}"
TASK_DIR="${SHOGUN_HEAVY_JOB_TASK_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)/queue/tasks}"
CAPABILITY_DIR="${SHOGUN_HEAVY_JOB_CAPABILITY_DIR:-/tmp/shogun-heavy-capabilities}"
P9_PROBE_TIMEOUT="${SHOGUN_DRVFS_P9_PROBE_TIMEOUT:-2}"
# A leader may exit after detaching a descendant.  Admission must not wait on
# that process group forever: bounded failure releases the lock and makes the
# lifecycle defect observable to the caller/CI instead of producing a silent
# tail.  A zombie is already terminated and cannot do work, but kill(2) still
# reports its process group as existing on runners whose init has not reaped it.
# Drain therefore means "a non-zombie member remains", not merely kill -0.
# This does not signal unrelated processes or broaden cleanup scope.
DRAIN_TIMEOUT="${SHOGUN_HEAVY_JOB_DRAIN_TIMEOUT:-10}"
DRAIN_MEMBER_LIMIT="${SHOGUN_HEAVY_JOB_DRAIN_MEMBER_LIMIT:-20}"

[[ "$TIMEOUT" =~ ^[1-9][0-9]*$ ]] || { echo "BLOCK: invalid heavy admission timeout" >&2; exit 2; }
[[ "$HEARTBEAT_SECONDS" =~ ^[1-9][0-9]*$ ]] || { echo "BLOCK: invalid heavy admission heartbeat interval" >&2; exit 2; }
[[ "$P9_PROBE_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || { echo "BLOCK: invalid p9 probe timeout" >&2; exit 2; }

if [[ -z "$PRIORITY" && -n "${TMUX_PANE:-}" ]] && command -v tmux >/dev/null 2>&1; then
    admission_agent="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
    admission_task="$TASK_DIR/${admission_agent}.yaml"
    if [[ -r "$admission_task" ]] \
        && awk '$1 == "task_type:" {gsub(/[[:space:]'\''"]/, "", $2); exit !($2 == "ci_fix")}' "$admission_task"; then
        PRIORITY="ci"
    fi
fi
PRIORITY="${PRIORITY:-normal}"
case "${PRIORITY,,}" in
    ci|ci_fix|critical) priority_rank=0 ;;
    normal) priority_rank=10 ;;
    [0-9]|[0-9][0-9]) priority_rank=$((10#$PRIORITY)) ;;
    *) echo "BLOCK: invalid heavy admission priority" >&2; exit 2 ;;
esac

detect_persistent_p9_rpc() {
    local first second resolved_ps
    # Process-lifecycle fixtures intentionally inject a fake ps for drain
    # behavior.  Do not let the unrelated p9 probe consume or reinterpret that
    # fixture; production PATH resolves to the system ps.
    resolved_ps="$(command -v ps 2>/dev/null || true)"
    [[ "$(realpath -- "$resolved_ps" 2>/dev/null || true)" == "$(realpath -- /bin/ps)" ]] || return 1
    first="$(timeout "$P9_PROBE_TIMEOUT" /bin/ps -e -o pid=,stat=,wchan= 2>/dev/null \
        | awk '$2 ~ /^D/ && $3 == "p9_client_rpc" {print $1}' | sort -n | paste -sd, -)" || return 2
    [[ -n "$first" ]] || return 1
    sleep 0.1
    second="$(timeout "$P9_PROBE_TIMEOUT" /bin/ps -e -o pid=,stat=,wchan= 2>/dev/null \
        | awk '$2 ~ /^D/ && $3 == "p9_client_rpc" {print $1}' | sort -n | paste -sd, -)" || return 2
    [[ -n "$second" ]] || return 1
    printf '%s\n' "$second"
}

read_owner_metadata() {
    owner_pid="unknown" owner_started="0" owner_generation="unknown" owner_nonce="unknown"
    if [[ -r "$OWNER_FILE" ]]; then
        read -r owner_pid owner_started owner_generation owner_nonce <"$OWNER_FILE" || true
        [[ "$owner_pid" =~ ^[1-9][0-9]*$ ]] || owner_pid="unknown"
        [[ "$owner_started" =~ ^[1-9][0-9]*$ ]] || owner_started="0"
    fi
}

validate_and_consume_admission_token() {
    local consume="${1:-1}"
    local token="${SHOGUN_HEAVY_JOB_TOKEN:-}" generation="${SHOGUN_HEAVY_JOB_OWNER_GENERATION:-}"
    local claimed_owner="${SHOGUN_HEAVY_JOB_OWNER_PID:-}" consume_file capability_file
    local cap_owner="" cap_generation="" cap_nonce=""
    [[ -n "$token" ]] && capability_file="$CAPABILITY_DIR/$(printf '%s' "$token" | sha256sum | awk '{print $1}').cap"
    [[ -n "${capability_file:-}" && -r "$capability_file" ]] \
        && read -r cap_owner cap_generation cap_nonce <"$capability_file" || true
    [[ -n "$token" && "$token" == "$cap_nonce" && "$generation" == "$cap_generation" \
        && "$claimed_owner" == "$cap_owner" ]] || {
        echo "BLOCK: heavy admission ownership proof mismatch" >&2; return 2;
    }
    [[ "$consume" == "1" ]] || return 0
    consume_file="${capability_file}.consumed"
    ( set -o noclobber; printf '%s\n' "$$" >"$consume_file" ) 2>/dev/null || {
        echo "BLOCK: heavy admission token already consumed" >&2; return 2;
    }
}

process_group_has_live_member() {
    local target_pgid="$1"
    local member_pgid member_stat
    local snapshot

    # Process-substitution status is not propagated to the parent shell.  Take
    # the snapshot explicitly so a ps failure cannot look like an empty/drained
    # group and release admission early.
    if ! snapshot="$(SHOGUN_HEAVY_JOB_DRAIN_PGID="$target_pgid" ps -e -o pgid=,stat=)"; then
        return 0
    fi
    while read -r member_pgid member_stat; do
        [[ "$member_pgid" == "$target_pgid" ]] || continue
        [[ "$member_stat" == Z* ]] || return 0
    done <<< "$snapshot"
    return 1
}

report_live_process_group_members() {
    local target_pgid="$1"
    local snapshot

    # Keep timeout diagnostics bounded and non-sensitive.  In particular, do
    # not expose argv, environment, or cwd; comm is the executable basename.
    if ! snapshot="$(SHOGUN_HEAVY_JOB_DRAIN_PGID="$target_pgid" ps -e -o pid=,ppid=,pgid=,stat=,etimes=,comm=)"; then
        echo "DRAIN_MEMBER_UNAVAILABLE pgid=${target_pgid} reason=ps_failed" >&2
        return 0
    fi
    while read -r member_pid member_ppid member_pgid member_stat member_elapsed member_comm; do
        [[ "$member_pgid" == "$target_pgid" && "$member_stat" != Z* ]] || continue
        member_origin="unknown"
        if [[ "$member_comm" == "bash" && -r "/proc/$member_pid/cmdline" ]]; then
            mapfile -d '' -t member_argv < "/proc/$member_pid/cmdline" || true
            member_origin="${member_argv[1]:-unknown}"
            member_origin="${member_origin##*/}"
            [[ "$member_origin" =~ ^[[:alnum:]_.-]{1,64}$ ]] || member_origin="unknown"
        fi
        printf 'DRAIN_MEMBER pid=%s ppid=%s pgid=%s stat=%s elapsed=%s comm=%s origin=%s\n' \
            "$member_pid" "$member_ppid" "$member_pgid" "$member_stat" "$member_elapsed" "$member_comm" "$member_origin" >&2
        emitted=$(( ${emitted:-0} + 1 ))
        (( emitted < DRAIN_MEMBER_LIMIT )) || break
    done < <(awk -v target="$target_pgid" '
        $3 == target && $4 !~ /^Z/ {
            print $1, $2, $3, $4, $5, $6
        }
    ' <<< "$snapshot")
}

if [[ "${1:-}" == "--" ]]; then
    shift
fi

if [[ "${1:-}" == "--validate-token" ]]; then
    validate_and_consume_admission_token 1
    exit $?
fi

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 -- <command> [args...]" >&2
    exit 2
fi

if [[ "${SHOGUN_HEAVY_JOB_ADMITTED:-0}" == "1" ]]; then
    validate_and_consume_admission_token 0 || exit $?
    exec "$@"
fi
if [[ "${SHOGUN_HEAVY_JOB_LOCK_HELD:-0}" == "1" ]]; then
    exec "$@"
fi

run_id="${SHOGUN_HEAVY_JOB_RUN_ID:-}"
if [[ -n "$run_id" ]]; then
    run_key="$(printf '%s' "$run_id" | sha256sum | awk '{print $1}')"
    run_lock="${SHOGUN_HEAVY_JOB_RUN_LOCK_DIR:-/tmp}/shogun-heavy-run-${run_key}.lock"
    exec {run_fd}>"$run_lock"
    flock -n "$run_fd" || { echo "BLOCK: duplicate heavy run id: $run_id" >&2; exit 2; }
fi

exec {admission_fd}>"$LOCK_FILE"
queue_started="$(date +%s)"
queue_started_ns="$(date -u +%s%N)"
mkdir -p "$WAITER_DIR"
chmod 700 "$WAITER_DIR"
exec {waiter_mutex_fd}>"$WAITER_MUTEX"
waiter_file="$WAITER_DIR/$(printf '%03d-%020d-%010d' "$priority_rank" "$queue_started_ns" "$$")"
process_start_ticks="$(awk '{print $22}' "/proc/$$/stat")"
printf '%s %s %s %s\n' "$$" "$process_start_ticks" "$priority_rank" "$queue_started_ns" >"$waiter_file"
cleanup_waiter() {
    [[ -n "${waiter_file:-}" ]] && rm -f -- "$waiter_file"
    return 0
}
trap cleanup_waiter EXIT

while true; do
    acquired=0
    flock "$waiter_mutex_fd"
    for candidate in "$WAITER_DIR"/*; do
        [[ -f "$candidate" ]] || continue
        read -r candidate_pid candidate_start _ <"$candidate" || candidate_pid=""
        live_start=""
        [[ "$candidate_pid" =~ ^[1-9][0-9]*$ && -r "/proc/$candidate_pid/stat" ]] \
            && live_start="$(awk '{print $22}' "/proc/$candidate_pid/stat" 2>/dev/null || true)"
        if [[ -z "$live_start" || "$live_start" != "$candidate_start" ]]; then
            rm -f -- "$candidate"
        fi
    done
    winner="$(LC_ALL=C find "$WAITER_DIR" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort | head -n1)"
    if [[ -n "$winner" && "$WAITER_DIR/$winner" == "$waiter_file" ]] \
        && flock -n "$admission_fd"; then
        acquired=1
        rm -f -- "$waiter_file"
        waiter_file=""
    fi
    flock -u "$waiter_mutex_fd"
    (( acquired == 0 )) || break

    now="$(date +%s)"
    read_owner_metadata
    owner_age=0
    (( owner_started > 0 && now >= owner_started )) && owner_age=$((now - owner_started))
    printf 'HEAVY_ADMISSION_HEARTBEAT owner_pid=%s owner_age_sec=%s queue_age_sec=%s\n' \
        "$owner_pid" "$owner_age" "$((now - queue_started))" >&2
    if (( now - queue_started >= TIMEOUT )); then
        echo "BLOCK: heavy job admission timeout after ${TIMEOUT}s" >&2
        exit 2
    fi
    sleep "$HEARTBEAT_SECONDS"
done
owner_started="$(date +%s)"
owner_generation="$(date -u +%s%N)-$$"
owner_nonce="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
printf '%s %s %s %s\n' "$$" "$owner_started" "$owner_generation" "$owner_nonce" >"$OWNER_FILE"
mkdir -p "$CAPABILITY_DIR"
chmod 700 "$CAPABILITY_DIR"
capability_file="$CAPABILITY_DIR/$(printf '%s' "$owner_nonce" | sha256sum | awk '{print $1}').cap"
printf '%s %s %s\n' "$$" "$owner_generation" "$owner_nonce" >"$capability_file"
chmod 600 "$capability_file"
cleanup_owner_metadata() {
    local recorded_pid=""
    [[ -r "$OWNER_FILE" ]] && read -r recorded_pid _ <"$OWNER_FILE" || true
    [[ "$recorded_pid" == "$$" ]] && rm -f "$OWNER_FILE"
}
trap 'cleanup_waiter; cleanup_owner_metadata' EXIT
_hja_queue_age_sec=$((owner_started - queue_started))
printf 'HEAVY_ADMISSION_ACQUIRED owner_pid=%s queue_age_sec=%s\n' "$$" "$_hja_queue_age_sec" >&2
if [[ "$_hja_metrics_enabled" == "1" ]]; then
    # The generic async writer inherits every open descriptor in its caller.
    # Close admission-owned lock descriptors in the writer process before it
    # can outlive this wrapper; otherwise a slow ledger write keeps the host
    # semaphore locked after the admitted process group has already drained.
    (
        eval "exec ${admission_fd}>&-"
        [[ -z "${run_fd:-}" ]] || eval "exec ${run_fd}>&-"
        defense_overhead_write heavy_job_admission queue_wait "$((_hja_queue_age_sec * 1000))" \
            PASS "hja-${owner_generation}-queue"
    ) >/dev/null 2>&1 &
    _hja_metrics_pids+=("$!")
fi

p9_pids=""
set +e
p9_pids="$(detect_persistent_p9_rpc)"
p9_rc=$?
set -e
case "$p9_rc" in
    0) export RUN_TESTS_DRVFS_P9_DETECTED=1
       printf 'DRVFS_P9_STATE persistent=1 probe_timeout_sec=%s pids=%s\n' "$P9_PROBE_TIMEOUT" "$p9_pids" >&2 ;;
    1) export RUN_TESTS_DRVFS_P9_DETECTED=0
       printf 'DRVFS_P9_STATE persistent=0 probe_timeout_sec=%s pids=none\n' "$P9_PROBE_TIMEOUT" >&2 ;;
    *) echo "BLOCK: bounded p9_client_rpc probe failed" >&2; exit 2 ;;
esac

# A shell can return while a background descendant is still doing the real
# work.  Run each top-level job in its own session and retain both admission
# locks until the complete process group drains.  Closing the lock descriptors
# in the child preserves the durable-worker re-entry contract.
export SHOGUN_HEAVY_JOB_LOCK_HELD=1
export SHOGUN_HEAVY_JOB_ADMITTED=1
export SHOGUN_HEAVY_JOB_TOKEN="$owner_nonce"
export SHOGUN_HEAVY_JOB_OWNER_GENERATION="$owner_generation"
export SHOGUN_HEAVY_JOB_OWNER_PID="$$"
ADMISSION_FD="$admission_fd" RUN_FD="${run_fd:-}" setsid bash -c '
    eval "exec ${ADMISSION_FD}>&-"
    [[ -z "$RUN_FD" ]] || eval "exec ${RUN_FD}>&-"
    exec "$@"
' _ "$@" &
leader_pid=$!
_hja_leader_pid="$leader_pid"
rc=0
wait "$leader_pid" || rc=$?
_hja_leader_pid=""
if [[ "$_hja_metrics_enabled" == "1" ]]; then
    (
        eval "exec ${admission_fd}>&-"
        [[ -z "${run_fd:-}" ]] || eval "exec ${run_fd}>&-"
        defense_overhead_write heavy_job_admission execution \
            "$(( ($(date +%s) - owner_started) * 1000 ))" \
            "$([[ "$rc" -eq 0 ]] && echo PASS || echo FAIL)" "hja-${owner_generation}-exec"
    ) >/dev/null 2>&1 &
    _hja_metrics_pids+=("$!")
fi
drain_started=$SECONDS
while process_group_has_live_member "$leader_pid"; do
    if (( SECONDS - drain_started >= DRAIN_TIMEOUT )); then
        echo "BLOCK: heavy job process group -${leader_pid} did not drain within ${DRAIN_TIMEOUT}s" >&2
        report_live_process_group_members "$leader_pid"
        exit 124
    fi
    sleep 0.05
done
_hja_drain_metrics
exit "$rc"
