#!/usr/bin/env bats
# contract test: scratch/lock directory retention
# test_necessity: 作業残骸とlockディレクトリは無制限に蓄積し走査コストを押し上げるが、
#                 退避対象に git worktree 登録済みパスが1件でも混じるとworktreeが壊れる。
#                 「TTL超過の未登録scratchのみ集約移動し、登録済みworktreeは1件も動かさない」
#                 という不変量(陰性対照)を守る。
# origin: [[cmd_karo_impl_scratch_retention_cleanup_20260725]] -> [[retention欠落による残骸83,344ファイル]] -> [[走査系の劣化と登録worktree破壊リスク]]

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    FIX="$BATS_TEST_TMPDIR/fix"
    TMPD="$FIX/tmp"
    REPO="$FIX/repo"
    QUAR="$FIX/quarantine"
    mkdir -p "$TMPD" "$REPO" "$QUAR"
    git -C "$REPO" init -q
    git -C "$REPO" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init
}

# ninja_monitor.sh 全体をsourceせず、対象関数だけを切り出して評価する
load_retention() {
    SCRIPT_DIR="$REPO"
    log() { :; }
    # shellcheck disable=SC1090
    eval "$(awk '/^SCRATCH_RETENTION_TTL_MIN=/,/^}$/' "$REPO_ROOT/scripts/ninja_monitor.sh")"
}

age_dir() { touch -d '3 days ago' "$1"; }

@test "TTL超過のscratch/lockディレクトリは集約移動される(発火する場合)" {
    mkdir -p "$TMPD/shogun_lock_deadbeef00000000.lock" "$REPO/.saizo-topic.AbCdEf"
    age_dir "$TMPD/shogun_lock_deadbeef00000000.lock"
    age_dir "$REPO/.saizo-topic.AbCdEf"

    load_retention
    SCRATCH_QUARANTINE_DIR="$QUAR" SCRATCH_RETENTION_REPO="$REPO" run_scratch_retention "$TMPD"

    [ ! -e "$TMPD/shogun_lock_deadbeef00000000.lock" ]
    [ ! -e "$REPO/.saizo-topic.AbCdEf" ]
    [ -d "$QUAR/shogun_lock_deadbeef00000000.lock" ]
    [ -d "$QUAR/.saizo-topic.AbCdEf" ]
}

@test "TTL内のscratchは1件も動かさない(発火しない場合)" {
    mkdir -p "$TMPD/shogun_lock_cafebabe00000000.lock" "$REPO/.hanzo-fresh.XyZ123"

    load_retention
    SCRATCH_QUARANTINE_DIR="$QUAR" SCRATCH_RETENTION_REPO="$REPO" run_scratch_retention "$TMPD"

    [ -d "$TMPD/shogun_lock_cafebabe00000000.lock" ]
    [ -d "$REPO/.hanzo-fresh.XyZ123" ]
    [ -z "$(ls -A "$QUAR")" ]
}

# 陰性対照: 検出されてはならないもの(登録済みworktree)が対象に含まれないこと
@test "git worktree登録済みのscratchはTTL超過でも移動されない(陰性対照)" {
    git -C "$REPO" worktree add -q --detach "$REPO/.live-wt.QqWwEe" >/dev/null
    age_dir "$REPO/.live-wt.QqWwEe"

    load_retention
    SCRATCH_QUARANTINE_DIR="$QUAR" SCRATCH_RETENTION_REPO="$REPO" run_scratch_retention "$TMPD"

    [ -d "$REPO/.live-wt.QqWwEe" ]
    [ ! -e "$QUAR/.live-wt.QqWwEe" ]
    git -C "$REPO" worktree list | grep -q ".live-wt.QqWwEe"
}
