#!/usr/bin/env bash
# semantic-links: [[gate迂回防止]]
# ============================================================
# gate_improvement_trigger.sh
# gate ALERT検知 → 穴検出3問を家老inbox送信 + ntfy通知
#
# 設計原則（殿厳命）:
#   「自動消火は最悪の手段。問題を隠し先送りして被害を拡大させる。
#    まっとうに成長して賢くなり結果論としてゲートブロックが起きないループを回せ。」
#
# ❌ 自動消火: ALERT→自動で処理→終わり（問題が隠れる）
# ✅ 改善トリガー: ALERT→ntfy通知→穴検出3問を家老に送信
#    →家老が調査→教訓化→防御層強化→根本原因修正
#
# Usage:
#   bash scripts/gate_improvement_trigger.sh
#
# Exit code: 0 (always — this script is a notification trigger, not a blocker)
# ============================================================
set -euo pipefail

SCRIPT_DIR="${GATE_IMPROVEMENT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
GATES_DIR="$SCRIPT_DIR/scripts/gates"
ALERTS_FILE="$SCRIPT_DIR/logs/gate_alerts.yaml"
STATE_DIR="$SCRIPT_DIR/logs/gate_state"
mkdir -p "$STATE_DIR"
DEDUP_WINDOW_SECONDS="${GATE_IMPROVEMENT_DEDUP_WINDOW_SECONDS:-86400}"

# A trigger started by an older monitor generation may finish after hot reload.
# Check the owner lease at every side-effect boundary so ownership transfers by
# generation handoff, without signalling or terminating the old worker.
owner_generation_is_current() {
    local owner_file="${GATE_IMPROVEMENT_OWNER_FILE:-}"
    local expected_pid="${GATE_IMPROVEMENT_OWNER_PID:-}"
    local expected_generation="${GATE_IMPROVEMENT_OWNER_GENERATION:-}"
    local owner_pid="" owner_generation=""
    [ -n "$owner_file" ] || return 0
    [ -n "$expected_pid" ] && [ -n "$expected_generation" ] || return 1
    IFS=' ' read -r owner_pid owner_generation _owner_heartbeat < "$owner_file" 2>/dev/null || return 1
    [ "$owner_pid" = "$expected_pid" ] || return 1
    [ "$owner_generation" = "$expected_generation" ] || return 1
    [ -d "/proc/$owner_pid" ] || return 1
}

current_epoch() {
    if [[ "${GATE_IMPROVEMENT_NOW:-}" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$GATE_IMPROVEMENT_NOW"
    else
        date +%s
    fi
}

sanitize_state_key() {
    local value="$1"
    value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/_/g; s/_+/_/g; s/^_//; s/_$//')"
    if [[ -z "$value" ]]; then
        value="unknown"
    fi
    printf '%s\n' "$value"
}

dedup_key_for_alert_line() {
    local gate_name="$1"
    local alert_line="$2"
    local alert_type file_name

    if [[ "$alert_line" =~ ^(WARN|ALERT):[[:space:]]+([^[:space:]]+) ]]; then
        alert_type="${BASH_REMATCH[1]}"
        file_name="${BASH_REMATCH[2]}"
        printf '%s_%s_%s\n' "$(sanitize_state_key "$gate_name")" "$(sanitize_state_key "$alert_type")" "$(sanitize_state_key "$file_name")"
        return 0
    fi

    return 1
}

alert_lines_have_file_alert_key() {
    local gate_name="$1"
    local alert_lines="$2"
    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if dedup_key_for_alert_line "$gate_name" "$line" >/dev/null; then
            return 0
        fi
    done <<< "$alert_lines"
    return 1
}

dedup_alert_lines_24h() {
    local gate_name="$1"
    local alert_lines="$2"
    local now
    now="$(current_epoch)"

    if ! [[ "$DEDUP_WINDOW_SECONDS" =~ ^[0-9]+$ ]]; then
        DEDUP_WINDOW_SECONDS=86400
    fi

    local kept_lines=()
    local skipped_count=0
    local line key state_file last_epoch elapsed
    # GA-216/GA-217: dedup by logical EVENT, not by individual line. A gate
    # emits one ALERT:/WARN: line optionally followed by continuation lines
    # (action:/METRIC:) that belong to that same event — see
    # extract_alert_lines()/extract_diagnostic_lines() above, which pair them
    # up. dedup_key_for_alert_line() only matches lines starting with
    # ALERT:/WARN:, so a continuation line alone never matches. Track the
    # skip/keep decision made for the most recent ALERT:/WARN: line and apply
    # it to its continuation lines too, so a deduped-away event is dropped as
    # a whole block instead of leaving an orphaned "action: ..." line that
    # bypasses dedup entirely and mints a spurious new GA-ID (reproduced
    # verbatim in logs/gate_alerts.yaml GA-217).
    local skip_current_block=false
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if key="$(dedup_key_for_alert_line "$gate_name" "$line")"; then
            skip_current_block=false
            state_file="${STATE_DIR}/gate_improvement_dedup_${key}.last"
            if [[ -f "$state_file" ]]; then
                last_epoch="$(head -n 1 "$state_file" 2>/dev/null || true)"
                if [[ "$last_epoch" =~ ^[0-9]+$ ]]; then
                    elapsed=$((now - last_epoch))
                    if (( elapsed >= 0 && elapsed < DEDUP_WINDOW_SECONDS )); then
                        echo "SKIP: ${gate_name} — ${line} は同一file+alert_typeで24時間以内に送信済み (${elapsed}s ago)" >&2
                        skipped_count=$((skipped_count + 1))
                        skip_current_block=true
                        continue
                    fi
                fi
            fi
            printf '%s\n' "$now" > "$state_file"
        elif [[ "$skip_current_block" == true ]]; then
            # Continuation line of an event whose ALERT:/WARN: line was just
            # deduped away — drop it too instead of leaking it through.
            continue
        fi
        kept_lines+=("$line")
    done <<< "$alert_lines"

    if [[ "${#kept_lines[@]}" -eq 0 ]]; then
        if [[ "$skipped_count" -gt 0 ]]; then
            return 1
        fi
        return 0
    fi

    printf '%s\n' "${kept_lines[@]}"
    return 0
}

# --- alert_id連番管理 ---
get_next_alert_id() {
    local counter_file="$SCRIPT_DIR/logs/gate_alert_counter.txt"
    local current=0
    if [ -f "$counter_file" ]; then
        current=$(tr -d '[:space:]' < "$counter_file" 2>/dev/null) || current=0
        if ! [[ "$current" =~ ^[0-9]+$ ]]; then
            current=0
        fi
    fi
    local next=$((current + 1))
    echo "$next" > "$counter_file"
    printf "GA-%03d" "$next"
}

# Karo's control-plane inbox requires every actionable gate alert to carry a
# structured commander envelope.  Keep the subject task unique per alert
# while making parent_cmd identify the gate that caused it.
gate_alert_identity() {
    local gate_name="$1"
    local alert_id="$2"
    printf 'task_id=commander_directive subject_task_id=gate_alert_%s_%s parent_cmd=cmd_gate_improvement_%s\n' \
        "$gate_name" "$alert_id" "$gate_name"
}

# --- gate_alerts.yaml記録 ---
record_alert() {
    local alert_id="$1"
    local gate_name="$2"
    local alert_detail="$3"
    local timestamp
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z')
    local identity_subject="gate_alert_${gate_name}_${alert_id}"
    local identity_parent="cmd_gate_improvement_${gate_name}"

    # ファイルが存在しなければヘッダ作成
    if [ ! -f "$ALERTS_FILE" ]; then
        echo "alerts:" > "$ALERTS_FILE"
    fi

    cat >> "$ALERTS_FILE" <<EOF
  - alert_id: ${alert_id}
    gate: ${gate_name}
    task_id: commander_directive
    subject_task_id: ${identity_subject}
    parent_cmd: ${identity_parent}
    detected_at: "${timestamp}"
    alert_detail: "${alert_detail}"
    three_questions_sent: true
    investigation_cmd: null
    improvement_done: false
EOF
}

# --- 冪等性チェック ---
# 前回と同一のALERT状態なら送信しない（状態遷移時のみ送信）
check_idempotent() {
    local gate_name="$1"
    local current_state="$2"
    local state_file="${STATE_DIR}/gate_improvement_last_state_${gate_name}"

    if [ -f "$state_file" ]; then
        local prev_state
        prev_state=$(cat "$state_file" 2>/dev/null) || prev_state=""
        if [ "$prev_state" = "$current_state" ]; then
            return 1  # 同一状態 → 送信しない
        fi
    fi

    echo "$current_state" > "$state_file"
    return 0  # 状態遷移 → 送信する
}

# --- 共通アラート送信パイプライン ---
# 冪等性チェック → alert_id発行 → 3問組立て → inbox送信 → 記録 → ntfy通知
# Returns: 0=sent, 1=skipped (idempotent)
send_alert() {
    local gate_name="$1"
    local alert_lines="$2"
    local deduped_alert_lines

    owner_generation_is_current || {
        echo "HANDOFF: ${gate_name} — owner generation superseded; side effects skipped"
        return 1
    }

    if ! deduped_alert_lines="$(dedup_alert_lines_24h "$gate_name" "$alert_lines")"; then
        if [[ -n "$deduped_alert_lines" ]]; then
            printf '%s\n' "$deduped_alert_lines"
        fi
        echo "SKIP: ${gate_name} — 全ALERT行が同一file+alert_typeの24時間dedup対象。"
        return 1
    fi
    if [[ -n "$deduped_alert_lines" ]]; then
        alert_lines="$deduped_alert_lines"
    fi

    if ! alert_lines_have_file_alert_key "$gate_name" "$alert_lines"; then
        if ! check_idempotent "$gate_name" "$alert_lines"; then
            echo "SKIP: ${gate_name} — 前回と同一ALERT状態。送信済み。"
            return 1
        fi
    fi

    local alert_id
    alert_id=$(get_next_alert_id)

    local supplement
    supplement=$(get_gate_supplement "$gate_name")
    local message
    message=$(build_three_questions "$gate_name" "$alert_id" "$alert_lines" "$supplement")
    local identity
    identity=$(gate_alert_identity "$gate_name" "$alert_id")
    message="${identity}"$'\n'"${message}"

    bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$message" gate_alert gate_improvement_trigger
    record_alert "$alert_id" "$gate_name" "$alert_lines"
    bash "$SCRIPT_DIR/scripts/ntfy.sh" "【改善トリガー】${gate_name} ALERT (${alert_id})" || true

    echo "SENT: ${gate_name} → ${alert_id}"
    return 0
}

# --- 穴検出3問テンプレート + gate固有補足 ---
build_three_questions() {
    local gate_name="$1"
    local alert_id="$2"
    local alert_detail="$3"
    local supplement="$4"

    cat <<EOF
【gate穴検出3問】${gate_name} ALERT (alert_id: ${alert_id})
検知内容: ${alert_detail}
Q1: なぜこのgateが鳴ったか？直接原因と根本原因の仮説を立てよ
Q2: 同じカテゴリの穴が他にないか？横展開候補を洗い出せ
Q3: 次にこのgateが鳴らないようにする防御層は何か？
→ 忍者に調査配備し、結果をlesson登録+防御層に反映せよ
補足: ${supplement}
EOF
}

# --- Gate固有の補足情報 ---
get_gate_supplement() {
    local gate_name="$1"
    case "$gate_name" in
        lesson_health)
            echo "未振り分け教訓が溜まっている。なぜ溜まった？教訓登録の頻度/品質に問題はないか？"
            ;;
        cmd_state)
            echo "未委任cmdがある。なぜ委任されていない？将軍の委任手順に穴はないか？"
            ;;
        context_freshness)
            echo "contextが古い。なぜ更新されていない？更新トリガーの設計に穴はないか？"
            ;;
        p_average_freshness)
            echo "p̄計算が古い。なぜバッチが実行されていない？バッチ実行の仕組みに穴はないか？"
            ;;
        ci_red)
            echo "CIが赤い。なぜテストが失敗した？テストカバレッジの穴はないか？"
            ;;
        hook_failure)
            echo "hookに引っかかった。コード品質の問題か、hook設定の問題か？パターンがあるか確認せよ。"
            ;;
        *)
            echo "gate固有の補足なし。"
            ;;
    esac
}

# --- 各gateの実行+ALERT判定+3問送信 ---

process_gate() {
    local gate_name="$1"
    local gate_script="$2"
    local extra_alert_exit="${3:-}"    # 追加ALERTとするexit code (e.g., "2")
    local extra_alert_pattern="${4:-}" # 追加ALERTとするgrepパターン (e.g., "WARN:")
    local output
    local exit_code=0
    owner_generation_is_current || return 0

    output=$($gate_script 2>&1) || exit_code=$?
    evaluate_gate_result "$gate_name" "$output" "$exit_code" "$extra_alert_exit" "$extra_alert_pattern"
}

process_gate_cached() {
    local gate_name="$1"
    local ttl_seconds="$2"
    local gate_script="$3"
    local extra_alert_exit="${4:-}"    # 追加ALERTとするexit code (e.g., "2")
    local extra_alert_pattern="${5:-}" # 追加ALERTとするgrepパターン (e.g., "WARN:")
    local cache_key="${SCRIPT_DIR//[\/: .#*?!]/_}_${gate_name}"
    local cache_base="${TMPDIR:-/tmp}/gate_improvement_trigger_${cache_key}"
    local output_file="${cache_base}.out"
    local rc_file="${cache_base}.rc"
    local now cache_mtime cache_age output exit_code
    owner_generation_is_current || return 0

    now=$(date +%s)
    cache_mtime=$(stat -c %Y "$output_file" 2>/dev/null || printf 0)
    cache_age=$((now - cache_mtime))
    if [ -s "$output_file" ] && [ -s "$rc_file" ] && [ "$cache_age" -ge 0 ] && [ "$cache_age" -lt "$ttl_seconds" ]; then
        output=$(cat "$output_file" 2>/dev/null || true)
        exit_code=$(cat "$rc_file" 2>/dev/null || printf 127)
        if [[ "$exit_code" =~ ^[0-9]+$ ]]; then
            evaluate_gate_result "$gate_name" "$output" "$exit_code" "$extra_alert_exit" "$extra_alert_pattern"
            return 0
        fi
    fi

    output=$($gate_script 2>&1) || exit_code=$?
    printf '%s\n' "$output" > "$output_file"
    printf '%s\n' "${exit_code:-0}" > "$rc_file"
    evaluate_gate_result "$gate_name" "$output" "${exit_code:-0}" "$extra_alert_exit" "$extra_alert_pattern"
}

output_has_alert_prefix() {
    local output="$1"
    local extra_alert_pattern="${2:-}"
    if [[ "$output" == ALERT:* || "$output" == *$'\n'ALERT:* ]]; then
        return 0
    fi
    if [[ -n "$extra_alert_pattern" && ( "$output" == "$extra_alert_pattern"* || "$output" == *$'\n'"$extra_alert_pattern"* ) ]]; then
        return 0
    fi
    return 1
}

# GA-505: source-only publication can carry the same changed-path blobs to
# origin/main without preserving the local source commit as an ancestor.  That
# provenance lag is not a knowledge-freshness defect, so do not wake the
# improvement lane when equivalence is proven.  Unknown/missing commits and
# divergent blobs remain actionable; inability to prove equivalence never
# suppresses a WARN.
source_equivalent_publication_lag_is_non_actionable() {
    local gate_name="$1"
    local alert_lines="$2"
    local first_line source_hash repo local_main origin_main path
    local -a lines=() changed_paths=()

    [[ "$gate_name" == "context_freshness" ]] || return 1
    mapfile -t lines <<< "$alert_lines"
    ((${#lines[@]} >= 1 && ${#lines[@]} <= 2)) || return 1
    first_line="${lines[0]}"
    [[ "$first_line" =~ source_equivalent[[:space:]]+boundary[[:space:]]+rejected:[[:space:]]+source[[:space:]]+commit[[:space:]]+([0-9a-f]{7,40})[[:space:]]+is[[:space:]]+not[[:space:]]+an[[:space:]]+origin/main[[:space:]]+ancestor ]] || return 1
    source_hash="${BASH_REMATCH[1]}"
    if ((${#lines[@]} == 2)); then
        [[ "${lines[1]}" == action:* ]] || return 1
    fi

    repo="${GATE_IMPROVEMENT_SOURCE_REPO:-$SCRIPT_DIR}"
    [[ -d "$repo/.git" || -f "$repo/.git" ]] || return 1
    git -C "$repo" cat-file -e "${source_hash}^{commit}" 2>/dev/null || return 1
    local_main="$(git -C "$repo" rev-parse --verify refs/heads/main 2>/dev/null || true)"
    origin_main="$(git -C "$repo" rev-parse --verify refs/remotes/origin/main 2>/dev/null || true)"
    [[ "$local_main" =~ ^[0-9a-f]{40}$ && "$origin_main" =~ ^[0-9a-f]{40}$ ]] || return 1
    git -C "$repo" merge-base --is-ancestor "$source_hash" "$local_main" 2>/dev/null || return 1
    git -C "$repo" merge-base --is-ancestor "$source_hash" "$origin_main" 2>/dev/null && return 1
    mapfile -t changed_paths < <(git -C "$repo" diff-tree --root --no-commit-id --name-only -r "$source_hash" 2>/dev/null)
    ((${#changed_paths[@]} > 0)) || return 1
    for path in "${changed_paths[@]}"; do
        [[ -n "$path" ]] || continue
        git -C "$repo" diff --quiet "$source_hash" "$origin_main" -- "$path" 2>/dev/null || return 1
    done
    return 0
}

extract_alert_lines() {
    local output="$1"
    local extra_alert_pattern="${2:-}"
    local line count=0
    local include_next_context=false
    while IFS= read -r line; do
        if [[ "$line" == ALERT:* || ( -n "$extra_alert_pattern" && "$line" == "$extra_alert_pattern"* ) ]]; then
            printf '%s\n' "$line"
            count=$((count + 1))
            include_next_context=true
            if [ "$count" -ge 5 ]; then
                return 0
            fi
            continue
        fi
        if [[ "$include_next_context" == true && ( "$line" == action:* || "$line" == METRIC:* ) ]]; then
            printf '%s\n' "$line"
            include_next_context=false
            continue
        fi
    done <<< "$output"
}

extract_diagnostic_lines() {
    local output="$1"
    local line count=0
    local include_next_context=false
    while IFS= read -r line; do
        if [[ "$line" == WARN:* || "$line" == ALERT:* ]]; then
            printf '%s\n' "$line"
            count=$((count + 1))
            include_next_context=true
            if [ "$count" -ge 5 ]; then
                return 0
            fi
            continue
        fi
        if [[ "$include_next_context" == true && ( "$line" == action:* || "$line" == METRIC:* ) ]]; then
            printf '%s\n' "$line"
            include_next_context=false
            continue
        fi
        if [[ "$line" == METRIC:* ]]; then
            printf '%s\n' "$line"
            count=$((count + 1))
            if [ "$count" -ge 5 ]; then
                return 0
            fi
        fi
    done <<< "$output"
}

evaluate_gate_result() {
    local gate_name="$1"
    local output="$2"
    local exit_code="$3"
    local extra_alert_exit="${4:-}"    # 追加ALERTとするexit code (e.g., "2")
    local extra_alert_pattern="${5:-}" # 追加ALERTとするgrepパターン (e.g., "WARN:")

    owner_generation_is_current || {
        echo "HANDOFF: ${gate_name} — owner generation superseded; result ignored"
        return 0
    }

    # ALERT判定: exit_code=1 または出力に "ALERT:" を含む
    local is_alert=false
    if [ "$exit_code" -eq 1 ] || output_has_alert_prefix "$output"; then
        is_alert=true
    fi
    if [ -n "$extra_alert_exit" ] && [ "$exit_code" -eq "$extra_alert_exit" ]; then
        is_alert=true
    fi
    if [ -n "$extra_alert_pattern" ] && output_has_alert_prefix "$output" "$extra_alert_pattern"; then
        is_alert=true
    fi

    if [ "$is_alert" = true ]; then
        # ALERT行を抽出（複数あり得る）
        local alert_lines
        alert_lines=$(extract_alert_lines "$output" "$extra_alert_pattern")
        if [ -z "$alert_lines" ]; then
            alert_lines=$(extract_diagnostic_lines "$output")
        fi
        if [ -z "$alert_lines" ]; then
            local output_snippet
            output_snippet=$(printf '%s\n' "$output" | awk 'NF {print; exit}' | tr '\n' ' ' | cut -c 1-240)
            alert_lines="exit_code=$exit_code; output_snippet=${output_snippet:-empty}"
        fi

        if source_equivalent_publication_lag_is_non_actionable "$gate_name" "$alert_lines"; then
            echo "OK: ${gate_name} — source-equivalent publication already matches origin/main; improvement trigger suppressed"
            return 0
        fi

        send_alert "$gate_name" "$alert_lines" || true
    else
        # ALERT解消時: 状態ファイルをクリア（次回ALERTで再送可能にする）
        local state_file="${STATE_DIR}/gate_improvement_last_state_${gate_name}"
        if [ -f "$state_file" ]; then
            rm -f "$state_file"
        fi
        echo "OK: ${gate_name} — no ALERT"
    fi
}

# --- (5) CI赤チェック ---
check_ci_red() {
    local gate_name="ci_red"
    local output
    local exit_code=0
    owner_generation_is_current || return 0

    # gh run list で最新runの結論を取得（originリポジトリを明示指定）
    output=$(gh run list --repo simokitafresh/multi-agent-shogun --limit 3 --json conclusion,name,headBranch \
        --jq '.[] | select(.headBranch=="main") | .conclusion' 2>&1) || exit_code=$?

    evaluate_ci_red_result "$output" "$exit_code"
}

evaluate_ci_red_result() {
    local output="$1"
    local exit_code="$2"
    local gate_name="ci_red"
    owner_generation_is_current || return 0

    if [ "$exit_code" -ne 0 ]; then
        echo "SKIP: ci_red — gh run list failed: $output"
        return 0
    fi

    # 最新mainブランチの結論を取得
    local latest_conclusion
    latest_conclusion=$(echo "$output" | head -1)

    if [ "$latest_conclusion" = "failure" ]; then
        local alert_lines="ALERT: CI赤 — 最新mainブランチのCIが失敗"

        send_alert "$gate_name" "$alert_lines" || true
    else
        local state_file="${STATE_DIR}/gate_improvement_last_state_${gate_name}"
        if [ -f "$state_file" ]; then
            rm -f "$state_file"
        fi
        echo "OK: ${gate_name} — conclusion=${latest_conclusion:-none}"
    fi
}

# =========================
# メイン処理
# =========================
echo "=== gate_improvement_trigger.sh ==="
echo "timestamp: $(date '+%Y-%m-%dT%H:%M:%S%z')"
echo ""

RUN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/gate_improvement_trigger.XXXXXX")
cleanup_run_dir() {
    rm -rf "$RUN_DIR"
}
trap cleanup_run_dir EXIT

run_check_async() {
    local key="$1"
    shift
    (
        set +e
        "$@" > "$RUN_DIR/${key}.out" 2>&1
        printf '%s\n' "$?" > "$RUN_DIR/${key}.rc"
    ) &
}

read_check_output() {
    local key="$1"
    cat "$RUN_DIR/${key}.out" 2>/dev/null || true
}

read_check_rc() {
    local key="$1"
    local rc
    rc=$(cat "$RUN_DIR/${key}.rc" 2>/dev/null || true)
    if [[ "$rc" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$rc"
    else
        printf '127\n'
    fi
}

# `gh run list`は外部待ちが支配的なため、I/O-heavyなgate直列実行の裏で先行取得する。
run_check_async ci_red gh run list --repo simokitafresh/multi-agent-shogun --limit 3 --json conclusion,name,headBranch --jq '.[] | select(.headBranch=="main") | .conclusion'
pid_ci_red=$!

# The three remaining gates are independent read-only probes. Start them before
# lesson_health (the longest probe), then consume their captured results in the
# original order below so user-visible ordering and alert semantics stay fixed.
run_check_async cmd_state bash "$GATES_DIR/gate_cmd_state.sh"
pid_cmd_state=$!
run_check_async context_freshness bash "$GATES_DIR/gate_context_freshness.sh"
pid_context_freshness=$!
run_check_async p_average_freshness bash "$GATES_DIR/gate_p_average_freshness.sh"
pid_p_average_freshness=$!

# (1) gate_lesson_health
# A single lesson_health run can exceed 10s on /mnt/c, so a 5s TTL expires before
# consecutive trigger invocations can reuse it. Keep this below the 5-minute
# monitor cadence while avoiding duplicate scans in burst/manual runs.
process_gate_cached "lesson_health" 60 "bash $GATES_DIR/gate_lesson_health.sh"

# (2) gate_cmd_state
wait "$pid_cmd_state" || true
evaluate_gate_result "cmd_state" "$(read_check_output cmd_state)" "$(read_check_rc cmd_state)"

# (3) gate_context_freshness (WARN/ALERT両方をトリガー対象 — exit=2もALERT扱い)
wait "$pid_context_freshness" || true
evaluate_gate_result "context_freshness" "$(read_check_output context_freshness)" "$(read_check_rc context_freshness)" "2" "WARN:"

# (4) gate_p_average_freshness
wait "$pid_p_average_freshness" || true
evaluate_gate_result "p_average_freshness" "$(read_check_output p_average_freshness)" "$(read_check_rc p_average_freshness)"

# (5) CI赤
wait "$pid_ci_red" || true
evaluate_ci_red_result "$(read_check_output ci_red)" "$(read_check_rc ci_red)"

# (6) Hook失敗検知 (cmd_1117)
# logs/hook_failures.yamlに新規レコードがあれば穴検出3問を家老inboxに送信
check_hook_failures() {
    local gate_name="hook_failure"
    local failures_file="$SCRIPT_DIR/logs/hook_failures.yaml"
    local state_file="${STATE_DIR}/gate_improvement_hook_last_count"
    owner_generation_is_current || return 0

    if [ ! -f "$failures_file" ]; then
        echo "OK: ${gate_name} — no failures file"
        return 0
    fi

    # 現在のレコード数（awk使用: cmd_192 grep -c バグ回避）
    local current_count
    current_count=$(awk '/^- timestamp:/{c++}END{print c+0}' "$failures_file" 2>/dev/null)

    # 前回確認時のレコード数
    local last_count=0
    if [ -f "$state_file" ]; then
        last_count=$(tr -d '[:space:]' < "$state_file" 2>/dev/null) || last_count=0
        if ! [[ "$last_count" =~ ^[0-9]+$ ]]; then
            last_count=0
        fi
    fi

    if [ "$current_count" -gt "$last_count" ]; then
        local new_count=$((current_count - last_count))
        local tracked_hook="$SCRIPT_DIR/.githooks/pre-push"
        local active_hook="$SCRIPT_DIR/.git/hooks/pre-push"
        local tracked_hash=""
        local active_hash=""
        [ -f "$tracked_hook" ] && tracked_hash=$(sha256sum "$tracked_hook" 2>/dev/null | awk '{print $1}')
        [ -f "$active_hook" ] && active_hash=$(sha256sum "$active_hook" 2>/dev/null | awk '{print $1}')
        local classification
        classification=$(python3 - "$failures_file" "$last_count" "$tracked_hash" "$active_hash" "$SCRIPT_DIR" <<'PY'
import sys
from pathlib import Path

import yaml

path, cursor, tracked, active, script_root = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5]
rows = yaml.safe_load(open(path, encoding="utf-8")) or []
if isinstance(rows, dict):
    rows = rows.get("failures", [])
rows = rows[cursor:]
current_hashes = {h for h in (tracked, active) if h}

def is_expected_ga_push1_safety_block(row):
    """Require the recorded artifact to prove the hook's safety-block path."""
    if not isinstance(row, dict):
        return False
    if row.get("hook") != "pre-push" or row.get("exit_code") != 1:
        return False
    artifact = row.get("artifact")
    if not isinstance(artifact, str) or not artifact:
        return False
    artifact_path = Path(artifact)
    if not artifact_path.is_absolute():
        artifact_path = Path(script_root) / artifact_path
    try:
        text = artifact_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        return False
    required = (
        "[pre-push] BLOCK(GA-PUSH1): pushしようとしているcommitと、作業ツリーの未commit変更が同一pathを差している。",
        "[pre-push] 重複path:",
    )
    return all(marker in text for marker in required)

expected = [r for r in rows if is_expected_ga_push1_safety_block(r)]
remaining = [r for r in rows if r not in expected]
current = [r for r in remaining if isinstance(r, dict) and r.get("hook_sha256") in current_hashes]
legacy = [r for r in remaining if not isinstance(r, dict) or not r.get("hook_sha256")]
old = len(remaining) - len(current) - len(legacy)
print(f"{len(current)} {old} {len(legacy)} {len(expected)}")
PY
)
        local current_generation_count old_generation_count legacy_count expected_ga_push1_count
        read -r current_generation_count old_generation_count legacy_count expected_ga_push1_count <<< "$classification"

        # Failures from an already-running old hook can finish after a fix is
        # committed. They are evidence, but not a recurrence of the tracked
        # generation. Advance the cursor without minting a false GA alert.
        if [ "$current_generation_count" -eq 0 ] && [ "$legacy_count" -eq 0 ]; then
            echo "$current_count" > "$state_file"
            if [ "$expected_ga_push1_count" -gt 0 ]; then
                echo "OK: ${gate_name} — expected GA-PUSH1 safety BLOCKs ignored (expected=${expected_ga_push1_count}, old=${old_generation_count}, current=0)"
            else
                echo "OK: ${gate_name} — old generation completions ignored (old=${old_generation_count}, current=0)"
            fi
            return 0
        fi
        local alert_lines="ALERT: hook失敗 ${new_count}件の新規レコード検知(total: ${current_count})"
        alert_lines+=" current_generation=${current_generation_count} old_generation=${old_generation_count} legacy=${legacy_count} expected_ga_push1=${expected_ga_push1_count}"

        # 最新の失敗レコードを取得（最後の5行）
        local latest_detail
        latest_detail=$(tail -5 "$failures_file" 2>/dev/null | tr '\n' ' ')

        if ! check_idempotent "$gate_name" "$alert_lines"; then
            echo "SKIP: ${gate_name} — 前回と同一ALERT状態。送信済み。"
            echo "$current_count" > "$state_file"
            return 0
        fi

        local alert_id
        alert_id=$(get_next_alert_id)

        # hook版穴検出3問（タスク指定のQ1-Q3）
        local identity
        identity=$(gate_alert_identity "$gate_name" "$alert_id")
        local message
        message=$(cat <<EOF
${identity}
【hook穴検出3問】${gate_name} ALERT (alert_id: ${alert_id})
検知内容: ${alert_lines}
最新失敗: ${latest_detail}
Q1: なぜこのhookに引っかかったか？コード品質の問題か、hook設定の問題か
Q2: 同じ種類の引っかかりが他の忍者でも起きていないか？パターンはあるか
Q3: 次に引っかからないようにする防御層は何か？
→ 忍者に調査配備し、結果をlesson登録+防御層に反映せよ
補足: $(get_gate_supplement "$gate_name")
EOF
)

        bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$message" gate_alert gate_improvement_trigger
        record_alert "$alert_id" "$gate_name" "$alert_lines"
        bash "$SCRIPT_DIR/scripts/ntfy.sh" "【改善トリガー】${gate_name} ALERT (${alert_id})" || true

        echo "$current_count" > "$state_file"
        echo "SENT: ${gate_name} → ${alert_id}"
    else
        echo "OK: ${gate_name} — no new failures (count=${current_count})"
    fi
}
check_hook_failures

echo ""
echo "=== gate_improvement_trigger.sh complete ==="
