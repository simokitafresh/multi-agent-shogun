#!/bin/bash
# deploy_task/state.sh — cluster B state: cache, locks, deadlines, and deferred queue.
# Function bodies are extracted verbatim from deploy_task.sh.

deploy_task_wave_cache() {
    local namespace="$1" target_key="$2" source_list="$3"
    shift 3
    local cache_root="${DEPLOY_TASK_WAVE_CACHE_DIR:-/tmp/deploy_task_wave_cache}"
    local source_fp key cache_file lock_file tmp_file
    mkdir -p "$cache_root"
    # One interpreter batches every metadata lookup.  Spawning stat/find once
    # per source on DrvFS cost seconds and could exceed the lookup itself.
    # The generation remains exact: content edits change mtime/ctime+size;
    # atomic replacement changes inode; skill additions/removals change the
    # sorted tree member set.
    source_fp="$(DEPLOY_TASK_WAVE_SOURCE_LIST="$source_list" python3 - <<'PY'
import hashlib
import os
from pathlib import Path

records = []
for source in os.environ.get("DEPLOY_TASK_WAVE_SOURCE_LIST", "").splitlines():
    if not source:
        continue
    if source.startswith("fingerprint:"):
        records.append(source)
        continue
    if source.startswith("skill-tree:"):
        root = Path(source.removeprefix("skill-tree:"))
        try:
            members = sorted(
                entry / "SKILL.md"
                for entry in root.iterdir()
                if (entry / "SKILL.md").is_file()
            )
        except OSError:
            records.append(f"missing-tree  {root}")
            continue
        for member in members:
            stat = member.stat()
            records.append(
                f"{stat.st_dev}:{stat.st_ino}:{stat.st_size}:"
                f"{stat.st_mtime_ns}:{stat.st_ctime_ns}  {member}"
            )
        continue
    try:
        stat = os.stat(source)
    except OSError:
        records.append(f"missing  {source}")
    else:
        records.append(
            f"{stat.st_dev}:{stat.st_ino}:{stat.st_size}:"
            f"{stat.st_mtime_ns}:{stat.st_ctime_ns}  {source}"
        )
payload = "\n".join(records).encode("utf-8", errors="surrogateescape")
print(hashlib.sha256(payload).hexdigest())
PY
)"
    key="$(printf '%s\0%s\0%s' "$namespace" "$source_fp" "$target_key" | sha256sum | cut -d' ' -f1)"
    cache_file="$cache_root/${namespace}_${key}.snapshot"
    lock_file="$cache_file.lock"
    if [ ! -f "$cache_file" ]; then
        exec {wave_cache_fd}>"$lock_file"
        flock -w "${DEPLOY_TASK_WAVE_CACHE_LOCK_TIMEOUT:-30}" "$wave_cache_fd" || return 1
        if [ ! -f "$cache_file" ]; then
            tmp_file=$(mktemp "$cache_root/.${namespace}.${key}.XXXXXX")
            if "$@" > "$tmp_file"; then
                mv "$tmp_file" "$cache_file"
                log "wave_cache: miss namespace=${namespace} source_fp=${source_fp} target_key=${target_key}"
            else
                rm -f "$tmp_file"
                flock -u "$wave_cache_fd"
                eval "exec ${wave_cache_fd}>&-"
                return 1
            fi
        fi
        flock -u "$wave_cache_fd"
        eval "exec ${wave_cache_fd}>&-"
    else
        log "wave_cache: hit namespace=${namespace} source_fp=${source_fp} target_key=${target_key}"
    fi
    cat "$cache_file"
}

warn_three_layer_candidate_backlog() {
    local db_path="${SHOGUN_MEMORY_DB:-$SCRIPT_DIR/data/multi_agent_shogun_memory.db}"
    local warn_threshold="${SHOGUN_THREE_LAYER_CANDIDATE_WARN_THRESHOLD:-10}"
    local counts total

    case "$warn_threshold" in
        ''|*[!0-9]*) warn_threshold=10 ;;
    esac
    [ -f "$db_path" ] || return 0

    counts="$(
        python3 - "$db_path" <<'PY' 2>/dev/null || true
import sqlite3
import sys

db_path = sys.argv[1]
states = ("obsidian_candidate", "contradiction_candidate", "duplicate_candidate")

try:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        has_events = conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='events'"
        ).fetchone() is not None
        if not has_events:
            raise SystemExit(0)
        has_state = any(row[1] == "state" for row in conn.execute("PRAGMA table_info(events)"))
        if not has_state:
            raise SystemExit(0)
        values = {
            state: int(conn.execute("SELECT COUNT(*) FROM events WHERE state = ?", (state,)).fetchone()[0] or 0)
            for state in states
        }
    finally:
        conn.close()
except Exception:
    raise SystemExit(0)

print("\t".join(str(values[state]) for state in states))
PY
    )"
    [ -n "$counts" ] || return 0

    IFS=$'\t' read -r obsidian_count contradiction_count duplicate_count <<< "$counts"
    obsidian_count="${obsidian_count:-0}"
    contradiction_count="${contradiction_count:-0}"
    duplicate_count="${duplicate_count:-0}"
    total=$((obsidian_count + contradiction_count + duplicate_count))

    if [ "$total" -gt "$warn_threshold" ] 2>/dev/null; then
        log "WARN: three_layer_candidate_backlog total=${total} threshold=${warn_threshold} obsidian_candidate=${obsidian_count} contradiction_candidate=${contradiction_count} duplicate_candidate=${duplicate_count}"
    fi
    return 0
}

deploy_task_idle_codex_ninjas() {
    local target_ninja="$1"
    local task_file candidate status

    for task_file in "$SCRIPT_DIR"/queue/tasks/*.yaml; do
        [ -f "$task_file" ] || continue
        candidate=$(basename "$task_file" .yaml)
        [ "$candidate" = "$target_ninja" ] && continue
        [ "$(cli_type "$candidate")" = "codex" ] || continue

        status=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "status" "" 2>/dev/null || true)
        status="${status,,}"
        case "$status" in
            ""|idle|unknown)
                printf '%s\n' "$candidate"
                ;;
        esac
    done
}

deploy_task_enforce_gpt_priority() {
    local target_ninja="$1"
    local deploy_scope_mode="$2"
    local target_cli idle_codex_ninjas override_reason

    [ "${DEPLOY_TASK_GPT_PRIORITY:-0}" != "0" ] || return 0
    [ "${TYPE:-task_assigned}" = "task_assigned" ] || return 0

    target_cli=$(cli_type "$target_ninja")
    [ "$target_cli" != "codex" ] || return 0

    case "${deploy_scope_mode,,}" in
        training|train|修行)
            return 0
            ;;
    esac

    idle_codex_ninjas=$(deploy_task_idle_codex_ninjas "$target_ninja" | paste -sd, -)
    [ -n "$idle_codex_ninjas" ] || return 0

    if [ "${DEPLOY_TASK_ALLOW_NON_GPT:-0}" = "1" ] || [ "${GPT_PRIORITY_OVERRIDE:-0}" = "1" ]; then
        override_reason="${DEPLOY_TASK_GPT_PRIORITY_REASON:-${GPT_PRIORITY_REASON:-}}"
        if [ -z "$override_reason" ]; then
            log "BLOCK(GPT_PRIORITY): ${target_ninja} is ${target_cli}, idle Codex ninja exists (${idle_codex_ninjas}), override reason missing"
            echo "BLOCK: GPT優先配備。${target_ninja} は非GPT(${target_cli})だが、idle GPT忍者(${idle_codex_ninjas})がいる。" >&2
            echo "Sonnetへ意図的に配備する場合は DEPLOY_TASK_ALLOW_NON_GPT=1 DEPLOY_TASK_GPT_PRIORITY_REASON='理由' を付けよ。" >&2
            return 1
        fi
        log "WARN(GPT_PRIORITY_OVERRIDE): ${target_ninja}=${target_cli}, idle_codex=${idle_codex_ninjas}, reason=${override_reason}"
        echo "WARN: GPT優先override。${target_ninja}(${target_cli})へ配備。idle GPT=${idle_codex_ninjas}。reason=${override_reason}" >&2
        return 0
    fi

    log "BLOCK(GPT_PRIORITY): ${target_ninja} is ${target_cli}, idle Codex ninja exists (${idle_codex_ninjas})"
    echo "BLOCK: GPT優先配備。${target_ninja} は非GPT(${target_cli})だが、idle GPT忍者(${idle_codex_ninjas})がいる。" >&2
    echo "GPT忍者へ配備するか、意図的にSonnetへ回す場合は DEPLOY_TASK_ALLOW_NON_GPT=1 DEPLOY_TASK_GPT_PRIORITY_REASON='理由' を付けよ。" >&2
    return 1
}

deploy_task_lock_path() {
    local lock_key="$1"
    mkdir -p "$SCRIPT_DIR/queue/locks"
    printf '%s/queue/locks/deploy_%s.lock\n' "$SCRIPT_DIR" "${lock_key//[^A-Za-z0-9_.-]/_}"
}

deploy_task_release_lock() {
    local lock_fd="$1"
    local lock_file="$2"

    [ -n "$lock_fd" ] || return 0
    flock -u "$lock_fd" || true
    eval "exec ${lock_fd}>&-"
    log "deploy_lock: released ${lock_file}"
}

DEPLOY_TASK_NINJA_LOCK_FD=""
DEPLOY_TASK_NINJA_LOCK_FILE=""

# Account for the whole serial deploy wall without spawning a profiler.  Each
# checkpoint closes the preceding interval; EXIT closes the final interval so
# the receipt can expose any still-unaccounted overhead explicitly.
DEPLOY_TASK_WALL_PHASE_LAST_US=""
DEPLOY_TASK_WALL_PHASE_SUM_MS=0
DEPLOY_TASK_WALL_PHASE_MAX_MS=0
DEPLOY_TASK_WALL_PHASE_MAX_NAME="none"

deploy_task_wall_phase_checkpoint() {
    local phase="$1" now_us wall_ms start_ms end_ms
    now_us="${EPOCHREALTIME/./}"
    now_us="${now_us:0:16}"
    if [ -n "${DEPLOY_TASK_WALL_PHASE_LAST_US:-}" ]; then
        wall_ms=$(((now_us - DEPLOY_TASK_WALL_PHASE_LAST_US + 999) / 1000))
        DEPLOY_TASK_WALL_PHASE_SUM_MS=$((DEPLOY_TASK_WALL_PHASE_SUM_MS + wall_ms))
        if [ "$wall_ms" -gt "${DEPLOY_TASK_WALL_PHASE_MAX_MS:-0}" ]; then
            DEPLOY_TASK_WALL_PHASE_MAX_MS="$wall_ms"
            DEPLOY_TASK_WALL_PHASE_MAX_NAME="$phase"
        fi
        start_ms=$(((DEPLOY_TASK_WALL_PHASE_LAST_US - DEPLOY_TASK_STARTED_US) / 1000))
        end_ms=$(((now_us - DEPLOY_TASK_STARTED_US) / 1000))
        # One append carries both interval and duration contracts.  log() opens
        # the shared 9P file, so two rows doubled the largest profiler-only
        # subphase in isolated trials without adding information.
        log "DEPLOY_WALL_EVENT name=${phase} start_ms=${start_ms} end_ms=${end_ms} DEPLOY_WALL_PHASE phase=${phase} wall_ms=${wall_ms}"
    fi
    DEPLOY_TASK_WALL_PHASE_LAST_US="$now_us"
}

deploy_task_acquire_ninja_lock() {
    local ninja_name="$1"
    local timeout_sec="${DEPLOY_TASK_NINJA_LOCK_TIMEOUT_SEC:-300}"
    case "$timeout_sec" in
        ''|*[!0-9]*) timeout_sec=300 ;;
    esac
    [ -z "$DEPLOY_TASK_NINJA_LOCK_FD" ] || return 0

    DEPLOY_TASK_NINJA_LOCK_FILE="$(deploy_task_lock_path "ninja_${ninja_name}")"
    exec {DEPLOY_TASK_NINJA_LOCK_FD}>"$DEPLOY_TASK_NINJA_LOCK_FILE"
    if ! flock -w "$timeout_sec" "$DEPLOY_TASK_NINJA_LOCK_FD"; then
        log "BLOCK: could not acquire ninja deploy lock for ${ninja_name}: ${DEPLOY_TASK_NINJA_LOCK_FILE}"
        echo "BLOCK: ${ninja_name} deploy lock busy. Retry after the current deployment finishes." >&2
        eval "exec ${DEPLOY_TASK_NINJA_LOCK_FD}>&-"
        DEPLOY_TASK_NINJA_LOCK_FD=""
        DEPLOY_TASK_NINJA_LOCK_FILE=""
        return 1
    fi
    log "ninja_deploy_lock: acquired ${DEPLOY_TASK_NINJA_LOCK_FILE}"
}

deploy_task_release_ninja_lock() {
    [ -n "$DEPLOY_TASK_NINJA_LOCK_FD" ] || return 0
    deploy_task_release_lock "$DEPLOY_TASK_NINJA_LOCK_FD" "$DEPLOY_TASK_NINJA_LOCK_FILE"
    DEPLOY_TASK_NINJA_LOCK_FD=""
    DEPLOY_TASK_NINJA_LOCK_FILE=""
}

deploy_task_retro_event_answered() {
    local event_id="$1"
    local root="$SCRIPT_DIR"
    [ -n "$event_id" ] || return 1
    python3 - "$root" "$event_id" <<'PY'
import json, re, sys
from pathlib import Path

root, event_id = sys.argv[1:]
retro = Path(root) / "queue/retro"

# E4 is the primary answer ledger.  Match the complete event_id field only;
# substring/nearby-line matches are intentionally not accepted.
answers = retro / "answers.jsonl"
if answers.exists():
    for raw in answers.read_text(encoding="utf-8").splitlines():
        try:
            item = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if item.get("event_id") == event_id:
            raise SystemExit(0)

# The live and archived Karo mailboxes are secondary persisted transports.
# Parse YAML structure and require the exact answer type plus an event-boundary
# match. inbox_archive must not turn an answered hold back into unanswered.
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

mailboxes = [Path(root) / "queue/inbox/karo.yaml"]
mailboxes.extend(sorted((Path(root) / "archive/inbox").glob("karo_*.yaml")))
pattern = re.compile(r"(?<![A-Za-z0-9_-])" + re.escape(event_id) + r"(?![A-Za-z0-9_-])")
for mailbox_path in mailboxes:
    try:
        mailbox = yaml.safe_load(mailbox_path.read_text(encoding="utf-8")) or {}
    except Exception:
        continue
    for message in mailbox.get("messages", []) if isinstance(mailbox, dict) else []:
        # 回答族は送信側(scripts/inbox_write.sh inbox_is_retro_answer_type)および
        # 判定側(scripts/retro_write.sh final-checkpoint)と同一集合でなければならない。
        # ここだけ retro_answer 厳密一致だったため、忍者が infra_bug_suspected 等で
        # 回答してもholdが解けず次の配備がBLOCKされ続けた(家老が手動復元していた真因)。
        # tests/unit/test_retro_answer_type_parity.bats が3箇所の一致を強制する。
        if not isinstance(message, dict) or message.get("type") not in {
            "retro_answer", "infra_bug_suspected", "infra_bug_report", "infra_bug",
        }:
            continue
        if message.get("event_id") == event_id or pattern.search(str(message.get("content", ""))):
            raise SystemExit(0)
raise SystemExit(1)
PY
}

deploy_task_guard_retro_answer_hold() {
    local ninja_name="$1" hold event_id
    # Caller must hold the per-ninja deploy lock. This closes the race between
    # monitor publishing the hold and a concurrent deployment transaction.
    [ -n "${DEPLOY_TASK_NINJA_LOCK_FD:-}" ] || { echo "BLOCK: retro hold guard requires ninja deploy lock" >&2; return 2; }
    for hold in "$SCRIPT_DIR"/queue/retro/verbatim_awaiting_answer/*.event; do
        [ -f "$hold" ] || continue
        [ "$(sed -n '1p' "$hold")" = "$ninja_name" ] || continue
        event_id=$(sed -n '2p' "$hold")
        if [ -n "$event_id" ] && deploy_task_retro_event_answered "$event_id"; then
            printf '%s\t%s\t%s\t%s\n' "$(date -Iseconds)" "$ninja_name" "$event_id" "answered=1 decision=PASS" >> "$SCRIPT_DIR/logs/retro_hold_gate_fire.log"
            rm -f "$hold"
            continue
        fi
        printf '%s\t%s\t%s\t%s\n' "$(date -Iseconds)" "$ninja_name" "$event_id" "answered=0 decision=BLOCK" >> "$SCRIPT_DIR/logs/retro_hold_gate_fire.log"
        echo "BLOCK: $ninja_name has an unanswered terminal retrospective; next task deployment is held" >&2
        return 2
    done
}

deploy_task_guard_checkpoint_review_hold() {
    local ninja_name="$1" manifest state worker
    [ -n "${DEPLOY_TASK_NINJA_LOCK_FD:-}" ] || { echo "BLOCK: checkpoint hold guard requires ninja deploy lock" >&2; return 2; }
    for manifest in "$SCRIPT_DIR"/queue/checkpoint_manifests/*.manifest; do
        [ -f "$manifest" ] || continue
        state=$(sed -n 's/^state=//p' "$manifest" | head -1)
        case "$state" in awaiting_artifact|ready) ;; *) continue ;; esac
        worker=$(sed -n 's/^worker=//p' "$manifest" | head -1)
        [ "$worker" = "$ninja_name" ] || continue
        echo "BLOCK: $ninja_name has a checkpoint artifact awaiting review; next task deployment is held" >&2
        return 2
    done
}

deploy_task_guard_done_report_unarchived() {
    local ninja_name="$1" parent_cmd="$2"
    local report_file gate_dir completion_tail
    [ -n "$ninja_name" ] || return 1
    [ -n "$parent_cmd" ] || return 1
    gate_dir="$SCRIPT_DIR/queue/gates/$parent_cmd"
    completion_tail="$gate_dir/completion_tail.log"
    # archive_completed.sh intentionally retains up to 10 completed reports in
    # queue/reports, while its overflow scan writes archive.done for every
    # GATE-CLEAR candidate.  A retained report is therefore logically closed
    # once the ordered cmd-complete pipeline has also reached its exact terminal
    # checkpoint; treating file existence alone as "unarchived" permanently
    # blocks that worker's next task.
    if [ -f "$gate_dir/archive.done" ] \
        && [ -f "$completion_tail" ] \
        && grep -Fqx -- "[cmd_complete] COMPLETE $parent_cmd" "$completion_tail"; then
        log "LOGICAL_ARCHIVE: ${ninja_name} ${parent_cmd} retained report is closed by archive.done + cmd_complete terminal checkpoint"
        return 1
    fi
    for report_file in "$SCRIPT_DIR/queue/reports/${ninja_name}_report_${parent_cmd}"*.yaml; do
        # archive_completed.sh keeps a temporary compatibility symlink at the
        # former active path.  The report body is already archived, so treating
        # that symlink as unarchived permanently blocks the worker's next task.
        [ -f "$report_file" ] && [ ! -L "$report_file" ] && return 0
    done
    return 1
}

deploy_task_archive_terminal_task() {
    local task_file="$1" ninja_name="$2" parent_cmd="$3"
    local archive_dir timestamp archive_file candidate
    archive_dir="$SCRIPT_DIR/queue/archive/tasks"
    timestamp=$(date '+%Y%m%dT%H%M%S%N')
    archive_file="$archive_dir/${ninja_name}_${parent_cmd}_${timestamp}.yaml"
    mkdir -p "$archive_dir" || return 1
    candidate=$(mktemp "$archive_dir/.${ninja_name}_${parent_cmd}.XXXXXX") || return 1
    if ! cp -- "$task_file" "$candidate" \
        || ! python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1], encoding="utf-8"))' "$candidate" \
        || ! mv -- "$candidate" "$archive_file"; then
        rm -f -- "$candidate"
        return 1
    fi
    log "TERMINAL_TASK_ARCHIVE: worker=${ninja_name} parent_cmd=${parent_cmd} path=${archive_file#$SCRIPT_DIR/}"
    printf '%s\n' "$archive_file"
}

deploy_task_guard_worker_assignment() {
    local task_file="$1"
    local incoming_cmd="$2"
    local current_status current_parent worker_name

    current_status=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "status" "unknown" 2>/dev/null || true)
    local owner_tx owner_subject owner_generation owner_fence owner_root owner_record owner_phase owner_record_fence owner_pointer
    owner_tx=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "owner_transaction_status" "" 2>/dev/null || true)
    if [ "$current_status" = owner_prepared ]; then
        echo "BLOCK: prepared owner is non-executable: $task_file" >&2
        return 1
    fi
    if [ "$owner_tx" = active ]; then
        owner_subject=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "owner_subject_id" "" 2>/dev/null || true)
        owner_generation=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "owner_generation" "" 2>/dev/null || true)
        owner_fence=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "owner_fence" "" 2>/dev/null || true)
        owner_root=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "owner_state_root" "" 2>/dev/null || true)
        [ -n "$owner_subject" ] && [ "$owner_generation" = "$owner_fence" ] && [ -n "$owner_root" ] || { echo "BLOCK: invalid owner fence metadata: $task_file" >&2; return 1; }
        owner_record=$(bash "$SCRIPT_DIR/scripts/lib/durable_state.sh" read "$owner_root" task_owner "$owner_subject" 2>/dev/null) || { echo "BLOCK: owner pointer unreadable: $task_file" >&2; return 1; }
        owner_phase=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("phase",""))' "$owner_record")
        owner_record_fence=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("fence_token",""))' "$owner_record")
        owner_pointer=$(python3 -c 'import json,sys; r=json.loads(sys.argv[1]); print(next((x.split(":",1)[1] for x in r.get("side_effect_ledger",[]) if x.startswith("owner_pointer:")),""))' "$owner_record")
        [ "$owner_phase" = terminal ] && [ "$owner_record_fence" = "$owner_fence" ] && [ "$(realpath "$owner_pointer")" = "$(realpath "$task_file")" ] || { echo "BLOCK: stale/non-owner task execution denied: $task_file" >&2; return 1; }
    fi
    current_parent=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
    worker_name="${NINJA_NAME:-$(basename "$task_file" .yaml)}"
    case "$current_status" in
        assigned|acknowledged|in_progress)
            if [ -n "$incoming_cmd" ] && [ "$current_parent" != "$incoming_cmd" ]; then
                log "BLOCK(GA-257): ${worker_name:-worker} already has active task ${current_parent:-unknown} (status=${current_status})"
                echo "BLOCK: ${worker_name:-worker} は ${current_parent:-unknown} を実行中/受領済み。別cmd ${incoming_cmd} で上書きしない。" >&2
                return 1
            fi
            ;;
        done|PASS)
            # B26 escape hatch (将軍裁可 blt_20260725_234849): CI REDのときGATEが通らず
            # 報告がarchiveできない。その状態でこのガードが全配備を拒むと「CI修正を
            # 配備できないからCI REDが直らない」という自己矛盾で全忍者が詰む(2026-07-25実証)。
            # ci_fixはREDを消すための弾なので、これに限り通す。他のtask_typeは従来通り拒否。
            if [ "${DEPLOY_INCOMING_TASK_TYPE:-}" != "" ] \
                && [ "$(printf '%s' "${DEPLOY_INCOMING_TASK_TYPE:-}" | tr '[:upper:]' '[:lower:]')" = "ci_fix" ] \
                && [ -n "$incoming_cmd" ] && [ -n "$current_parent" ] && [ "$current_parent" != "$incoming_cmd" ] \
                && deploy_task_guard_done_report_unarchived "$worker_name" "$current_parent"; then
                log "B26-ESCAPE(ci_fix): ${worker_name:-worker} ${current_status} task ${current_parent} has an unarchived report; allowing ${incoming_cmd} because task_type=ci_fix"
                printf '{"ts":"%s","event":"b26_ci_fix_escape","worker":"%s","held_cmd":"%s","incoming_cmd":"%s","held_status":"%s"}\n' \
                    "$(date -Is)" "${worker_name:-worker}" "$current_parent" "$incoming_cmd" "$current_status" \
                    >> "$SCRIPT_DIR/logs/defense_overhead.jsonl" 2>/dev/null || true
                return 0
            fi
            if [ -n "$incoming_cmd" ] && [ -n "$current_parent" ] && [ "$current_parent" != "$incoming_cmd" ] \
                && deploy_task_guard_done_report_unarchived "$worker_name" "$current_parent"; then
                log "BLOCK(cmd_karo_hotfix_reflux_deploy_race_20260725): ${worker_name:-worker} ${current_status} task ${current_parent} has an unarchived report; refusing overwrite by ${incoming_cmd}"
                echo "BLOCK: ${worker_name:-worker} は ${current_parent} 完了済み(status=${current_status})だが報告未archive。別cmd ${incoming_cmd} での上書きを拒否。cmd_complete/archive完了後に再試行せよ。" >&2
                bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo \
                    "配備競合BLOCK: ${worker_name:-worker} は ${current_parent}(status=${current_status})完了済みだが報告未archiveのまま、別cmd ${incoming_cmd} からの上書き配備を試行→拒否した。archive完了を確認してから再配備せよ。" \
                    reflux_conflict_block deploy_task review_reflux_conflict >/dev/null 2>&1 || true
                return 1
            fi
            ;;
    esac
}

deploy_task_start_deadline() {
    local timeout_sec="${DEPLOY_TASK_MAIN_TIMEOUT_SEC:-0}"
    case "$timeout_sec" in
        ''|*[!0-9]*) timeout_sec=0 ;;
    esac
    if [ "$timeout_sec" -gt 0 ] 2>/dev/null; then
        DEPLOY_TASK_MAIN_DEADLINE=$((SECONDS + timeout_sec))
        log "main_timeout: armed (${timeout_sec}s)"
    else
        DEPLOY_TASK_MAIN_DEADLINE=0
        log "main_timeout: disabled"
    fi
}

deploy_task_check_deadline() {
    local phase="$1"
    if [ "${DEPLOY_TASK_MAIN_DEADLINE:-0}" -gt 0 ] 2>/dev/null && [ "$SECONDS" -ge "$DEPLOY_TASK_MAIN_DEADLINE" ] 2>/dev/null; then
        log "TIMEOUT: deploy_task_main exceeded ${DEPLOY_TASK_MAIN_TIMEOUT_SEC}s at ${phase}; exiting safely"
        echo "TIMEOUT: deploy_task_main exceeded ${DEPLOY_TASK_MAIN_TIMEOUT_SEC}s at ${phase}; deployment stopped safely. Check logs/deploy_task.log and retry." >&2
        return 124
    fi
    return 0
}

# Emit one machine-readable timing record for every task-mutation subphase.
# Keep this in bash so profiling the control plane does not add another Python
# process to the path being measured.
deploy_task_mutation_phase() {
    local phase="$1"
    shift
    local started_us finished_us wall_ms rc report_scans_before report_scans_after
    started_us="${EPOCHREALTIME/./}"
    started_us="${started_us:0:16}"
    report_scans_before="${DEPLOY_TASK_REPORT_SCAN_COUNT:-0}"
    "$@"
    rc=$?
    finished_us="${EPOCHREALTIME/./}"
    finished_us="${finished_us:0:16}"
    wall_ms=$(((finished_us - started_us + 999) / 1000))
    report_scans_after="${DEPLOY_TASK_REPORT_SCAN_COUNT:-0}"
    log "TASK_MUTATION_PHASE phase=${phase} wall_ms=${wall_ms} rc=${rc} subprocesses=0 report_scans=$((report_scans_after - report_scans_before))"
    return "$rc"
}

# Record slow provenance/housekeeping work durably without delaying delivery.
# A consumer must revalidate HEAD/path or report state before acting on a row.
deploy_task_deferred_append() {
    local queue_name="$1"
    shift
    local queue_dir="$SCRIPT_DIR/queue/deferred"
    local queue_file="$queue_dir/${queue_name}.tsv"
    mkdir -p "$queue_dir"
    (
        flock -x 9
        printf '%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$queue_file"
    ) 9>"${queue_file}.lock"
}

deploy_task_queue_history_lookup() {
    deploy_task_deferred_append git_history "head=$2" "path=$3" "repo=$1"
}

deploy_task_history_cache_get() {
    local repo_root="$1" head_oid="$2" repo_relative="$3"
    local cache_dir="$SCRIPT_DIR/.cache/deploy-history" key cache_file cached_head cached_path cached_commit
    key=$(printf '%s\0%s\0%s' "$repo_root" "$head_oid" "$repo_relative" | sha256sum | awk '{print $1}')
    cache_file="$cache_dir/$key"
    [ -f "$cache_file" ] || return 1
    IFS=$'\t' read -r cached_head cached_path cached_commit < "$cache_file" || return 1
    [ "$cached_head" = "$head_oid" ] && [ "$cached_path" = "$repo_relative" ] \
        && [[ "$cached_commit" =~ ^[0-9a-f]{40}$ ]] || return 1
    printf '%s\n' "$cached_commit"
}

# cmd_4165: report_publication工程の「owner task再parse」対策。
# cProfile接地(blt_20260721_173822): report_publicationの支配項は他忍者(owner)のtask
# YAMLをparent_cmd/status確認のため毎回field_get()で2回、全量awk走査していたこと
# (299回重複parse/owner実数8人、11.6秒=工程の71.1%)。
# 設計(既承認・knowledge:8d38e090): owner task 8件をmtimeキーで1回cache
# +cache miss時はheader text scan(先頭N行のみ1pass)。ただし「同parent_cmd一致
# (PROTECT判定に直結する安全境界)」「header scan未検出(malformed境界)」の2ケースのみ
# field_get()の全量parseへfallbackし、検出境界(全列挙)は落とさない。
deploy_task_owner_cache_get() {
    local ninja="$1" mtime="$2"
    local cache_file="$SCRIPT_DIR/.cache/owner-task/${ninja}"
    local cached_mtime cached_parent cached_status
    [ -f "$cache_file" ] || return 1
    IFS=$'\t' read -r cached_mtime cached_parent cached_status < "$cache_file" || return 1
    [ "$cached_mtime" = "$mtime" ] || return 1
    printf '%s\t%s\n' "$cached_parent" "$cached_status"
}

deploy_task_owner_cache_set() {
    local ninja="$1" mtime="$2" parent="$3" status="$4"
    local cache_dir="$SCRIPT_DIR/.cache/owner-task"
    mkdir -p "$cache_dir"
    local cache_file="$cache_dir/${ninja}"
    printf '%s\t%s\t%s\n' "$mtime" "$parent" "$status" > "${cache_file}.tmp.$$"
    mv "${cache_file}.tmp.$$" "$cache_file"
}

# 先頭${max_lines}行だけを1 awk passでparent_cmd/statusを同時抽出する。
# field_get()と同じ「任意インデント許容・最初の出現優先」規約(L070準拠、2sp固定禁止)。
# 窓内に両方見つからなければ __HEADER_MISS__ を返し、呼び出し側でfull parseへfallbackさせる。
deploy_task_owner_header_scan() {
    local max_lines="$1" file="$2"
    awk -v maxl="$max_lines" '
        function trim(s) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
            gsub(/^\x27|\x27[[:space:]]*$/, "", s)
            gsub(/^"|"[[:space:]]*$/, "", s)
            return s
        }
        gp == "" && $0 ~ /^[[:space:]]*parent_cmd:/ {
            v = $0; sub(/^[[:space:]]*parent_cmd:[[:space:]]*/, "", v)
            gp = trim(v); if (gp == "") gp = "\x01"
        }
        gs == "" && $0 ~ /^[[:space:]]*status:/ {
            v = $0; sub(/^[[:space:]]*status:[[:space:]]*/, "", v)
            gs = trim(v); if (gs == "") gs = "\x01"
        }
        gp != "" && gs != "" { found = 1; exit }
        NR >= maxl { exit }
        END {
            if (found) printf "%s\t%s\n", (gp == "\x01" ? "" : gp), (gs == "\x01" ? "" : gs)
            else print "__HEADER_MISS__"
        }
    ' "$file" 2>/dev/null
}

# owner(他忍者)のtask YAMLからparent_cmd/statusを取得する。出力: "parent_cmd<TAB>status" 1行。
deploy_task_owner_task_lookup() {
    local other_ninja="$1" other_task_file="$2" current_parent_cmd="$3"
    local mtime
    mtime=$(stat -c '%Y' "$other_task_file" 2>/dev/null) || { printf '\t\n'; return 1; }

    local cached
    cached=$(deploy_task_owner_cache_get "$other_ninja" "$mtime")
    if [ -n "$cached" ]; then
        printf '%s\n' "$cached"
        return 0
    fi

    local scan parent status need_full=0
    scan=$(deploy_task_owner_header_scan 200 "$other_task_file")
    if [ "$scan" = "__HEADER_MISS__" ]; then
        need_full=1
    else
        IFS=$'\t' read -r parent status <<< "$scan"
        [ "$parent" = "$current_parent_cmd" ] && need_full=1
    fi

    if [ "$need_full" -eq 1 ]; then
        parent=$(field_get "$other_task_file" "parent_cmd" "" 2>/dev/null || true)
        status=$(field_get "$other_task_file" "status" "" 2>/dev/null || true)
    fi

    deploy_task_owner_cache_set "$other_ninja" "$mtime" "$parent" "$status"
    printf '%s\t%s\n' "$parent" "$status"
}

deploy_task_queue_stale_report() {
    deploy_task_deferred_append stale_reports "path=$1" "parent=$2" "verdict=${3:-empty}"
}

# Queue lesson injection counters by deployment attempt/task generation.  The
# counter is provenance telemetry, not a deployment gate, so rewriting the two
# large lesson archives must not delay task delivery.  A durable done marker
# makes enqueue idempotent even when the same attempt is re-entered while a
# prior row is being drained.
deploy_task_queue_lesson_scores() {
    local task_file="$1" project="$2" ids="$3"
    local parent_cmd task_id ac_version attempt_key event_key queue_file done_dir ids_csv
    [ -n "$project" ] && [ -n "$ids" ] || return 0

    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" parent_cmd task_id ac_version 2>/dev/null)" || true
    attempt_key="${DEPLOY_TASK_ISSUE_ATTEMPT_ID:-${parent_cmd:-unknown}:${task_id:-unknown}:${BASHPID}}"
    ids_csv=$(printf '%s\n' "$ids" | awk '{$1=$1; gsub(/[[:space:]]+/, ","); print}')
    event_key=$(printf '%s\0%s\0%s\0%s\0%s\0%s' \
        "$attempt_key" "${parent_cmd:-}" "${task_id:-}" "${ac_version:-}" "$project" "$ids_csv" \
        | sha256sum | awk '{print $1}')
    queue_file="$SCRIPT_DIR/queue/deferred/lesson_scores.tsv"
    done_dir="$SCRIPT_DIR/.cache/deploy-lesson-scores"
    mkdir -p "$(dirname "$queue_file")" "$done_dir"

    (
        flock -x 9
        [ ! -f "$done_dir/${event_key}.done" ] || exit 0
        if [ -f "$queue_file" ] && awk -F '\t' -v key="$event_key" '$2 == key { found=1; exit } END { exit !found }' "$queue_file"; then
            exit 0
        fi
        printf '%s\t%s\t%s\t%s\n' \
            "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$event_key" "$project" "$ids_csv" >> "$queue_file"
    ) 9>"${queue_file}.lock"
    log "injection_count: deferred project=${project} ids=${ids_csv} event=${event_key}"
}

# Apply all increments for one project under one lock and one archive rewrite.
# Repeated lesson IDs intentionally add more than one: distinct deployment
# attempts retain the historical injection_count semantics when batched.
deploy_task_batch_lesson_score_update() {
    local project="$1"
    shift
    local archive fallback lock_file tmp_file ts spec="" id
    local -A deltas=()
    [ "$#" -gt 0 ] || return 0
    for id in "$@"; do
        [[ "$id" =~ ^[A-Za-z0-9_.-]+$ ]] || return 1
        deltas["$id"]=$(( ${deltas["$id"]:-0} + 1 ))
    done
    for id in "${!deltas[@]}"; do
        spec+="${spec:+,}${id}=${deltas[$id]}"
    done

    archive="$SCRIPT_DIR/projects/${project}/lessons_archive.yaml"
    fallback="$SCRIPT_DIR/projects/${project}/lessons.yaml"
    [ -f "$archive" ] || archive="$fallback"
    [ -f "$archive" ] || return 1
    lock_file="${archive}.lock"
    ts="$(date '+%Y-%m-%dT%H:%M:%S')"
    tmp_file="$(mktemp "${archive}.XXXXXX.tmp")" || return 1

    if (
        flock -w 10 200 || exit 1
        awk -v spec="$spec" -v ts="$ts" '
function flush_target() {
    if (current == "") return
    if (!count_done) print "  injection_count: " delta[current]
    if (!ts_done) print "  last_referenced: \047" ts "\047"
    current=""
}
BEGIN {
    n=split(spec, pairs, ",")
    for (i=1; i<=n; i++) {
        split(pairs[i], kv, "=")
        wanted[kv[1]]=1
        delta[kv[1]]=kv[2]+0
    }
}
{
    line=$0
    sub(/\r$/, "", line)
    if (line ~ /^- id:[[:space:]]*/) {
        flush_target()
        lesson_id=line
        sub(/^- id:[[:space:]]*/, "", lesson_id)
        gsub(/^[\047"]|[\047"]$/, "", lesson_id)
        if (lesson_id in wanted) {
            current=lesson_id
            found[lesson_id]=1
            count_done=0
            ts_done=0
        }
        print
        next
    }
    if (current != "" && line != "" && line !~ /^[ \t#]/) {
        flush_target()
        print
        next
    }
    if (current != "" && line ~ /^  injection_count:[[:space:]]*[0-9]+/) {
        value=line
        sub(/^  injection_count:[[:space:]]*/, "", value)
        print "  injection_count: " (value + delta[current])
        count_done=1
        next
    }
    if (current != "" && line ~ /^  last_referenced:/) {
        print "  last_referenced: \047" ts "\047"
        ts_done=1
        next
    }
    print
}
END {
    flush_target()
    missing=0
    for (lesson_id in wanted) {
        if (!(lesson_id in found)) {
            print "ERROR: " lesson_id " not found in " FILENAME > "/dev/stderr"
            missing=1
        }
    }
    if (missing) exit 1
}
' "$archive" > "$tmp_file" || exit 1
        mv "$tmp_file" "$archive"
    ) 200>"$lock_file"; then
        return 0
    fi
    rm -f "$tmp_file"
    return 1
}

deploy_task_rotate_deferred_queue() {
    local queue_file="$1" work_file="$2"
    (
        flock -x 9
        [ -s "$queue_file" ] || exit 1
        mv "$queue_file" "$work_file"
    ) 9>"${queue_file}.lock"
}

deploy_task_drain_deferred() {
    local queue_dir="$SCRIPT_DIR/queue/deferred" drain_lock="$SCRIPT_DIR/queue/locks/deploy_deferred_drain.lock"
    local history_q="$queue_dir/git_history.tsv" stale_q="$queue_dir/stale_reports.tsv" lesson_q="$queue_dir/lesson_scores.tsv"
    local processed=0 skipped=0 failed=0 backlog=0 line repo head_oid rel commit key cache_dir cache_file
    mkdir -p "$(dirname "$drain_lock")" "$SCRIPT_DIR/archive/reports/stale" "$SCRIPT_DIR/.cache/deploy-history"
    exec {drain_fd}>"$drain_lock"
    flock -n "$drain_fd" || return 0

    local history_work="${history_q}.work.$BASHPID"
    if deploy_task_rotate_deferred_queue "$history_q" "$history_work"; then
        while IFS= read -r line; do
            repo=$(printf '%s\n' "$line" | sed -n 's/.* repo=//p')
            head_oid=$(printf '%s\n' "$line" | sed -n 's/.*head=\([^ ]*\).*/\1/p')
            rel=$(printf '%s\n' "$line" | sed -n 's/.* path=\([^ ]*\) repo=.*/\1/p')
            if [ -n "$repo" ] && [ -n "$head_oid" ] && [ -n "$rel" ] \
                && [ "$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)" = "$head_oid" ] \
                && git -C "$repo" cat-file -e "HEAD:${rel}" 2>/dev/null \
                && commit=$(timeout 30 git -C "$repo" log -1 --format='%H' -- "$rel" 2>/dev/null) \
                && [[ "$commit" =~ ^[0-9a-f]{40}$ ]]; then
                key=$(printf '%s\0%s\0%s' "$repo" "$head_oid" "$rel" | sha256sum | awk '{print $1}')
                cache_file="$SCRIPT_DIR/.cache/deploy-history/$key"
                printf '%s\t%s\t%s\n' "$head_oid" "$rel" "$commit" > "${cache_file}.tmp.$BASHPID"
                mv "${cache_file}.tmp.$BASHPID" "$cache_file"
                processed=$((processed + 1))
            else
                skipped=$((skipped + 1))
            fi
        done < "$history_work"
        rm -f "$history_work"
    fi

    local stale_work="${stale_q}.work.$BASHPID" report parent verdict worker task_parent task_status dest
    if deploy_task_rotate_deferred_queue "$stale_q" "$stale_work"; then
        while IFS= read -r line; do
            report=$(printf '%s\n' "$line" | sed -n 's/.*path=\([^ ]*\) parent=.*/\1/p')
            parent=$(printf '%s\n' "$line" | sed -n 's/.* parent=\([^ ]*\) verdict=.*/\1/p')
            [ -f "$report" ] || { skipped=$((skipped + 1)); continue; }
            verdict=$(FIELD_GET_NO_LOG=1 field_get "$report" verdict "" 2>/dev/null || true)
            worker=$(basename "$report"); worker="${worker%%_report_*}"
            task_parent=$(FIELD_GET_NO_LOG=1 field_get "$SCRIPT_DIR/queue/tasks/${worker}.yaml" parent_cmd "" 2>/dev/null || true)
            task_status=$(FIELD_GET_NO_LOG=1 field_get "$SCRIPT_DIR/queue/tasks/${worker}.yaml" status "" 2>/dev/null || true)
            if [[ "$verdict" =~ ^(PASS|FAIL|PASS_NO_IMPROVEMENT)$ ]] \
                || { [ "$task_parent" = "$parent" ] && [[ "$task_status" =~ ^(assigned|acknowledged|in_progress)$ ]]; }; then
                skipped=$((skipped + 1)); continue
            fi
            dest="$SCRIPT_DIR/archive/reports/stale/$(basename "$report")"
            [ ! -e "$dest" ] || dest="${dest%.yaml}_$(date +%s%N).yaml"
            mv "$report" "$dest" && processed=$((processed + 1)) || failed=$((failed + 1))
        done < "$stale_work"
        rm -f "$stale_work"
    fi

    local lesson_work="${lesson_q}.work.$BASHPID" lesson_done_dir="$SCRIPT_DIR/.cache/deploy-lesson-scores"
    local event_key project ids extra marker row
    local -a batch_ids=()
    local -A lesson_rows=() lesson_ids=() lesson_seen=()
    mkdir -p "$lesson_done_dir"
    if deploy_task_rotate_deferred_queue "$lesson_q" "$lesson_work"; then
        while IFS=$'\t' read -r _ts event_key project ids extra; do
            row=$(printf '%s\t%s\t%s\t%s' "$_ts" "$event_key" "$project" "$ids")
            if [ -n "$extra" ] || [[ ! "$event_key" =~ ^[0-9a-f]{64}$ ]] || [ -z "$project" ] || [ -z "$ids" ]; then
                lesson_rows["__invalid__"]+="${row}"$'\n'
                failed=$((failed + 1))
                continue
            fi
            marker="$lesson_done_dir/${event_key}.done"
            if [ -f "$marker" ] || [ -n "${lesson_seen[$event_key]:-}" ]; then
                skipped=$((skipped + 1))
                continue
            fi
            lesson_seen["$event_key"]=1
            lesson_rows["$project"]+="${row}"$'\n'
            lesson_ids["$project"]+="${ids//,/ } "
        done < "$lesson_work"
        rm -f "$lesson_work"

        for project in "${!lesson_rows[@]}"; do
            if [ "$project" = "__invalid__" ]; then
                while IFS= read -r row; do
                    [ -n "$row" ] || continue
                    ( flock -x 9; printf '%s\n' "$row" >> "$lesson_q" ) 9>"${lesson_q}.lock"
                done <<< "${lesson_rows[$project]}"
                continue
            fi
            read -r -a batch_ids <<< "${lesson_ids[$project]}"
            if deploy_task_batch_lesson_score_update "$project" "${batch_ids[@]}"; then
                while IFS=$'\t' read -r _ts event_key _project ids; do
                    [ -n "$event_key" ] || continue
                    printf '%s\t%s\t%s\n' "$_ts" "$_project" "$ids" \
                        > "$lesson_done_dir/${event_key}.done.tmp.$BASHPID"
                    mv "$lesson_done_dir/${event_key}.done.tmp.$BASHPID" \
                        "$lesson_done_dir/${event_key}.done"
                    processed=$((processed + 1))
                done <<< "${lesson_rows[$project]}"
            else
                while IFS= read -r row; do
                    [ -n "$row" ] || continue
                    ( flock -x 9; printf '%s\n' "$row" >> "$lesson_q" ) 9>"${lesson_q}.lock"
                done <<< "${lesson_rows[$project]}"
                failed=$((failed + 1))
            fi
        done
    fi
    backlog=$(find "$queue_dir" -maxdepth 1 -name '*.tsv' -type f -exec awk 'END{n+=NR} END{print n+0}' {} \; 2>/dev/null | awk '{s+=$1} END{print s+0}')
    log "DEFERRED_DRAIN processed=${processed} skipped=${skipped} failed=${failed} backlog=${backlog}"
}

deploy_task_start_deferred_drain() {
    ( deploy_task_drain_deferred ) >/dev/null 2>&1 &
    log "deferred_drain: started single-flight pid=$!"
}

