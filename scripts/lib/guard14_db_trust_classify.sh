#!/usr/bin/env bash
# guard14_db_trust_classify.sh — Guard14 DB接続信頼境界分類器の唯一の入口(SSOT)。
# cmd_karo_hotfix_guard14_db_trust_boundary_202607120854
#
# review_correction(2026-07-12 09:45, karo): _g14_maybe_connection() を
# pre-bash-combined.sh本体へ直書きすると「hook側の語彙gate」と「Python側のintent判定」
# の二重SSOTになりAC2(分類結果だけで判断する)を満たさない。本ファイルが唯一の入口。
# 呼び出し側(pre-bash-combined.sh)は guard14_classify "$payload" "$command" を無条件で
# 呼び、その返り値(not_connection / connection:local_ephemeral / connection:untrusted)
# だけを見る。中で何段の判定をしているかは呼び出し側の関心事ではない。
#
# guard14_classify内部は2段:
#   1. guard14_maybe_connection() — bash-nativeの保守的negative filter。
#      scripts/lib/guard14_db_trust_classify.py の _segment_has_db_marker /
#      _is_connection_segment が connection intentと判定し得る「必要条件」を
#      1対1でミラーする(構造的signalカテゴリ。個別client名の列挙ではない)。
#      1つも一致しなければ、Python側も必ずnot_connectionを返すと保証されるため、
#      python3プロセスを起動せずnot_connectionを直接返す(WSL2実測+29ms/呼び出しの回避)。
#   2. 一致した場合のみ python3 -S guard14_db_trust_classify.py を起動し、
#      構造判定(shlex tokenize+segment分離+DSN抽出+urllib.parse+realpath同一性)に委譲する。
#
# tests/unit/test_pre_bash_guard14_fast_filter_sync.bats が本ファイルのnegative filterと
# classify.pyの全fixtureとの乖離(false negative)を検証する。

guard14_maybe_connection() {
    local cmd="$1"
    # (1) DSN URLスキーム
    [[ "$cmd" == *'postgres://'* || "$cmd" == *'postgresql://'* ]] && return 0
    # (2) DB系env/DSN変数名。review_correction(09:51, karo): 単なる_URL/_DSN suffixだけでは
    # API_URL/SENTRY_DSN等の無関係env varまで拾いPython側でunknown BLOCKし得る。
    # DB/DATABASE/POSTGRES/PGというDB意味トークンを含むことを要求する。
    [[ "$cmd" =~ [A-Z][A-Z0-9_]*(DB|DATABASE|POSTGRES|PG)[A-Z0-9_]*_(URL|DSN)([^A-Za-z0-9_]|$) ]] && return 0
    # (3) CLI接続tool(psql。Postgres標準CLIでありこのスタックでの正規token)
    [[ "$cmd" == *psql* ]] && return 0
    # (4) 接続API呼出の形(psycopg2/psycopg v3/asyncpg/pg8000等の異種clientを横断)。
    # review_correction(09:51, karo): Python側 CONNECT_CALL_RE は\s*で空白を許容するが
    # shell側は固定文字列'.connect('のみだった。同期させる。
    [[ "$cmd" =~ \.connect[[:space:]]*\( ]] && return 0
    # (5) engine factory呼出の形(create_db_engine/create_engine/create_async_engine等)
    [[ "$cmd" =~ create_[A-Za-z_]*engine[[:space:]]*\( ]] && return 0
    # (6) host指定
    [[ "$cmd" =~ host[[:space:]]*= ]] && return 0
    # (7) in-memoryマーカー
    [[ "$cmd" == *':memory:'* ]] && return 0
    # (8) credential source。Python側が明示HTTP callとの組合せだけnot_connectionへ落とす。
    # fast filterは保守的negative filterなので.envを必ずslow-pathへ渡す。
    [[ "$cmd" =~ (^|[^A-Za-z0-9_])\.env(\.[A-Za-z0-9_]+)?([^A-Za-z0-9_]|$) ]] && return 0
    return 1
}

guard14_classify() {
    local payload="$1"
    local command="$2"

    if guard14_maybe_connection "$command"; then
        # review_correction(09:51, karo): script_dir算出(dirname+cd+pwdサブシェル)は
        # fast-not_connection経路にも課税されていた。slow-path(実際にpython3を
        # 起動する場合)の内側だけへ移す。
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
        local classify_script="${script_dir}/scripts/lib/guard14_db_trust_classify.py"
        if [[ -n "${BATS_TEST_FILENAME:-}" && -n "${GUARD14_BATS_CLASSIFY_SCRIPT:-}" ]]; then
            classify_script="$GUARD14_BATS_CLASSIFY_SCRIPT"
        fi
        if [[ -n "${BATS_TEST_FILENAME:-}" && -n "${GUARD14_BATS_COMMAND+x}" ]]; then
            COMMAND="$command" python3 -S "$classify_script" 2>/dev/null
        else
            HOOK_PAYLOAD_JSON="$payload" python3 -S "$classify_script" 2>/dev/null
        fi
    else
        echo "not_connection"
    fi
}
