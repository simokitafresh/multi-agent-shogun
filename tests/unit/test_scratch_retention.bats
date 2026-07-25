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

load_tmp_cache_retention() {
    log() { :; }
    # shellcheck disable=SC1090
    eval "$(awk '/^TMP_CACHE_RETENTION_TTL_MIN=/,/^}$/' "$REPO_ROOT/scripts/ninja_monitor.sh")"
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

# ── /tmp cache retention (cmd_karo_impl_tmp_cache_retention_20260726) ──
# test_necessity: /tmp直下のcacheは無制限に蓄積しmaxdepth1走査を直撃するが、使用中のcache
#                 (TTL内)や実行中プロセスが所有する review_fp_cache を退避すると
#                 進行中のレビュー・鮮度判定が壊れる。「TTL超過のcacheのみ集約移動し、
#                 TTL内と生存PID所有分は1件も動かさない」という不変量(陰性対照)を守る。
# origin: [[cmd_karo_impl_tmp_cache_retention_20260726]] -> [[cache retention欠落による/tmp 130,377件]] -> [[全gate/配備のpreflight走査劣化]]

@test "TTL超過の/tmp cacheは集約移動される(発火する場合)" {
    touch "$TMPD/context_freshness_check_111_222.cache" \
          "$TMPD/context_freshness_check_111_222.cache.3456" \
          "$TMPD/cmd_save_q11_999.cache" \
          "$TMPD/pre_bash_memory_inject_777"
    mkdir -p "$TMPD/review_fp_cache_4194304_31337"
    age_dir "$TMPD/context_freshness_check_111_222.cache"
    age_dir "$TMPD/context_freshness_check_111_222.cache.3456"
    age_dir "$TMPD/cmd_save_q11_999.cache"
    age_dir "$TMPD/pre_bash_memory_inject_777"
    age_dir "$TMPD/review_fp_cache_4194304_31337"

    load_tmp_cache_retention
    TMP_CACHE_QUARANTINE_DIR="$QUAR" run_tmp_cache_retention "$TMPD"

    [ -f "$QUAR/context_freshness_check_111_222.cache" ]
    [ -f "$QUAR/context_freshness_check_111_222.cache.3456" ]
    [ -f "$QUAR/cmd_save_q11_999.cache" ]
    [ -f "$QUAR/pre_bash_memory_inject_777" ]
    [ -d "$QUAR/review_fp_cache_4194304_31337" ]
    [ "$(find "$TMPD" -maxdepth 1 -mindepth 1 | wc -l)" -eq 0 ]
}

@test "TTL内の/tmp cacheは1件も動かさない(発火しない場合・陰性対照)" {
    touch "$TMPD/context_freshness_check_111_333.cache" "$TMPD/cmd_save_q11_888.cache"
    mkdir -p "$TMPD/review_fp_cache_4194304_4242"

    load_tmp_cache_retention
    TMP_CACHE_QUARANTINE_DIR="$QUAR" run_tmp_cache_retention "$TMPD"

    [ -f "$TMPD/context_freshness_check_111_333.cache" ]
    [ -f "$TMPD/cmd_save_q11_888.cache" ]
    [ -d "$TMPD/review_fp_cache_4194304_4242" ]
    [ -z "$(ls -A "$QUAR")" ]
}

@test "生存プロセスが所有するreview_fp_cacheはTTL超過でも動かさない(陰性対照)" {
    mkdir -p "$TMPD/review_fp_cache_$$_55555"
    age_dir "$TMPD/review_fp_cache_$$_55555"

    load_tmp_cache_retention
    TMP_CACHE_QUARANTINE_DIR="$QUAR" run_tmp_cache_retention "$TMPD"

    [ -d "$TMPD/review_fp_cache_$$_55555" ]
    [ -z "$(ls -A "$QUAR")" ]
}

@test "対象外の/tmpエントリには触れない(scope陰性対照)" {
    touch "$TMPD/shogun_lock_abc.lock" "$TMPD/unrelated_file.txt"
    age_dir "$TMPD/shogun_lock_abc.lock"
    age_dir "$TMPD/unrelated_file.txt"

    load_tmp_cache_retention
    TMP_CACHE_QUARANTINE_DIR="$QUAR" run_tmp_cache_retention "$TMPD"

    [ -f "$TMPD/shogun_lock_abc.lock" ]
    [ -f "$TMPD/unrelated_file.txt" ]
    [ -z "$(ls -A "$QUAR")" ]
}
