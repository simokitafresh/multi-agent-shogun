#!/usr/bin/env bash
# semantic-links: [[防御階層原則(Level 1-6)]]
# ============================================================
# gate_context_freshness.sh
# dashboardと同じ監視対象に対してソースcommit差分ベースで鮮度を自動チェックする
#
# Usage:
#   bash scripts/gates/gate_context_freshness.sh
#
# チェック内容:
#   scripts/context_freshness_check.sh --dashboard-warnings と同じ対象
#   （直近completed cmdがあるactive projectのcontext）のみを監視する
#   各context/*.mdの先頭コメントから last_updated を解析し、ソースrepoの非auto commit有無を確認
#   フォーマット: <!-- last_updated: YYYY-MM-DD --> または
#                <!-- last_updated: YYYY-MM-DD cmd_XXX ... -->
#   ソースrepoにlast_updated後の新commitあり → ALERT
#     last_updated未記載 → WARN（「未記載」と明示）
#
# Exit code: 0=全OK, 1=1つ以上ALERT, 2=WARNのみ(ALERTなし)
# ============================================================
set -euo pipefail

_self="${BASH_SOURCE[0]}"
SCRIPT_DIR="${_self%/*}"
[[ "$SCRIPT_DIR" != /* ]] && SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd)"
SCRIPT_DIR="${SCRIPT_DIR%/scripts/gates}"
ROOT_DIR="${CONTEXT_FRESHNESS_ROOT:-$SCRIPT_DIR}"
CHECK_SCRIPT="${CONTEXT_FRESHNESS_CHECK_SCRIPT:-$ROOT_DIR/scripts/context_freshness_check.sh}"
NTFY_SCRIPT="${CONTEXT_FRESHNESS_NTFY_SCRIPT:-$ROOT_DIR/scripts/ntfy.sh}"
TODAY_OVERRIDE="${CONTEXT_FRESHNESS_TODAY:-}"
CACHE_TTL="${CONTEXT_FRESHNESS_GATE_CACHE_TTL:-300}"
ALERT_DEBOUNCE_SECONDS="${CONTEXT_FRESHNESS_ALERT_DEBOUNCE_SECONDS:-86400}"
ALERT_STATE_DIR="${CONTEXT_FRESHNESS_ALERT_STATE_DIR:-/tmp/gate_context_freshness_alerts}"
# GA-245: 旧既定1秒は、このリポジトリの実行環境(9pマウント/mnt/c)でのgit log
# 実測所要時間(集約後でも1回あたり3〜8秒、不安定域は6秒以下で実証)を大幅に
# 下回っており、対象のほぼ全件がtimeoutする根本原因だった。context_freshness_check.sh
# 側のgit呼出し集約(GA-245)と組み合わせ、実測に安全マージンを載せた値へ適正化する。
# 単純延長ではなく、それでも取得失敗した場合はfail-closedでALERT(exit 1)遮断する
# (check_failed_paths分岐、GA-245で WARN→ALERT に格上げ済み)。
# GA-292: snapshot producerのgit history走査は同じ9p上の履歴I/Oを使い、B0候補で
# 絶対時間326秒を実測した。旧30秒をproducerにも転送すると4 grouped query全てが
# timeoutし、内容が新鮮でも判定不能BLOCKになった。360秒は実測上限+10%余裕の
# bounded budgetであり、consumerはsnapshot hitならgit subprocess 0件のまま。
GIT_TIMEOUT="${CONTEXT_FRESHNESS_GATE_GIT_TIMEOUT:-360}"

HAS_ALERT=0
HAS_BLOCK=0
HAS_WARN=0
ALERT_LIST=()
STALE_TEMPLATE_ROWS=()

emit_actionable() {
    local message="$1"
    local action="$2"
    echo "$message"
    echo "  action: $action"
}

sanitize_cmd_slug() {
    local value="$1"
    value="${value#context/}"
    value="${value%.md}"
    value="${value//\//_}"
    value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_]+/_/g; s/_+/_/g; s/^_//; s/_$//')"
    if [[ -z "$value" ]]; then
        value="context"
    fi
    printf '%s' "$value"
}

record_stale_template_candidate() {
    local rel_path="$1"
    local days_ago="$2"
    local last_updated="$3"
    local sort_days
    if [[ "$days_ago" =~ ^[0-9]+$ ]]; then
        sort_days="$days_ago"
    else
        sort_days=99999
    fi
    STALE_TEMPLATE_ROWS+=("${sort_days}"$'\t'"${rel_path}"$'\t'"${days_ago}"$'\t'"${last_updated}")
}

source_commit_action() {
    local rel_path="$1"
    local alert_line="$2"
    local latest_hash=""
    if [[ "$alert_line" =~ latest:[[:space:]]*([0-9a-f]{7,40}) ]]; then
        latest_hash="${BASH_REMATCH[1]}"
    fi
    if [[ -n "$latest_hash" ]]; then
        printf '%s' "一次差分を照合後、bash scripts/context_source_commit_set.sh ${rel_path} ${latest_hash} '<reason>' '<evidence>' で検出済み境界を記録せよ。last_updatedだけの更新は禁止。"
    else
        printf '%s' "${rel_path} をソースPJの最新commitと照合し、必要なら内容とsource_commitをscripts/context_source_commit_set.shで更新せよ。last_updatedだけの更新は禁止。"
    fi
}

# GA-314: source更新を解消する際、索引本文が参照するrepo相対リンクの欠落を
# source_commit更新だけで隠してはならない。鮮度ALERT対象に限って参照を検査し、
# 欠落が1件でもあれば後段でBLOCKへ倒す。
missing_context_links() {
    local context_file="$1" rel_path="$2" token candidate reference_root="$ROOT_DIR"
    if [[ "$rel_path" == context/dm-signal* && -f "$ROOT_DIR/projects/dm-signal.yaml" ]]; then
        reference_root="$(python3 - "$ROOT_DIR/projects/dm-signal.yaml" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1])) or {}
print((data.get("project") or {}).get("path", ""))
PY
)"
        [[ -n "$reference_root" ]] || reference_root="$ROOT_DIR"
    fi
    while IFS= read -r token; do
        candidate="${token#\`}"
        candidate="${candidate%\`}"
        [[ "$candidate" == docs/* || "$candidate" == context/* ]] || continue
        candidate="${candidate%% *}"
        candidate="${candidate%%#*}"
        compgen -G "$reference_root/$candidate" >/dev/null || printf '%s\n' "$candidate"
    done < <(grep -oE '`(docs|context)/[^`]+`' "$context_file" 2>/dev/null || true)
}

emit_update_cmd_templates() {
    [[ "${#STALE_TEMPLATE_ROWS[@]}" -gt 0 ]] || return 0

    local today cmd_date
    if [[ -n "$TODAY_OVERRIDE" ]]; then
        today="$TODAY_OVERRIDE"
    else
        today="$(date +%F)"
    fi
    cmd_date="${today//-/}"

    echo "--- 更新cmdテンプレート TOP3 ---"
    printf '%s\n' "${STALE_TEMPLATE_ROWS[@]}" \
        | sort -t $'\t' -k1,1nr \
        | head -3 \
        | while IFS=$'\t' read -r _sort_days rel_path days_ago last_updated; do
            local slug project_id last_note
            slug="$(sanitize_cmd_slug "$rel_path")"
            project_id="infra"
            if [[ "$rel_path" == context/dm-signal* ]]; then
                project_id="dm-signal"
            fi
            if [[ -n "$last_updated" ]]; then
                last_note="last_updated=${last_updated}, ${days_ago}日前"
            else
                last_note="last_updated未記載"
            fi
            cat <<EOF
- id: cmd_ctx_${slug}_${cmd_date}
  purpose: "${rel_path} の鮮度ALERTを解消し、一次データで内容とsource_commit境界を更新する"
  project: ${project_id}
  acceptance_criteria:
    - "AC1: ${rel_path} を一次データと照合し、古い記述を更新または不要なら根拠付きで維持判断する"
    - "AC2: scripts/context_source_commit_set.shで${rel_path}のsource_commitを検証済み最新hashへ更新し、reason/evidenceを記録する。last_updatedだけの更新は禁止"
    - "AC3: bash scripts/gates/gate_context_freshness.sh をcache無効で再実行し、${rel_path} の未解消source commit=0件かつALERT=0件を確認する"
  not_in_scope: "対象ファイル以外の知識整理・設計変更"
  unresolved_decisions: "none"
  command: "${rel_path} の知識鮮度とsource_commit境界を更新。現状: ${last_note}。境界未更新なら完了せずBLOCKする"
EOF
        done
}

notify_context_alert() {
    local alert_summary="$1"
    local now
    now="${CONTEXT_FRESHNESS_ALERT_NOW:-$(date +%s)}"

    if ! [[ "$ALERT_DEBOUNCE_SECONDS" =~ ^[0-9]+$ ]]; then
        ALERT_DEBOUNCE_SECONDS=3600
    fi

    local alert_hash state_file last_epoch elapsed
    alert_hash="$(printf '%s' "$alert_summary" | sha256sum | awk '{print $1}')"
    mkdir -p "$ALERT_STATE_DIR" 2>/dev/null || true
    state_file="$ALERT_STATE_DIR/${alert_hash}.last"

    if [[ -f "$state_file" ]]; then
        last_epoch="$(head -n 1 "$state_file" 2>/dev/null || true)"
        if [[ "$last_epoch" =~ ^[0-9]+$ ]]; then
            elapsed=$((now - last_epoch))
            if (( elapsed >= 0 && elapsed < ALERT_DEBOUNCE_SECONDS )); then
                echo "[gate_context_freshness] ntfy skip: same ALERT sent ${elapsed}s ago (<${ALERT_DEBOUNCE_SECONDS}s): ${alert_summary}" >&2
                return 0
            fi
        fi
    fi

    if bash "$NTFY_SCRIPT" "【将軍】context鮮度ALERT: ${alert_summary}" >/dev/null 2>&1; then
        printf '%s\n' "$now" > "$state_file" 2>/dev/null || true
        echo "[gate_context_freshness] ntfy sent: ${alert_summary}" >&2
    else
        echo "[gate_context_freshness] ntfy failed: ${alert_summary}" >&2
    fi
}

TODAY_EPOCH=""

today_epoch() {
    [[ -n "$TODAY_EPOCH" ]] && return 0
    if [[ -n "$TODAY_OVERRIDE" ]]; then
        TODAY_EPOCH=$(date -d "$TODAY_OVERRIDE" +%s 2>/dev/null) || {
            echo "WARN: CONTEXT_FRESHNESS_TODAY の日付形式不正: $TODAY_OVERRIDE"
            echo "  action: YYYY-MM-DD 形式に修正せよ。"
            exit 2
        }
    else
        TODAY_EPOCH=$(date +%s)
    fi
}

if [[ ! -f "$CHECK_SCRIPT" ]]; then
    echo "WARN: context_freshness_check.sh not found"
    echo "  action: scripts/context_freshness_check.sh を復旧せよ。"
    exit 2
fi

warnings_output() {
    local cache_file=""
    if [[ "${CONTEXT_FRESHNESS_GATE_DISABLE_CACHE:-0}" != "1" && "$CACHE_TTL" =~ ^[0-9]+$ && "$CACHE_TTL" -gt 0 ]]; then
        local root_key
        root_key="${ROOT_DIR//[^A-Za-z0-9._-]/_}"
        local today_key="${TODAY_OVERRIDE:-today}"
        local stale_key="${CONTEXT_STALE_DAYS:-7}"
        local sig_parts=()
        local path
        for path in \
            "$CHECK_SCRIPT" \
            "$ROOT_DIR/config/projects.yaml" \
            "$ROOT_DIR/context/cmd-chronicle.md" \
            "$ROOT_DIR/queue/archive/cmds"
        do
            if [[ -e "$path" ]]; then
                sig_parts+=("$(stat -c '%n:%y:%s' "$path" 2>/dev/null || printf 'missing')")
            else
                sig_parts+=("missing")
            fi
        done
        while IFS= read -r path_signature; do
            sig_parts+=("$path_signature")
        done < <(find "$ROOT_DIR/context" -maxdepth 1 -type f -name '*.md' \
            -printf '%p:%T@:%s\n' 2>/dev/null | sort)
        sig_parts+=("git_timeout=${GIT_TIMEOUT}")
        local sig sig_hash
        sig="$(printf '%s|' "${sig_parts[@]}")"
        sig_hash="$(printf '%s' "$sig" | sha256sum | awk '{print $1}')"
        cache_file="/tmp/gate_context_freshness_${root_key}_${today_key}_${stale_key}_${sig_hash}.cache"
        local now cache_mtime
        now="$(date +%s)"
        if [[ -f "$cache_file" ]]; then
            cache_mtime="$(stat -c '%Y' "$cache_file" 2>/dev/null || printf 0)"
            if (( now - cache_mtime < CACHE_TTL )); then
                cat "$cache_file"
                return 0
            fi
        fi
    fi

    # One source commit after the context's recorded source_commit is enough to
    # make the context stale.  A threshold greater than one lets an ALERT
    # disappear when commits are later merged/squashed even though the context
    # itself was never refreshed (GA-226).
    local _min_sc="${CONTEXT_FRESHNESS_MIN_SOURCE_COMMITS:-1}"
    if [[ -n "$cache_file" ]]; then
        local tmp_cache="${cache_file}.$$"
        # The gate timeout is a total per-attempt budget, not merely the first
        # attempt.  Without forwarding the retry budget the checker falls back
        # to 60s, so e.g. GIT_TIMEOUT=1 can still block for 61s (GA-283).
        # A gate decision cannot consume an asynchronously-produced snapshot on
        # its first run.  Rebuild a cache miss within this bounded gate budget so
        # a new source tip is checked now instead of emitting one false BLOCK and
        # only becoming usable on the next invocation (GA-301).
        CFC_HISTORY_REFRESH_SYNC=1 CFC_GIT_TIMEOUT="$GIT_TIMEOUT" CFC_GIT_RETRY_TIMEOUT="$GIT_TIMEOUT" CFC_GIT_MAX_WORKERS="${CONTEXT_FRESHNESS_GATE_GIT_MAX_WORKERS:-4}" \
            CONTEXT_FRESHNESS_MIN_SOURCE_COMMITS="$_min_sc" \
            bash "$CHECK_SCRIPT" --dashboard-warnings > "$tmp_cache" 2>/dev/null
        mv "$tmp_cache" "$cache_file"
        cat "$cache_file"
    else
        CFC_HISTORY_REFRESH_SYNC=1 CFC_GIT_TIMEOUT="$GIT_TIMEOUT" CFC_GIT_RETRY_TIMEOUT="$GIT_TIMEOUT" CFC_GIT_MAX_WORKERS="${CONTEXT_FRESHNESS_GATE_GIT_MAX_WORKERS:-4}" \
            CONTEXT_FRESHNESS_MIN_SOURCE_COMMITS="$_min_sc" \
            bash "$CHECK_SCRIPT" --dashboard-warnings 2>/dev/null
    fi
}

declare -A seen_paths=()
declare -A source_alerts=()
# GA-238: git log呼出しがtimeout/returncode異常でsource commit数を確定できなかった
# ("source commit check failed", context_freshness_check.shのbuild_source_check_warning)
# rel_pathを記録する。source_alertsが空のままdays_ago<=7だと従来はOK扱いへ落ちて
# 未確認状態を隠蔽していた(fail-open) — check_failed_pathsに載ったrel_pathは
# 後段の分類で必ずWARNへ倒す(fail-closed)。
declare -A check_failed_paths=()
target_rel_paths=()
while IFS= read -r warning_line; do
    [[ -n "$warning_line" ]] || continue
    rel_path=""
    if [[ "$warning_line" =~ ^(WARN|ALERT):[[:space:]]([^[:space:]]+) ]]; then
        rel_path="${BASH_REMATCH[2]}"
    fi
    [[ -n "$rel_path" ]] || continue
    if [[ "$warning_line" == ALERT:*"source commits"* ]]; then
        source_alerts["$rel_path"]="$warning_line"
    elif [[ "$warning_line" == WARN:*"source commit check failed"* ]]; then
        check_failed_paths["$rel_path"]=1
    fi
    if [[ -n "${seen_paths[$rel_path]:-}" ]]; then
        continue
    fi
    seen_paths["$rel_path"]=1
    target_rel_paths+=("$rel_path")
done < <(
    warnings_output
)

if [[ "${#target_rel_paths[@]}" -eq 0 ]]; then
    echo "--- 総合判定: OK ---"
    exit 0
fi

for rel_path in "${target_rel_paths[@]}"; do
    file="$ROOT_DIR/$rel_path"
    [[ -f "$file" ]] || continue

    basename_file=$(basename "$file")
    last_updated=""
    line_count=0
    while IFS= read -r line && (( line_count < 10 )); do
        line_count=$((line_count + 1))
        if [[ "$line" =~ last_updated:[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
            last_updated="${BASH_REMATCH[1]}"
            break
        fi
    done < "$file"

    if [[ -z "$last_updated" ]]; then
        emit_actionable \
            "WARN: ${basename_file} (last_updated 未記載)" \
            "${basename_file} に <!-- last_updated: YYYY-MM-DD --> を追記せよ。"
        HAS_WARN=1
        continue
    fi

    file_epoch=$(date -d "$last_updated" +%s 2>/dev/null) || {
        emit_actionable \
            "WARN: ${basename_file} (last_updated日付パース失敗: ${last_updated})" \
            "${basename_file} の last_updated 日付形式を YYYY-MM-DD に修正せよ。"
        HAS_WARN=1
        continue
    }
    today_epoch

    days_ago=$(( (TODAY_EPOCH - file_epoch) / 86400 ))
    record_stale_template_candidate "$rel_path" "$days_ago" "$last_updated"

    if [[ -n "${source_alerts[$rel_path]:-}" ]]; then
        missing_links="$(missing_context_links "$file" "$rel_path")"
        if [[ -n "$missing_links" ]]; then
            emit_actionable \
                "BLOCK: ${basename_file} (source更新あり・参照リンク欠落)" \
                "欠落参照を復旧してから内容とsource_commitを更新せよ: $(printf '%s' "$missing_links" | paste -sd, -)"
            HAS_BLOCK=1
            continue
        fi
        emit_actionable \
            "ALERT: ${basename_file} (source commits since last_updated=${last_updated})" \
            "$(source_commit_action "$rel_path" "${source_alerts[$rel_path]}")"
        HAS_ALERT=1
        ALERT_LIST+=("${basename_file}(source更新)")
    elif [[ -n "${check_failed_paths[$rel_path]:-}" ]]; then
        # A timeout means freshness is unknown, not stale. Keep it fail-closed
        # while distinguishing detector failure (BLOCK) from a verified source
        # change (ALERT), so operators cannot "fix" it by touching timestamps.
        emit_actionable \
            "BLOCK: ${basename_file} (source commit確認失敗: timeout/returncode。last_updated=${last_updated}, ${days_ago}日前、鮮度判定不能)" \
            "${basename_file} のsource commit確認がgit timeout/returncode異常で失敗した。個別文書のlast_updatedは変更せず、検査環境を復旧して再実行せよ。"
        HAS_BLOCK=1
    elif [[ "$days_ago" -gt 14 ]]; then
        emit_actionable \
            "WARN: ${basename_file} (${days_ago}日前更新、ソース変更なし)" \
            "${basename_file} の鮮度を確認し、必要なら更新せよ。"
        HAS_WARN=1
    elif [[ "$days_ago" -gt 7 ]]; then
        emit_actionable \
            "WARN: ${basename_file} (${days_ago}日前更新)" \
            "${basename_file} の鮮度を確認し、必要なら更新せよ。"
        HAS_WARN=1
    else
        echo "OK: ${basename_file} (${days_ago}日前更新)"
    fi
done

if [[ "$HAS_ALERT" -gt 0 && "${#ALERT_LIST[@]}" -gt 0 && -f "$NTFY_SCRIPT" ]]; then
    alert_summary=$(IFS=', '; echo "${ALERT_LIST[*]}")
    notify_context_alert "$alert_summary"
fi

if [[ "$HAS_BLOCK" -gt 0 ]]; then
    echo "--- 総合判定: BLOCK ---"
    exit 1
elif [[ "$HAS_ALERT" -gt 0 ]]; then
    emit_update_cmd_templates
    echo "--- 総合判定: ALERT ---"
    exit 1
elif [[ "$HAS_WARN" -gt 0 ]]; then
    echo "--- 総合判定: WARN ---"
    exit 2
else
    echo "--- 総合判定: OK ---"
    exit 0
fi
