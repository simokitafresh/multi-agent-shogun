#!/usr/bin/env bash
# heavy_job_classify.sh — 重量テストジョブ判定の唯一の入口(SSOT)。
# cmd_karo_hotfix_heavy_job_admission_202607121348
#
# guard14_db_trust_classify.sh と同じ2段構成:
#   1. heavy_job_maybe_relevant() — bash-nativeの保守的negative filter。
#      scripts/lib/heavy_job_classify.py のclassify()が"heavy"を返し得る
#      「必要条件」(bats/pytest/python(3)/run_tests.shのいずれかの文字列を含む)
#      をミラーする。1つも一致しなければpython側も必ず"light"を返すと保証されるため、
#      python3プロセスを起動せず"light"を直接返す。
#   2. 一致した場合のみ python3 -S heavy_job_classify.py を起動し、
#      argv位置ベースの構造判定に委譲する。
#
# 呼び出し側は heavy_job_classify "$command" を無条件で呼び、
# 返り値("heavy"/"light")だけを見る。

heavy_job_maybe_relevant() {
    local cmd="$1"
    [[ "$cmd" == *bats* ]] && return 0
    [[ "$cmd" == *pytest* ]] && return 0
    [[ "$cmd" == *run_tests.sh* ]] && return 0
    [[ "$cmd" =~ python3?([[:space:]]|$) ]] && return 0
    return 1
}

heavy_job_classify() {
    local command="$1"
    if heavy_job_maybe_relevant "$command"; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        HEAVY_JOB_COMMAND="$command" python3 -S "${script_dir}/lib/heavy_job_classify.py" 2>/dev/null || echo "heavy"
    else
        echo "light"
    fi
}
