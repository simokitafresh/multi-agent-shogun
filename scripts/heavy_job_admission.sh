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
while kill -0 -- "-$leader_pid" 2>/dev/null; do
    sleep 0.05
done
exit "$rc"
