#!/usr/bin/env bash
# semantic-links: [[掲示板通信基盤]]
# bulletin_write.sh — 全エージェント共有掲示板への書込み
# Usage: bash scripts/bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]
#    or: bash scripts/bulletin_write.sh <content> [requires_confirmation] [action_type]

set -euo pipefail

_BULLETIN_SELF="${BASH_SOURCE[0]:-$0}"
[[ "$_BULLETIN_SELF" = /* ]] || _BULLETIN_SELF="$PWD/$_BULLETIN_SELF"
_BULLETIN_ROOT="${_BULLETIN_SELF%/scripts/bulletin_write.sh}"
BULLETIN_WRITE_TOTAL_T0_US="${EPOCHREALTIME/./}"
BULLETIN_WRITE_TOTAL_T0_US="${BULLETIN_WRITE_TOTAL_T0_US:0:16}"
DEFENSE_OVERHEAD_REPO_ROOT="${DEFENSE_OVERHEAD_REPO_ROOT:-${BULLETIN_ROOT_OVERRIDE:-$_BULLETIN_ROOT}}"
if [[ -f "$_BULLETIN_ROOT/scripts/lib/defense_overhead_writer.sh" ]]; then
    source "$_BULLETIN_ROOT/scripts/lib/defense_overhead_writer.sh"
else
    defense_overhead_write_async() { return 0; }
fi
BULLETIN_WRITE_TOTAL_RECORDED=0
bulletin_write_record_total() {
    local rc="${1:-0}" now_us wall_ms verdict
    [[ "${BULLETIN_WRITE_TOTAL_RECORDED:-0}" -eq 0 ]] || return 0
    BULLETIN_WRITE_TOTAL_RECORDED=1
    now_us="${EPOCHREALTIME/./}"
    now_us="${now_us:0:16}"
    wall_ms=$(( (now_us - BULLETIN_WRITE_TOTAL_T0_US + 999) / 1000 ))
    verdict=PASS
    [[ "$rc" -eq 0 ]] || verdict=FAIL
    defense_overhead_write_async bulletin_write bulletin_write_total "$wall_ms" "$verdict" \
        "bulletin-write-${BASHPID}-${BULLETIN_WRITE_TOTAL_T0_US}" || true
}
bulletin_write_total_on_exit() { local rc=$?; bulletin_write_record_total "$rc"; return "$rc"; }
trap bulletin_write_total_on_exit EXIT

# ── Fast-path: no-args before SCRIPT_DIR/source ──────────────────────────────
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${2:-}" == "-h" || "${2:-}" == "--help" ]]; then
    echo "Usage: bash scripts/bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]"
    echo "    or: bash scripts/bulletin_write.sh <content> [requires_confirmation] [action_type]"
    exit 0
fi
if [[ $# -lt 1 ]]; then
    echo "Usage: bash scripts/bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]" >&2
    exit 1
fi

SCRIPT_DIR="${BULLETIN_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/escalation_evidence.sh"
BULLETIN_FILE="$SCRIPT_DIR/queue/bulletin_board.yaml"
LOCK_FILE="${BULLETIN_FILE}.lock"
AGENT_CONFIG="$SCRIPT_DIR/scripts/lib/agent_config.sh"
NOTIFY_FAILURE_LOG="${BULLETIN_NOTIFY_FAILURE_LOG:-$SCRIPT_DIR/logs/bulletin_notify_failures.yaml}"
NOTIFY_RETRIES="${BULLETIN_NOTIFY_RETRIES:-3}"
NOTIFY_RETRY_DELAY_SECONDS="${BULLETIN_NOTIFY_RETRY_DELAY_SECONDS:-0}"

if ! [[ "$NOTIFY_RETRIES" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: BULLETIN_NOTIFY_RETRIES must be a positive integer: $NOTIFY_RETRIES" >&2
    exit 1
fi

if ! [[ "$NOTIFY_RETRY_DELAY_SECONDS" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "ERROR: BULLETIN_NOTIFY_RETRY_DELAY_SECONDS must be a non-negative number: $NOTIFY_RETRY_DELAY_SECONDS" >&2
    exit 1
fi

KNOWN_AGENTS_RAW=""
if [[ -f "$AGENT_CONFIG" ]]; then
    # shellcheck disable=SC1090
    source "$AGENT_CONFIG"
    KNOWN_AGENTS_RAW="$(get_allowed_targets)"
fi

if [[ -z "$KNOWN_AGENTS_RAW" ]]; then
    KNOWN_AGENTS_RAW="shogun karo gunshi $(get_ninja_names 2>/dev/null || echo 'hayate kagemaru hanzo saizo kotaro tobisaru')"
fi

is_known_agent() {
    local candidate="$1"
    local agent=""
    for agent in $KNOWN_AGENTS_RAW; do
        [[ "$agent" == "$candidate" ]] && return 0
    done
    return 1
}

# System actors are durable producers, not human agents.  Keep this allowlist
# separate from get_allowed_targets so a producer can be persisted as the
# posted_by identity without becoming a valid inbox destination or being
# mistaken for a human commander.
is_system_actor() {
    case "$1" in
        gate_context_freshness|ninja_monitor) return 0 ;;
        *) return 1 ;;
    esac
}

is_known_poster() {
    is_known_agent "$1" || is_system_actor "$1"
}

normalize_csv_agents() {
    local raw="$1"
    local field_name="$2"
    local token=""
    local trimmed=""
    local normalized=()
    local joined=""
    local old_ifs="$IFS"
    local i=0
    declare -A seen=()

    IFS=',' read -ra _bw_tokens <<< "$raw"
    IFS="$old_ifs"
    for token in "${_bw_tokens[@]}"; do
        trimmed="${token#"${token%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        [[ -z "$trimmed" ]] && continue
        if ! is_known_agent "$trimmed"; then
            echo "ERROR: unknown ${field_name} agent: $trimmed" >&2
            return 1
        fi
        if [[ -z "${seen[$trimmed]+x}" ]]; then
            normalized+=("$trimmed")
            seen["$trimmed"]=1
        fi
    done

    if [[ ${#normalized[@]} -eq 0 ]]; then
        printf '\n'
        return 0
    fi

    joined="${normalized[0]}"
    for ((i = 1; i < ${#normalized[@]}; i++)); do
        joined+=",${normalized[$i]}"
    done
    printf '%s\n' "$joined"
}

normalize_confirmation_arg() {
    local raw="$1"
    local lowered="${raw,,}"
    case "$lowered" in
        ""|1|true|yes|y|0|false|no|n)
            printf '%s\n' "$raw"
            ;;
        *)
            normalize_csv_agents "$raw" "requires_confirmation"
            ;;
    esac
}

normalize_action_type() {
    local raw="${1:-info}"
    local lowered="${raw,,}"
    case "$lowered" in
        ""|info)
            printf '%s\n' "info"
            ;;
        action_required)
            printf '%s\n' "action_required"
            ;;
        escalation)
            printf '%s\n' "escalation"
            ;;
        *)
            echo "ERROR: invalid action_type: $raw (expected info or action_required)" >&2
            return 1
            ;;
    esac
}

gunshi_action_required_content() {
    local poster="$1"
    local content="$2"

    [[ "$poster" == "gunshi" ]] || return 1
    [[ "$content" =~ (穴発見|構造的穴|未自動化|自動化ターゲット|改善提案|GP提案|future[[:space:]]+fix|対応必要|要対応) ]] || return 1
    [[ "$content" =~ (gate|ゲート|自動化|cmd|CMD|修正|対応|起票|実装|追加) ]] || return 1
    return 0
}

# ── cmd_karo_impl_commander_post_contract_20260727: 指揮官発信投稿の構造強制 ──
is_commander_poster() {
    case "$1" in
        karo|gunshi|shogun) return 0 ;;
        *) return 1 ;;
    esac
}

post_has_numeric_claim() {
    # half-width [0-9] or full-width [０-９]。
    # 主張としての件数・率・母集団のみを対象とし、識別子(cmd_id/msg_id/日付/
    # 時刻/SHA/行番号/バージョン番号)内の数字は「数値主張」ではないため除去する。
    # cmd_karo_impl_commander_post_contract_20260727 是正2点目(軍師draft REQUEST_CHANGES)。
    local stripped="$1"
    # 識別子トークン(cmd_/msg_/blt_等のprefix付きID)
    stripped="$(printf '%s' "$stripped" | sed -E 's/\b(cmd|msg|blt|task|rpt|LK|LG|LS|GP|PD|IB)[A-Za-z0-9_-]*//g')"
    # ISO日付 (2026-07-27等)
    stripped="$(printf '%s' "$stripped" | sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2}//g')"
    # 時刻 (09:06:35 / 09:06等)
    stripped="$(printf '%s' "$stripped" | sed -E 's/[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?//g')"
    # 行番号参照 (:229 / L229 / 行229)
    stripped="$(printf '%s' "$stripped" | sed -E 's/([:Ll行])[0-9]+/\1/g')"
    # git SHA (7-40桁hex) — \bはマルチバイト境界で効かないため除去
    stripped="$(printf '%s' "$stripped" | sed -E 's/[0-9a-f]{7,40}//g')"
    # バージョン番号 (v1.2.3 / 2.16.0 / v4.55) — \bはマルチバイト境界で効かないため除去
    stripped="$(printf '%s' "$stripped" | sed -E 's/v?[0-9]+(\.[0-9]+){1,2}//g')"
    # 言語的数量表現(1-2桁+語彙助数詞: 8パターン/2問/1つ/3例/2語)は計測主張ではない
    # (殿裁定2026-07-29 03:48「blockはゲートのバグだ」— Q6回答が3連続FP BLOCKされた実測への是正。
    #  件/率/%/ms/s等の計測単位は残す=真の数値報告への3点セット要求は不変)
    stripped="$(printf '%s' "$stripped" | sed -E 's/[0-9]{1,2}(パターン|問|つ|例|語)//g')"
    # WBSレーン識別子(S1-S3/A1-A4/B1-B3b/B3.5/A0-4b等)は構造参照であり数値主張ではない
    # (殿裁定2026-08-03「blockがバグではないか」— 軍師レビュー回答でS3がFP BLOCKされた)
    # 複合ID(B3.5/A0-4b/A0-2p等)はドット・ハイフン接続の数字+接尾辞を再帰的に除去
    # H/h追加: h1b/h2/h2b/h3等のrecon偵察レーン識別子の偽陽性解消 (INS-20260807 軍師D0)
    stripped="$(printf '%s' "$stripped" | sed -E 's/[SABCDEHsabcdeh][0-9]{1,2}([.\-][0-9]{1,2}[a-z]?)*[a-z]?//g')"
    # RC番号(RC1/RC2/RC3等)・SG-PRE番号(SG-PRE35等)・AC番号(AC1-AC8等)は構造参照
    stripped="$(printf '%s' "$stripped" | sed -E 's/(RC|SG-PRE|AC|PRE)[0-9]{1,3}//gi')"
    # 終了コード参照(rc=2/exit 1等)は技術参照であり数値主張ではない
    stripped="$(printf '%s' "$stripped" | sed -E 's/(rc|exit)[[:space:]]*[=:][[:space:]]*[0-9]+//gi')"
    # cmd prefix付きIDのスラッシュ区切り裸数字(cmd_4337/4336)は識別子の一部
    stripped="$(printf '%s' "$stripped" | sed -E 's|/[0-9]{3,6}([^0-9])|/\1|g; s|/[0-9]{3,6}$|/|g')"
    # 「N件」の0件は空集合の表明であり計測主張ではない(件は計測単位として残すが0は計測値ではない)
    stripped="$(printf '%s' "$stripped" | sed -E 's/0件//g')"
    printf '%s' "$stripped" | grep -qP '[0-9０-９]'
}

# 3点セット(4規律サブセット): 集計コマンド/出力行の生貼付/1件の定義
# 検出語彙は07:55以降に家老/軍師/将軍が実際に掲示板で使用した表記を
# grepで洗い出して確定した(観測1文言だけから作らない — cmd_karo_impl_commander_post_contract_20260727 是正3点目)。
# 実測: bash bulletin_write.sh (中略) 実行時に『出力行(生):』表記がBLOCKされる偽陽性を家老/軍師/将軍が確認。
# 欠落要素名を配列で返す(stdout, 改行区切り)。空出力=全て充足。
commander_three_point_missing() {
    local content="$1"
    printf '%s' "$content" | grep -qP '集計コマンド' \
        || echo "集計コマンド"
    printf '%s' "$content" | grep -qP '(出力行\s*[\(（]生[\)）]|出力行の生貼付|出力行:|生貼付|貼付.*出力|出力.*貼付)' \
        || echo "出力行の生貼付"
    printf '%s' "$content" | grep -qP '(1件の定義|1件は|1件とは|1件=)' \
        || echo "1件の定義"
}

# 3点セットは見出しの存在だけでは証拠にならない。一方、掲示板の読者は
# 将軍・家老・軍師に限られるため、コマンド内容の良否は機械判定しない。
# 回転速度を落とさず、明白な空欄・プレースホルダだけを静的に拒否する。
commander_three_point_invalid() {
    local content="$1"
    local command_part=""
    local output_part=""
    local definition_part=""
    local command_re='集計コマンド[[:space:]]*[:：=][[:space:]]*([^。；;[:cntrl:]]+)'
    local output_re='(出力行[[:space:]]*[(（]生[)）]|出力行の生貼付|出力行|生貼付)[[:space:]]*[:：=][[:space:]]*([^。；;[:cntrl:]]+)'
    local definition_re='(1件の定義[[:space:]]*[:：=]|1件は|1件とは|1件=)[[:space:]]*([^。；;[:cntrl:]]+)'

    [[ "$content" =~ $command_re ]] && command_part="${BASH_REMATCH[1]}"

    if [[ -z "${command_part//[[:space:]。；;]/}" ]] \
        || [[ "$command_part" =~ ^[[:space:]]*(なし|不明|N/?A|TODO|TBD|省略|同上)[[:space:]]*$ ]]; then
        echo "集計コマンドの値が空またはプレースホルダ"
    fi

    [[ "$content" =~ $output_re ]] && output_part="${BASH_REMATCH[2]}"
    if [[ -z "${output_part//[[:space:]]/}" ]] \
        || [[ "$output_part" =~ ^[[:space:]]*(なし|不明|N/?A|TODO|TBD|省略|同上)[[:space:]]*$ ]]; then
        echo "出力行の値が空またはプレースホルダ"
    fi

    [[ "$content" =~ $definition_re ]] && definition_part="${BASH_REMATCH[2]}"
    if [[ -z "${definition_part//[[:space:]]/}" ]] \
        || [[ "$definition_part" =~ ^[[:space:]]*(なし|不明|N/?A|TODO|TBD|省略|同上|1件)[[:space:]]*$ ]]; then
        echo "1件の定義が空またはプレースホルダ"
    fi
}

# レビュー/相談の依頼は計測結果そのものではない。本文に版番号・件数・節番号が
# 含まれても、受け手へ検分を求める途中laneへ最終報告用3点セットを課さない。
# 関連宣言(AC3)は引き続き必須なので、無関係な在庫投稿の迂回には使えない。
commander_post_is_review_request() {
    local content="$1"
    printf '%s' "$content" | grep -qP '(レビュー依頼|レビューして|検分されたし|相談依頼|照会依頼)'
}

# 現在指示との関連宣言(cmd_id/下知)の有無。
# 実害進行中の緊急阻止は固定マーカー [URGENT-HARM] を本文先頭行に含む場合のみ例外とする。
# cmd_karo_impl_commander_post_contract_20260727 是正2点目: 曖昧なキーワード一致(実害進行中/緊急阻止等)は
# 忍者裁量で言い回しが増減し検査の再現性・被ガード性が保てないため固定マーカーへ一本化した。
# 是正4点目: 検出語彙は queue/bulletin_board.yaml + inbox archive を実測grepし、
# 実際に使用実績のある表記のみを採用した(候補1語からの決め打ち禁止 — 3点目と同じ原則)。
# 実測(2026-07-27): 下知13/下問4/裁定34/指示25(bulletin_board.yaml)、
#                    下命3/御下知1/御下問3/仰せ2/沙汰2/指図2(inbox archive)。10語すべて実使用ありのため全採用。
# CLAUDE.md Step 8/Q6が掲示板投稿を明示指定する起動時義務投稿(自己検証)。
# CLAUDE.mdの指示自体が関連宣言であり、内容は計測報告ではないためAC2/AC3双方を免除する
# (殿裁定2026-07-29 03:48「blockはゲートのバグだ」— Q6回答3連続FP BLOCKの是正。
#  先頭固定プレフィックスのみ=本文中の言及では発火しない)
is_startup_verification_post() {
    local first_line="${1%%$'\n'*}"
    # Q6回答/Q6検証/Q6第三者検証 — 全て起動時義務投稿またはその応答
    # 旧: Q6回答:* のみ → Q6回答(将軍/clear復帰): や Q6第三者検証 がBLOCKされる偽陽性を根治
    [[ "$first_line" == Q6* || "$first_line" == 洗脳チェック回答* ]]
}

commander_post_has_related_declaration() {
    local content="$1"
    local first_line="${content%%$'\n'*}"
    [[ "$first_line" == *'[URGENT-HARM]'* ]] && return 0
    is_startup_verification_post "$content" && return 0
    printf '%s' "$content" | grep -qP 'cmd_[A-Za-z0-9_]+' && return 0
    printf '%s' "$content" | grep -qP '(下知|下問|下命|御下知|御下問|仰せ|沙汰|指図|裁定|指示)' && return 0
    # 将軍review_request/review_designへの応答(設計書独立レビュー等)。
    # 実測(2026-08-03): 独立レビュー6件が最多。cmd_idを自然に含まない正当投稿がBLOCKされるバグ是正。
    printf '%s' "$content" | grep -qP '独立レビュー' && return 0
    return 1
}

compute_notify_targets() {
    local posted_by="$1"
    local raw_targets=""
    local token=""
    local normalized=()
    local i=0
    local joined=""
    declare -A seen=()

    if [[ -n "${BULLETIN_NOTIFY:-}" ]]; then
        raw_targets="$BULLETIN_NOTIFY"
    else
        raw_targets="shogun,karo,gunshi"
    fi

    IFS=',' read -ra _bw_nt_tokens <<< "$raw_targets"
    for token in "${_bw_nt_tokens[@]}"; do
        token="${token#"${token%%[![:space:]]*}"}"
        token="${token%"${token##*[![:space:]]}"}"
        [[ -z "$token" ]] && continue
        [[ "$token" == "$posted_by" ]] && continue
        if [[ -z "${seen[$token]+x}" ]]; then
            normalized+=("$token")
            seen["$token"]=1
        fi
    done

    if [[ ${#normalized[@]} -eq 0 ]]; then
        printf '\n'
        return 0
    fi

    joined="${normalized[0]}"
    for ((i = 1; i < ${#normalized[@]}; i++)); do
        joined+=",${normalized[$i]}"
    done
    printf '%s\n' "$joined"
}

POSTED_BY=""
if [[ $# -ge 2 ]] && is_known_poster "$1"; then
    POSTED_BY="$1"
else
    if [[ -n "${TMUX_PANE:-}" ]]; then
        POSTED_BY="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
    fi
    if [[ -z "$POSTED_BY" ]]; then
        POSTED_BY="$(tmux display-message -p '#{@agent_id}' 2>/dev/null || true)"
    fi
    if [[ -z "$POSTED_BY" ]]; then
        POSTED_BY=""
    fi
fi

# Usage: bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]
# posted_by is $1 (explicit), content is $2, requires_confirmation is $3
# posted_byはtmuxからも取得するが、引数で明示されたものを優先(互換性)
if [[ $# -ge 2 ]]; then
    # 新形式: bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]
    POSTED_BY_ARG="$1"
    CONTENT="$2"
    REQUIRES_CONFIRMATION="${3:-false}"
    ACTION_TYPE="${4:-info}"
    # posted_byが既知エージェント名なら引数を信頼
    if is_known_poster "$POSTED_BY_ARG"; then
        POSTED_BY="$POSTED_BY_ARG"
    else
        if [[ -z "$POSTED_BY" ]]; then
            echo "ERROR: agent_id unavailable from tmux; use explicit posted_by argument" >&2
            exit 1
        fi
        # 第1引数がエージェント名でない→旧形式(content, requires_confirmation)
        CONTENT="$1"
        REQUIRES_CONFIRMATION="${2:-false}"
        ACTION_TYPE="${3:-info}"
    fi
else
    if [[ -z "$POSTED_BY" ]]; then
        echo "ERROR: agent_id unavailable from tmux; use explicit posted_by argument" >&2
        exit 1
    fi
    CONTENT="$1"
    REQUIRES_CONFIRMATION="false"
    ACTION_TYPE="info"
fi

# 引数順序ミス検出: contentがエージェント名そのもの=引数の置き間違い(blt_20260416_230053事故: content='karo')
if is_known_poster "$CONTENT"; then
    echo "ERROR: content is an agent name ('$CONTENT') — argument order mistake. Usage: bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]" >&2
    exit 1
fi

# GP-207: contentがエージェント名のみの場合はBLOCK(引数順序ミス検出)
if is_known_poster "$CONTENT"; then
    echo "BLOCK: contentがエージェント名のみ。引数順序ミスの可能性。Usage: bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]" >&2
    exit 1
fi

REQUIRES_CONFIRMATION="$(normalize_confirmation_arg "$REQUIRES_CONFIRMATION")"
ACTION_TYPE="$(normalize_action_type "$ACTION_TYPE")"
if [[ "$ACTION_TYPE" == "info" ]] && gunshi_action_required_content "$POSTED_BY" "$CONTENT"; then
    ACTION_TYPE="action_required"
fi

# Escalation messages must carry the self-trial receipt before bulletin or
# notification persistence.  BLOCK/FAIL prose in other action types is not
# rejected (cmd_4251 review ruling).
if ! escalation_evidence_validate_or_block bulletin_write "$ACTION_TYPE" "$CONTENT"; then
    exit 2
fi

# 【家老D0止血 2026-07-27 09:05・実害進行中の緊急阻止・影丸へ引継ぎ前提】
# スクリプトが自動生成する定型通知(review_approval.sh:291 等)は人が本文を書けないため、
# AC2/AC3の検査対象から除外する。除外しないと構造的に必ずBLOCKし、
# レビュー承認→家老通知の経路が全面停止する(軍師実測 2026-07-27 09:03)。
# 呼び出し元が BULLETIN_AUTOGEN=1 を明示した場合のみ免除。既定(未設定)は検査ありのまま。
if [[ "${BULLETIN_AUTOGEN:-0}" != "1" ]]; then
    # AC2: 指揮官発信+数値主張 → 3点セット必須(起動時義務投稿=自己検証は免除)
    if is_commander_poster "$POSTED_BY" \
        && [[ "$ACTION_TYPE" != "escalation" ]] \
        && ! is_startup_verification_post "$CONTENT" \
        && ! commander_post_is_review_request "$CONTENT" \
        && post_has_numeric_claim "$CONTENT"; then
        _cmd_missing_elements="$(commander_three_point_missing "$CONTENT")"
        if [[ -n "$_cmd_missing_elements" ]]; then
            echo "BLOCK: 指揮官(${POSTED_BY})発信の数値含み投稿に3点セットの欠落要素あり: $(printf '%s' "$_cmd_missing_elements" | tr '\n' ',' | sed 's/,$//')" >&2
            exit 1
        fi
        _cmd_invalid_elements="$(commander_three_point_invalid "$CONTENT")"
        if [[ -n "$_cmd_invalid_elements" ]]; then
            echo "BLOCK: 指揮官(${POSTED_BY})発信の数値含み投稿の証拠内容が不正: $(printf '%s' "$_cmd_invalid_elements" | tr '\n' ',' | sed 's/,$//')" >&2
            exit 1
        fi
    fi

    # AC3: 指揮官発信投稿は現在指示との関連宣言(cmd_id/下知)を必須化
    if is_commander_poster "$POSTED_BY" \
        && [[ "$ACTION_TYPE" != "escalation" ]] \
        && ! commander_post_has_related_declaration "$CONTENT"; then
        echo "BLOCK: 指揮官(${POSTED_BY})発信投稿に現在指示との関連宣言(cmd_id/下知)がありません。insight_write.sh で在庫化せよ。実害進行中なら本文先頭行に [URGENT-HARM] を付けて再送せよ。" >&2
        exit 1
    fi
fi

if [[ -n "${BULLETIN_NOTIFY:-}" ]]; then
    BULLETIN_NOTIFY="$(normalize_csv_agents "$BULLETIN_NOTIFY" "BULLETIN_NOTIFY")"
fi
NOTIFY_TARGETS_CSV="$(compute_notify_targets "$POSTED_BY")"

DATE_FIELDS="$(date '+%Y-%m-%dT%H:%M:%S %s%N %Y%m%d_%H%M%S')"
read -r POSTED_AT DATE_NANOS ENTRY_STAMP <<< "$DATE_FIELDS"
HASH_RESULT="$(printf '%s' "${DATE_NANOS}${POSTED_BY}${CONTENT}" | sha1sum)"
RAND_SUFFIX="${HASH_RESULT:0:6}"
ENTRY_ID="blt_${ENTRY_STAMP}_${RAND_SUFFIX}"
LEDGER_WRITER="$SCRIPT_DIR/scripts/ledger_writer.sh"
if [[ -f "$LEDGER_WRITER" && ! -x "$LEDGER_WRITER" ]]; then
    printf '%s\n' 'LEDGER-ROUTE-SKIP: ledger_writer.sh exists but not executable' >&2
fi
LEDGER_ENTRY_FILE="$(mktemp)"
trap 'rm -f -- "$LEDGER_ENTRY_FILE"' EXIT
ledger_append() {
    if [[ -x "$LEDGER_WRITER" ]]; then
        LEDGER_SOURCE_FILE="$BULLETIN_FILE" bash "$LEDGER_WRITER" append bulletin "$LEDGER_ENTRY_FILE" >/dev/null
    else
        [[ -s "$BULLETIN_FILE" ]] || printf 'entries:\n' > "$BULLETIN_FILE"
        cat "$LEDGER_ENTRY_FILE" >> "$BULLETIN_FILE"
    fi
}

mkdir -p "${BULLETIN_FILE%/*}"

WRITE_RESULT="$({
    flock -x 200

    # ── GP-210: Dedup check (Python3-lite: sys/os only, no yaml import) ─────────
    _bw_need_dedup_check=0
    if [[ -f "$BULLETIN_FILE" && -s "$BULLETIN_FILE" ]]; then
        if [[ "$CONTENT" == *$'\n'* ]] || grep -Fq -- "$CONTENT" "$BULLETIN_FILE"; then
            _bw_need_dedup_check=1
        fi
    fi
    if [[ "$_bw_need_dedup_check" == "1" ]]; then
        _bw_dedup_result="$(python3 - "$BULLETIN_FILE" "$POSTED_BY" "$CONTENT" <<'PY'
import sys, os
bf, poster, content_target = sys.argv[1], sys.argv[2], sys.argv[3].strip()
if not os.path.exists(bf):
    sys.exit(0)
lines = open(bf, encoding='utf-8').read().splitlines()
in_content = False
cur_lines = []
cur_poster = None
cur_id = None
def check():
    if cur_poster == poster:
        c = '\n'.join(cur_lines).strip()
        if c == content_target:
            print(f"DEDUP: 同一内容の掲示板エントリが既存 ({cur_id})")
            sys.exit(0)
for line in lines:
    if line.startswith('- id:'):
        check()
        cur_id = line[7:-1].replace("''", "'") if line.endswith("'") else line[7:]
        in_content = False; cur_lines = []; cur_poster = None
    elif line == '  content: |-':
        in_content = True
    elif in_content and line.startswith('    '):
        cur_lines.append(line[4:])
    elif in_content:
        in_content = False
        if line.startswith("  posted_by: '"):
            raw = line[14:]
            cur_poster = (raw[:-1] if raw.endswith("'") else raw).replace("''", "'")
    elif line.startswith("  posted_by: '"):
        raw = line[14:]
        cur_poster = (raw[:-1] if raw.endswith("'") else raw).replace("''", "'")
check()
PY
)"
        if [[ "$_bw_dedup_result" == DEDUP:* ]]; then
            printf '%s\n' "$_bw_dedup_result"
            exit 0
        fi
    fi

    # ── Write new entry (bash-only, prepend — no yaml import) ───────────────────
    _bw_sq() { printf '%s' "${1//\'/\'\'}"; }
    _bw_stripped_content="${CONTENT%$'\n'}"

    {
        printf '%s\n' "- id: '$(_bw_sq "$ENTRY_ID")'"
        printf "  content: |-\n"
        while IFS= read -r _bw_line; do
            printf "    %s\n" "$_bw_line"
        done <<< "$_bw_stripped_content"
        printf "  posted_by: '%s'\n" "$(_bw_sq "$POSTED_BY")"
        printf "  posted_at: '%s'\n" "$(_bw_sq "$POSTED_AT")"
        case "${REQUIRES_CONFIRMATION,,}" in
            ""|0|false|no|n) printf "  requires_confirmation: false\n" ;;
            1|true|yes|y)    printf "  requires_confirmation: true\n" ;;
            *)
                printf "  requires_confirmation:\n"
                IFS=',' read -ra _bw_rc_agents <<< "$REQUIRES_CONFIRMATION"
                for _bw_rc_a in "${_bw_rc_agents[@]}"; do
                    _bw_rc_a="${_bw_rc_a#"${_bw_rc_a%%[![:space:]]*}"}"
                    _bw_rc_a="${_bw_rc_a%"${_bw_rc_a##*[![:space:]]}"}"
                    [[ -n "$_bw_rc_a" ]] && printf "    - '%s'\n" "$(_bw_sq "$_bw_rc_a")"
                done
                ;;
        esac
        printf "  action_type: '%s'\n" "$(_bw_sq "$ACTION_TYPE")"
        printf "  actioned_by: ''\n"
        if [[ -n "$NOTIFY_TARGETS_CSV" ]]; then
            printf "  notify_targets:\n"
            IFS=',' read -ra _bw_nt_agents <<< "$NOTIFY_TARGETS_CSV"
            for _bw_nt_a in "${_bw_nt_agents[@]}"; do
                [[ -n "$_bw_nt_a" ]] && printf "    - '%s'\n" "$(_bw_sq "$_bw_nt_a")"
            done
        else
            printf "  notify_targets: []\n"
        fi
        printf "  confirmed_by: []\n"
        printf "  status: 'open'\n"
    } > "$LEDGER_ENTRY_FILE"

    printf '%s\n' "$ENTRY_ID"

} 200>"$LOCK_FILE")"

if [[ "$WRITE_RESULT" == DEDUP:* ]]; then
    printf '%s\n' "$WRITE_RESULT"
    exit 0
fi

printf '%s\n' "$WRITE_RESULT"

ledger_append

MEMORY_DB_LIVE_INSERT="$SCRIPT_DIR/scripts/memory_db_live_insert_async.py"
if [[ ! -f "$MEMORY_DB_LIVE_INSERT" ]]; then
    MEMORY_DB_LIVE_INSERT="$SCRIPT_DIR/scripts/memory_db_live_insert.py"
fi
if [[ -f "$MEMORY_DB_LIVE_INSERT" ]]; then
    _memory_db_insert_cmd=(
        python3 "$MEMORY_DB_LIVE_INSERT" bulletin
        --entry-id "$WRITE_RESULT" \
        --ts "$POSTED_AT" \
        --agent "$POSTED_BY" \
        --content "$CONTENT" \
        --requires-confirmation "$REQUIRES_CONFIRMATION" \
        --action-type "$ACTION_TYPE" \
        --actioned-by "" \
        --status "open" \
        --source-file "$BULLETIN_FILE"
    )
    if [[ "${MEMORY_DB_LIVE_INSERT_SYNC:-0}" == "1" || -n "${SHOGUN_MEMORY_DB:-}" || ( "$SCRIPT_DIR" != /mnt/c/* && "$SCRIPT_DIR" != /mnt/d/* ) ]]; then
        "${_memory_db_insert_cmd[@]}" >/dev/null 2>&1 || true
    else
        "${_memory_db_insert_cmd[@]}" >/dev/null 2>&1 &
        disown 2>/dev/null || true
    fi
fi

if [[ -f "$BULLETIN_FILE" && -x "$SCRIPT_DIR/scripts/bulletin_archive.sh" ]]; then
    ENTRY_COUNT="$(awk '/^- id: / {count++} END {print count + 0}' "$BULLETIN_FILE")"
    if [[ "$ENTRY_COUNT" -gt 50 ]]; then
        bash "$SCRIPT_DIR/scripts/bulletin_archive.sh" --max-keep 30 >/dev/null 2>&1 || true
    fi
fi

if [[ -x "$SCRIPT_DIR/scripts/yaml_auto_archive.sh" ]]; then
    if [[ "${BULLETIN_AUTO_ARCHIVE_SYNC:-0}" == "1" ]]; then
        SHOGUN_ROOT="$SCRIPT_DIR" bash "$SCRIPT_DIR/scripts/yaml_auto_archive.sh" >/dev/null 2>&1 || true
    else
        (SHOGUN_ROOT="$SCRIPT_DIR" bash "$SCRIPT_DIR/scripts/yaml_auto_archive.sh" >/dev/null 2>&1 || true) &
        disown 2>/dev/null || true
    fi
fi

# --- 投稿者以外に自動通知 ---
INBOX_WRITE="${BULLETIN_INBOX_WRITE:-$SCRIPT_DIR/scripts/inbox_write.sh}"
if [[ -f "$INBOX_WRITE" ]]; then
    # BULLETIN_NOTIFY: 環境変数で通知先を限定可能(カンマ区切り)
    # 未指定時は将軍+家老+軍師の全3者
    if [[ -n "$NOTIFY_TARGETS_CSV" ]]; then
        IFS=',' read -ra NOTIFY_TARGETS <<< "$NOTIFY_TARGETS_CSV"
    else
        NOTIFY_TARGETS=()
    fi
    # GP-208: 掲示板全文をinboxに含める。80文字要約→全文。
    # 理由: 通知だけでは読みに行く行動は強制できない。
    # inboxを読む行動は既に強制されている(startup gate+stop hook)。
    # その中に全文があれば、別途掲示板を読みに行く必要がない。
    notify_failed=0

    record_notify_failure() {
        local target="$1"
        local attempts="$2"
        local recorded_at
        recorded_at="$(date '+%Y-%m-%dT%H:%M:%S %z')"
        mkdir -p "${NOTIFY_FAILURE_LOG%/*}"
        {
            flock -x 201
            {
                printf '%s\n' "- entry_id: '$ENTRY_ID'"
                printf "  posted_by: '%s'\n" "${POSTED_BY//\'/\'\'}"
                printf "  target: '%s'\n" "${target//\'/\'\'}"
                printf "  attempts: %s\n" "$attempts"
                printf "  recorded_at: '%s'\n" "$recorded_at"
                printf "  content: |-\n"
                while IFS= read -r _failure_line; do
                    printf '    %s\n' "$_failure_line"
                done <<< "掲示板新規投稿($ENTRY_ID): ${CONTENT}"
            } >> "$NOTIFY_FAILURE_LOG"
        } 201>>"${NOTIFY_FAILURE_LOG}.lock"
    }

    notify_target() {
        local target="$1"
        local attempt=1
        while (( attempt <= NOTIFY_RETRIES )); do
            # 呼出元のtest/fixture用INBOX_WRITE_*を継承すると、掲示板は正本へ
            # 書けても通知だけ別rootへ逸脱する。通知rootはbulletin rootへ固定する。
            if INBOX_WRITE_ROOT_OVERRIDE="$SCRIPT_DIR" \
                INBOX_WRITE_TEST="${BULLETIN_INBOX_WRITE_TEST:-}" \
                bash "$INBOX_WRITE" "$target" \
                "掲示板新規投稿($ENTRY_ID): ${CONTENT}" \
                bulletin_notify bulletin_write bulletin_notify; then
                if ! pgrep -f "inbox_watcher.sh ${target}" >/dev/null 2>&1; then
                    echo "[bulletin_write] WARN: inbox_watcher not running for ${target} — nudge may be lost" >&2
                fi
                return 0
            fi
            if (( attempt < NOTIFY_RETRIES )) && [[ "$NOTIFY_RETRY_DELAY_SECONDS" != "0" ]]; then
                sleep "$NOTIFY_RETRY_DELAY_SECONDS"
            fi
            ((attempt++))
        done
        record_notify_failure "$target" "$NOTIFY_RETRIES"
        echo "[bulletin_write] ERROR: inbox_write failed for ${target} after ${NOTIFY_RETRIES} attempts — failure recorded in ${NOTIFY_FAILURE_LOG}" >&2
        return 1
    }

    for target in "${NOTIFY_TARGETS[@]}"; do
        if ! notify_target "$target"; then
            notify_failed=1
        fi
    done

    if (( notify_failed )); then
        echo "[bulletin_write] ERROR: bulletin notification delivery failed; bulletin entry ${ENTRY_ID} was written but command failed closed" >&2
        exit 1
    fi
fi
