#!/usr/bin/env bash
# heavy_job_admission.sh — host-wide 単一admission契約(重量テストジョブ最大同時1)。
# cmd_karo_hotfix_heavy_job_admission_202607121348
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

# v2: 2026-07-15、旧lockのFDがdurable背景workerへ継承され、そのworkerが
# SHOGUN_HEAVY_JOB_LOCK_HELD=0で再入して自己デッドロックした。現在の旧inodeを
# 自然timeoutへ隔離しつつ、修正済み契約を即時復旧するためlock世代も更新する。
LOCK_FILE="${SHOGUN_HEAVY_JOB_LOCK_FILE:-/tmp/shogun_heavy_job_admission_v2.lock}"
# 通常のgolden regression(実測550.82s)を大幅に超える上限。真の無期限だと
# 万一のlock leak(理論上あり得ないはずだが)でホストが永久停止するため、
# 実務上「無期限」相当の長さを保ちつつ保険的な上限として3600sを設定する。
TIMEOUT="${SHOGUN_HEAVY_JOB_ADMISSION_TIMEOUT:-3600}"
# A leader may exit after detaching a descendant.  Admission must not wait on
# that process group forever: bounded failure releases the lock and makes the
# lifecycle defect observable to the caller/CI instead of producing a silent
# tail.  A zombie is already terminated and cannot do work, but kill(2) still
# reports its process group as existing on runners whose init has not reaped it.
# Drain therefore means "a non-zombie member remains", not merely kill -0.
# This does not signal unrelated processes or broaden cleanup scope.
DRAIN_TIMEOUT="${SHOGUN_HEAVY_JOB_DRAIN_TIMEOUT:-10}"
DRAIN_MEMBER_LIMIT="${SHOGUN_HEAVY_JOB_DRAIN_MEMBER_LIMIT:-20}"

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

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 -- <command> [args...]" >&2
    exit 2
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
flock -w "$TIMEOUT" "$admission_fd" \
    || { echo "BLOCK: heavy job admission timeout after ${TIMEOUT}s" >&2; exit 2; }

# A shell can return while a background descendant is still doing the real
# work.  Run each top-level job in its own session and retain both admission
# locks until the complete process group drains.  Closing the lock descriptors
# in the child preserves the durable-worker re-entry contract.
export SHOGUN_HEAVY_JOB_LOCK_HELD=1
ADMISSION_FD="$admission_fd" RUN_FD="${run_fd:-}" setsid bash -c '
    eval "exec ${ADMISSION_FD}>&-"
    [[ -z "$RUN_FD" ]] || eval "exec ${RUN_FD}>&-"
    exec "$@"
' _ "$@" &
leader_pid=$!
rc=0
wait "$leader_pid" || rc=$?
drain_started=$SECONDS
while process_group_has_live_member "$leader_pid"; do
    if (( SECONDS - drain_started >= DRAIN_TIMEOUT )); then
        echo "BLOCK: heavy job process group -${leader_pid} did not drain within ${DRAIN_TIMEOUT}s" >&2
        report_live_process_group_members "$leader_pid"
        exit 124
    fi
    sleep 0.05
done
exit "$rc"
