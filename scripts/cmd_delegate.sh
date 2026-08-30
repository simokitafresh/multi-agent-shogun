#!/usr/bin/env bash
# semantic-links: [[gate迂回防止]]
# cmd_delegate.sh — cmd委任の原子的実行（将軍ワークフロー Step 3）
#
# Usage:
#   bash scripts/cmd_delegate.sh <cmd_id> "<message>"
#
# Example:
#   bash scripts/cmd_delegate.sh cmd_539 "cmd_539を書いた。配備せよ。"
#
# Behavior:
#   1. shogun_to_karo.yaml に cmd_id が存在し status=pending か検証
#   2. delegated_at 既存時は status/inbox/archive を照合し、冪等終了または安全に再通知
#   3. cmd_new 重複が既にあれば cmd_save.sh 前に BLOCK
#   4. 初回委任時のみ cmd_save.sh を自動実行。PASS(exit 0)時のみ次へ進む
#   5. status=delegated + delegated_at: <ISO8601> を cmd エントリに追加
#   6. inbox_write.sh karo "<msg>" cmd_new shogun を実行
#   7. 出力: DELEGATED: cmd_XXX at 2026-03-04T18:17:05
#
# Exit codes:
#   0 — 委任成功 or 既に委任済み
#   1 — エラー（cmd未発見/status不正/inbox_write失敗）

set -euo pipefail

# Round8 lane #0': complete entrypoint wall-clock telemetry.
CMD_DELEGATE_TOTAL_T0_US="${EPOCHREALTIME/./}"
CMD_DELEGATE_TOTAL_T0_US="${CMD_DELEGATE_TOTAL_T0_US:0:16}"
_CMD_DELEGATE_TOTAL_SELF="${BASH_SOURCE[0]:-$0}"
[[ "$_CMD_DELEGATE_TOTAL_SELF" = /* ]] || _CMD_DELEGATE_TOTAL_SELF="$PWD/$_CMD_DELEGATE_TOTAL_SELF"
_CMD_DELEGATE_TOTAL_ROOT="${_CMD_DELEGATE_TOTAL_SELF%/scripts/cmd_delegate.sh}"
DEFENSE_OVERHEAD_REPO_ROOT="${DEFENSE_OVERHEAD_REPO_ROOT:-$_CMD_DELEGATE_TOTAL_ROOT}"
# shellcheck source=scripts/lib/defense_overhead_writer.sh
source "$_CMD_DELEGATE_TOTAL_ROOT/scripts/lib/defense_overhead_writer.sh"
CMD_DELEGATE_TOTAL_RECORDED=0
cmd_delegate_record_total() {
    local rc="${1:-0}" now_us wall_ms verdict
    [ "${CMD_DELEGATE_TOTAL_RECORDED:-0}" -eq 0 ] || return 0
    CMD_DELEGATE_TOTAL_RECORDED=1
    now_us="${EPOCHREALTIME/./}"
    now_us="${now_us:0:16}"
    wall_ms=$(( (now_us - CMD_DELEGATE_TOTAL_T0_US + 999) / 1000 ))
    verdict=PASS
    [ "$rc" -eq 0 ] || verdict=FAIL
    defense_overhead_write_async cmd_delegate cmd_delegate_total "$wall_ms" "$verdict" \
        "cmd-delegate-${BASHPID}-${CMD_DELEGATE_TOTAL_T0_US}" || true
}
cmd_delegate_total_on_exit() { local rc=$?; cmd_delegate_record_total "$rc"; return "$rc"; }
trap cmd_delegate_total_on_exit EXIT

if [ "$#" -lt 2 ]; then
    echo "Usage: cmd_delegate.sh <cmd_id> \"<message>\"" >&2
    exit 1
fi

CMD_ID="$1"
MESSAGE="$2"

# 数字のみ指定をcmd_付きに正規化(cmd_save.shと同一規約。引数規約不一致FP修正 2026-06-10)
if [[ "$CMD_ID" =~ ^[0-9]+$ ]]; then
    CMD_ID="cmd_${CMD_ID}"
fi

if [[ "$MESSAGE" != *[![:space:]]* ]]; then
    echo "ERROR: message must contain non-whitespace content" >&2
    exit 1
fi

if [[ ! "$CMD_ID" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "ERROR: invalid cmd_id '$CMD_ID' (allowed: A-Z a-z 0-9 _ . -)" >&2
    exit 1
fi

if [ -n "${CMD_DELEGATE_SCRIPT_DIR:-}" ]; then
    SCRIPT_DIR="$CMD_DELEGATE_SCRIPT_DIR"
    PROJECT_DIR="${CMD_DELEGATE_PROJECT_DIR:-${SCRIPT_DIR%/scripts}}"
else
    _cmd_delegate_self="${BASH_SOURCE[0]}"
    [[ "$_cmd_delegate_self" != /* ]] && _cmd_delegate_self="$PWD/$_cmd_delegate_self"
    SCRIPT_DIR="${_cmd_delegate_self%/scripts/cmd_delegate.sh}"
    PROJECT_DIR="${SCRIPT_DIR%/scripts}"
    unset _cmd_delegate_self
fi
SHOGUN_TO_KARO="$PROJECT_DIR/queue/shogun_to_karo.yaml"
KARO_INBOX="$PROJECT_DIR/queue/inbox/karo.yaml"
DASHBOARD="$PROJECT_DIR/dashboard.md"
ARCHIVE_DIR="$PROJECT_DIR/queue/archive/cmds"
MEMORY_DB_LIVE_INSERT="${MEMORY_DB_LIVE_INSERT:-$PROJECT_DIR/scripts/memory_db_live_insert_async.py}"
if [[ ! -f "$MEMORY_DB_LIVE_INSERT" ]]; then
    MEMORY_DB_LIVE_INSERT="$PROJECT_DIR/scripts/memory_db_live_insert.py"
fi

if [ ! -f "$SHOGUN_TO_KARO" ]; then
    echo "ERROR: shogun_to_karo.yaml not found: $SHOGUN_TO_KARO" >&2
    exit 1
fi

# Source yaml_field_set for field get/set
# shellcheck source=/dev/null
source "$PROJECT_DIR/scripts/lib/yaml_field_set.sh"

find_undeployed_pending_cmds() {
    local yaml_file="$1"
    local current_cmd="$2"

    awk -v current_cmd="$current_cmd" '
function trim(s) {
    sub(/^[[:space:]]+/, "", s)
    sub(/[[:space:]]+$/, "", s)
    return s
}
function unquote(s) {
    s = trim(s)
    if (length(s) >= 2) {
        if (substr(s, 1, 1) == "\"" && substr(s, length(s), 1) == "\"") {
            s = substr(s, 2, length(s) - 2)
        } else if (substr(s, 1, 1) == "'"'"'" && substr(s, length(s), 1) == "'"'"'") {
            s = substr(s, 2, length(s) - 2)
        }
    }
    return trim(s)
}
function flush_block() {
    if (cmd_id != "" && cmd_id != current_cmd && status == "pending" && delegated_at != "") {
        print cmd_id " (delegated_at=" delegated_at ")"
    }
    cmd_id = ""
    status = ""
    delegated_at = ""
}
BEGIN {
    in_commands = 0
    cmd_id = ""
    status = ""
    delegated_at = ""
}
/^commands:[[:space:]]*$/ {
    in_commands = 1
    next
}
in_commands && $0 !~ /^[[:space:]]/ && $0 !~ /^$/ {
    flush_block()
    exit
}
in_commands && /^  - id:[[:space:]]*/ {
    flush_block()
    cmd_id = $0
    sub(/^  - id:[[:space:]]*/, "", cmd_id)
    cmd_id = unquote(cmd_id)
    next
}
in_commands && /^  [^[:space:]-][^:]*:[[:space:]]*$/ {
    flush_block()
    cmd_id = $0
    sub(/^  /, "", cmd_id)
    sub(/:[[:space:]]*$/, "", cmd_id)
    cmd_id = unquote(cmd_id)
    next
}
in_commands && /^    status:[[:space:]]*/ {
    status = $0
    sub(/^    status:[[:space:]]*/, "", status)
    status = unquote(status)
    next
}
in_commands && /^    delegated_at:[[:space:]]*/ {
    delegated_at = $0
    sub(/^    delegated_at:[[:space:]]*/, "", delegated_at)
    delegated_at = unquote(delegated_at)
    next
}
END {
    flush_block()
}
' "$yaml_file" 2>/dev/null || true
}

get_cmd_status_and_delegated() {
    local yaml_file="$1"
    local target_cmd="$2"

    awk -v target_cmd="$target_cmd" '
function trim(s) {
    sub(/^[[:space:]]+/, "", s)
    sub(/[[:space:]]+$/, "", s)
    return s
}
function unquote(s) {
    s = trim(s)
    if (length(s) >= 2) {
        if (substr(s, 1, 1) == "\"" && substr(s, length(s), 1) == "\"") {
            s = substr(s, 2, length(s) - 2)
        } else if (substr(s, 1, 1) == "'"'"'" && substr(s, length(s), 1) == "'"'"'") {
            s = substr(s, 2, length(s) - 2)
        }
    }
    return trim(s)
}
function flush_block() {
    if (cmd_id == target_cmd) {
        found = 1
        print status "\t" delegated_at
        exit 0
    }
    cmd_id = ""
    status = ""
    delegated_at = ""
}
BEGIN {
    in_commands = 0
    cmd_id = ""
    status = ""
    delegated_at = ""
    found = 0
}
/^commands:[[:space:]]*$/ {
    in_commands = 1
    next
}
in_commands && $0 !~ /^[[:space:]]/ && $0 !~ /^$/ {
    flush_block()
    exit
}
in_commands && /^  - id:[[:space:]]*/ {
    flush_block()
    cmd_id = $0
    sub(/^  - id:[[:space:]]*/, "", cmd_id)
    cmd_id = unquote(cmd_id)
    next
}
in_commands && /^  [^[:space:]-][^:]*:[[:space:]]*$/ {
    flush_block()
    cmd_id = $0
    sub(/^  /, "", cmd_id)
    sub(/:[[:space:]]*$/, "", cmd_id)
    cmd_id = unquote(cmd_id)
    next
}
in_commands && /^    status:[[:space:]]*/ {
    status = $0
    sub(/^    status:[[:space:]]*/, "", status)
    status = unquote(status)
    next
}
in_commands && /^    delegated_at:[[:space:]]*/ {
    delegated_at = $0
    sub(/^    delegated_at:[[:space:]]*/, "", delegated_at)
    delegated_at = unquote(delegated_at)
    next
}
END {
    if (!found) {
        flush_block()
    }
    if (!found) exit 2
}
' "$yaml_file"
}

inbox_has_cmd_new_for_cmd() {
    local inbox_file="$1"
    local cmd_id="$2"

    awk -v cmd_id="$cmd_id" '
function flush_block() {
    if (block_has_cmd && block_is_cmd_new) {
        found = 1
    }
}
function reset_block() {
    block_has_cmd = 0
    block_is_cmd_new = 0
    block_subject_seen = 0
}
BEGIN {
    reset_block()
}
/^-[[:space:]]/ || /^  -[[:space:]]/ {
    flush_block()
    reset_block()
}
{
    # 言及≠委任 (2026-08-22殿下知「品質バグによるblockは即時根治せよ」)。
    # 委任主語 = block本文で最初に現れるcmd_トークンのみ。任意位置の言及一致は
    # 別cmd委任文中の説明的言及(例: cmd_4367委任文中のcmd_4368)を誤検知する。
    if (!block_subject_seen) {
        line = $0
        if (match(line, /cmd_[A-Za-z0-9_]+/)) {
            block_subject_seen = 1
            if (substr(line, RSTART, RLENGTH) == cmd_id) {
                block_has_cmd = 1
            }
        }
    }
    if ($0 ~ /^[[:space:]]*type:[[:space:]]*['\''"]?cmd_new['\''"]?([[:space:]]|$)/) {
        block_is_cmd_new = 1
    }
}
END {
    flush_block()
    exit(found ? 0 : 1)
}
' "$inbox_file"
}

message_has_cmd_id() {
    local message="$1"
    local cmd_id="$2"

    awk -v cmd_id="$cmd_id" '
{
    remaining = $0
    offset = 0
    while ((pos = index(remaining, cmd_id)) > 0) {
        abs_pos = offset + pos
        before_char = (abs_pos > 1) ? substr($0, abs_pos - 1, 1) : ""
        after_char = substr($0, abs_pos + length(cmd_id), 1)
        if ((before_char == "" || before_char !~ /[A-Za-z0-9_]/) &&
            (after_char == "" || after_char !~ /[A-Za-z0-9_]/)) {
            found = 1
            exit
        }
        offset += pos
        remaining = substr(remaining, pos + 1)
    }
}
END {
    exit(found ? 0 : 1)
}
' <<< "$message"
}

build_notify_message() {
    local msg="$1" cmd_id="$2" body
    if message_has_cmd_id "$msg" "$cmd_id"; then
        body="$msg"
    else
        body="${cmd_id}: ${msg}"
    fi
    # 2026-08-30 20:36 将軍 D0: inbox_write の commander identity envelope(d9d036f10)を
    # cmd_new にも要求するようになり cmd_4422 の委任が BLOCK した。欠けていれば先頭に付与する。
    if [[ "$body" != *"task_id=commander_directive"* ]]; then
        body="task_id=commander_directive subject_task_id=${cmd_id} parent_cmd=${cmd_id} ${body}"
    fi
    printf '%s' "$body"
}

cmd_is_archived() {
    local cmd_id="$1"

    if [ ! -d "$ARCHIVE_DIR" ]; then
        return 1
    fi

    local nullglob_was_set=0
    if shopt -q nullglob; then
        nullglob_was_set=1
    fi
    shopt -s nullglob
    local archived_matches=("$ARCHIVE_DIR/${cmd_id}_"*)
    if [ "$nullglob_was_set" -eq 0 ]; then
        shopt -u nullglob
    fi
    [ "${#archived_matches[@]}" -gt 0 ]
}

validate_estimated_minutes() {
    local yaml_file="$1"
    local cmd_id="$2"
    python3 - "$yaml_file" "$cmd_id" <<'PY'
import sys
import yaml

path, cmd_id = sys.argv[1:]
data = yaml.safe_load(open(path, encoding="utf-8")) or {}
commands = data.get("commands", data)
if isinstance(commands, dict):
    command = commands.get(cmd_id)
elif isinstance(commands, list):
    command = next(
        (item for item in commands if isinstance(item, dict) and str(item.get("id")) == cmd_id),
        None,
    )
else:
    command = None
value = command.get("estimated_minutes") if isinstance(command, dict) else None
if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
    print(
        f"BLOCK: {cmd_id}.estimated_minutes must be a positive number before delegation "
        f"(actual={value!r})",
        file=sys.stderr,
    )
    raise SystemExit(1)
PY
}

cmd_state=$(get_cmd_status_and_delegated "$SHOGUN_TO_KARO" "$CMD_ID" 2>/dev/null) || {
    echo "ERROR: cmd_id '$CMD_ID' not found in shogun_to_karo.yaml" >&2
    exit 1
}
IFS=$'\t' read -r status existing_delegated <<< "$cmd_state"

if [ -n "$existing_delegated" ]; then
    if [ "$status" = "delegated" ]; then
        if cmd_is_archived "$CMD_ID"; then
            echo "BLOCK: $CMD_ID is already archived (completed). Cannot re-notify delegation." >&2
            exit 1
        fi
        if [ -f "$KARO_INBOX" ] && inbox_has_cmd_new_for_cmd "$KARO_INBOX" "$CMD_ID"; then
            echo "ALREADY_DELEGATED: $CMD_ID at $existing_delegated"
            exit 0
        fi
        echo "WARN: $CMD_ID is status=delegated but no cmd_new found in karo inbox. Retrying notification." >&2
        bash "$PROJECT_DIR/scripts/inbox_write.sh" karo "$(build_notify_message "$MESSAGE" "$CMD_ID")" cmd_new shogun || {
            echo "ERROR: inbox_write.sh failed for $CMD_ID — status=delegatedは維持(手動inbox_writeで再送可)" >&2
            exit 1
        }
        echo "DELEGATED: $CMD_ID at $existing_delegated (notification retried)"
        exit 0
    fi
    echo "ERROR: $CMD_ID has delegated_at=$existing_delegated but status=$status (expected delegated). Refusing to treat inconsistent state as delegated." >&2
    exit 1
fi

if [ "$status" != "pending" ]; then
    echo "ERROR: cmd_id '$CMD_ID' status is '$status', expected 'pending'" >&2
    exit 1
fi

# Step 2.5: 家老inboxのcmd_newメッセージに既にcmd_idが存在するかチェック（別経路委任の検出）
# 重複が明確な場合は cmd_save.sh を走らせず、状態を変えない。
if [ -f "$KARO_INBOX" ] && inbox_has_cmd_new_for_cmd "$KARO_INBOX" "$CMD_ID"; then
    echo "WARN: $CMD_ID is already mentioned in karo inbox (previously sent via another path)" >&2
    echo "BLOCK: Refusing to send duplicate. If re-delegation is intended, remove existing inbox entry first." >&2
    exit 1
fi

# deploy_task.sh's natural-boundary gate requires this field.  Validate it at
# the earlier delegation boundary so an invalid command can never wake Karo
# and fail only after review/deployment has begun.
validate_estimated_minutes "$SHOGUN_TO_KARO" "$CMD_ID" || exit 1

# Step 3: 初回委任前に cmd_save.sh を強制実行
cmd_save_exit=0
if bash "$PROJECT_DIR/scripts/cmd_save.sh" "$CMD_ID"; then
    cmd_save_exit=0
else
    cmd_save_exit=$?
fi

if [ "$cmd_save_exit" -eq 1 ]; then
    echo "BLOCK: GATE未通過。修正してからcmd_save.sh→inbox_writeを手動実行せよ" >&2
    exit 1
fi

if [ "$cmd_save_exit" -ne 0 ]; then
    echo "ERROR: cmd_save.sh failed for $CMD_ID (exit=$cmd_save_exit)" >&2
    exit "$cmd_save_exit"
fi

# Step 3.4: 他の未配備cmd検出チェック（status=pending + delegated_at存在 → WARNING）
# 事故防止: 家老が委任を受けたが配備を忘れたパターンを次の委任前に警告 (cmd_1686事故)
undeployed_cmds=$(find_undeployed_pending_cmds "$SHOGUN_TO_KARO" "$CMD_ID")

if [ -n "$undeployed_cmds" ]; then
    echo "WARN: 委任済みだが未配備のcmdを検出。家老が処理していない可能性がある:" >&2
    while IFS= read -r line; do
        echo "  - $line" >&2
    done <<< "$undeployed_cmds"
fi

# Step 3.6: dashboardパイプラインに既にcmd_idが載っているかチェック（WARN only — secondary data）
# -w: word-boundary matching。cmd_100 が cmd_1000 内にマッチして誤WARNするのを防ぐ（inbox_has_cmd_new_for_cmdと整合）
if [ -f "$DASHBOARD" ] && LC_ALL=C grep -Fqwm1 "$CMD_ID" "$DASHBOARD" 2>/dev/null; then
    echo "WARN: $CMD_ID is already listed in dashboard.md (karo may already be aware). Proceeding — dashboard is secondary data." >&2
fi

# Step 3.7: archiveに完了済みとして存在するかチェック
if cmd_is_archived "$CMD_ID"; then
    echo "BLOCK: $CMD_ID is already archived (completed). Cannot re-delegate." >&2
    exit 1
fi

# cmd_new gate(inbox_write.sh L1967-1999)はcontentに正規cmd IDが含まれることを要求し、
# 不在なら exit 1 でBLOCKする。cmd_delegate.shは検証済みのCMD_IDを保持しているため、
# 利用者メッセージにcmd_idが書かれていない場合は構造的に補う。
# これを補わないと status=delegated だけが立ち、家老inboxへ配送されない乖離が起きる
# (2026-07-23 cmd_4123実測: 1回目のdelegateでstatus=delegated かつ karo inbox 0件)。
# 二次情報(status)と一次情報(inbox実体)の乖離を作らないための構造型強制。

# Step 4: status=delegated + delegated_at を先に設定（inbox_writeのcmd_new guardがstatus確認するため）
printf -v TIMESTAMP '%(%Y-%m-%dT%H:%M:%S)T' -1
yaml_field_set "$SHOGUN_TO_KARO" "$CMD_ID" "status" "delegated" || {
    echo "ERROR: Failed to set status=delegated for $CMD_ID" >&2
    exit 1
}
yaml_field_set "$SHOGUN_TO_KARO" "$CMD_ID" "delegated_at" "\"$TIMESTAMP\"" || {
    echo "ERROR: Failed to set delegated_at for $CMD_ID" >&2
    if yaml_field_set "$SHOGUN_TO_KARO" "$CMD_ID" "status" "pending"; then
        echo "ROLLBACK: status restored to pending for $CMD_ID" >&2
    else
        echo "ERROR: rollback failed for $CMD_ID — status may be delegated without delegated_at" >&2
    fi
    exit 1
}

# Step 5: inbox_write.sh で家老に通知（status=delegated済みなのでguard通過）
bash "$PROJECT_DIR/scripts/inbox_write.sh" karo "$(build_notify_message "$MESSAGE" "$CMD_ID")" cmd_new shogun || {
    echo "ERROR: inbox_write.sh failed for $CMD_ID — status=delegatedは維持(手動inbox_writeで再送可)" >&2
    exit 1
}

MEMORY_DB_PATH="${SHOGUN_MEMORY_DB:-$PROJECT_DIR/data/multi_agent_shogun_memory.db}"
if [[ -f "$MEMORY_DB_LIVE_INSERT" && -f "$MEMORY_DB_PATH" ]]; then
    memory_db_args=(
        cmd_delegate
        --cmd-id "$CMD_ID" \
        --ts "$TIMESTAMP" \
        --delegated-at "$TIMESTAMP" \
        --message "$MESSAGE" \
        --summary "$MESSAGE" \
        --source-file "${SHOGUN_TO_KARO#$PROJECT_DIR/}"
    )
    if [[ -n "${SHOGUN_MEMORY_DB:-}" ]]; then
        python3 "$MEMORY_DB_LIVE_INSERT" "${memory_db_args[@]}" >/dev/null 2>&1 || true
    else
        python3 "$MEMORY_DB_LIVE_INSERT" "${memory_db_args[@]}" >/dev/null 2>&1 &
        disown 2>/dev/null || true
    fi
fi

# Step 6: 成功出力
echo "DELEGATED: $CMD_ID at $TIMESTAMP"
