#!/bin/bash
# deploy_task/gates.sh — cluster I freshness, scout, quality/RC gates, and task mutation.
# Function bodies are extracted verbatim from deploy_task.sh.

# ─── context鮮度チェック（穴2対策: cmd_239） ───
# cmd_1393: Python2箇所→awk+date変換
check_context_freshness() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        return 0
    fi

    local project
    project=$(field_get "$task_file" "project" "")
    if [ -z "$project" ]; then
        log "context_freshness: SKIP (no project field)"
        return 0
    fi

    local projects_yaml="$SCRIPT_DIR/config/projects.yaml"
    if [ ! -f "$projects_yaml" ]; then
        log "context_freshness: SKIP (projects.yaml not found)"
        return 0
    fi

    # Python→awk: projects.yamlからproject IDに対応するcontext_fileを取得
    local context_file
    context_file=$(awk -v proj="$project" '
        /^[[:space:]]*- id:/ { sub(/.*- id:[[:space:]]*/, ""); gsub(/[[:space:]]*$/, ""); cur_id = $0 }
        /^[[:space:]]*context_file:/ {
            if (cur_id == proj) {
                sub(/.*context_file:[[:space:]]*/, "")
                gsub(/[[:space:]]*$/, "")
                gsub(/^["'"'"']|["'"'"']$/, "")
                print
                exit
            }
        }
    ' "$projects_yaml" 2>/dev/null)

    if [ -z "$context_file" ]; then
        log "context_freshness: SKIP (no context_file for project=$project)"
        return 0
    fi

    local full_path="$SCRIPT_DIR/$context_file"
    if [ ! -f "$full_path" ]; then
        log "context_freshness: WARNING (file not found: $context_file)"
        echo "⚠️ WARNING: $context_file not found" >&2
        return 0
    fi

    local last_updated
    last_updated=$(grep -o 'last_updated: [0-9-]*' "$full_path" 2>/dev/null | head -1 | cut -d' ' -f2)

    if [ -z "$last_updated" ]; then
        log "context_freshness: ⚠️ WARNING: $context_file has no last_updated metadata"
        echo "⚠️ WARNING: $context_file has no last_updated metadata (date unknown)" >&2
        return 0
    fi

    # Python→date: 日付差分計算
    local days_old=-1
    local lu_epoch today_epoch
    lu_epoch=$(date -d "$last_updated" +%s 2>/dev/null) || true
    today_epoch=$(date +%s)
    if [ -n "$lu_epoch" ]; then
        days_old=$(( (today_epoch - lu_epoch) / 86400 ))
    fi

    if [ "$days_old" -ge 14 ] 2>/dev/null; then
        log "context_freshness: ⚠️ WARNING: $context_file last updated ${days_old} days ago"
        echo "⚠️ WARNING: $context_file last updated ${days_old} days ago" >&2
    else
        log "context_freshness: OK ($context_file updated ${days_old} days ago)"
    fi

    return 0
}

# ─── 入口門番: 前タスクの教訓未消化チェック ───
# cmd_1393: Python→awk変換
check_entrance_gate() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "entrance_gate: PASS (task file not found: $task_file)"
        return 0
    fi

    # awk: related_lessonsセクション内でreviewed: falseを持つエントリのIDを収集
    local result
    result=$(awk '
        BEGIN { in_rl=0; cur_id=""; rev_false=0 }
        /^  related_lessons:/ { in_rl=1; next }
        in_rl && /^  [a-z_]/ && !/^  -/ { in_rl=0 }
        in_rl && /^  - / {
            if (rev_false && cur_id!="") printf "%s, ",cur_id
            cur_id=""; rev_false=0
        }
        in_rl && /    id:/ { sub(/.*id:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); cur_id=$0 }
        in_rl && /    reviewed:[[:space:]]*false/ { rev_false=1 }
        END { if (rev_false && cur_id!="") printf "%s",cur_id }
    ' "$task_file" 2>/dev/null)

    if [ -n "$result" ]; then
        # trailing ", " を除去
        result="${result%, }"
        log "BLOCK: ${NINJA_NAME}の前タスクにreviewed:false残存 [${result}]。教訓を消化してから再配備せよ"
        echo "BLOCK: ${NINJA_NAME}の前タスクにreviewed:false残存 [${result}]。教訓を消化してから再配備せよ" >&2
        exit 1
    fi

    log "entrance_gate: PASS (no unreviewed lessons)"
    return 0
}

# Validate an explicit cross-command scout hand-off.  The ordinary scout gate
# deliberately counts only live tasks with the same parent_cmd; completed
# scouts are routinely archived and their workers reused, so an impl task may
# instead name the exact reviewed reports it consumes.
validate_explicit_scout_reports() {
    local task_file="$1"
    # Keep the common legacy path shell-only.  Python/YAML validation is paid
    # only by tasks that explicitly opt into cross-command report reuse.
    if ! grep -qE '^[[:space:]]{2}scout_reports:[[:space:]]*' "$task_file" 2>/dev/null; then
        return 3
    fi
    python3 - "$task_file" "$SCRIPT_DIR" <<'PY'
import pathlib
import sys

import yaml

task_path = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2]).resolve()


def block(reason):
    print(f"BLOCK(scout_reports): {reason}", file=sys.stderr)
    raise SystemExit(1)


try:
    task_doc = yaml.safe_load(task_path.read_text(encoding="utf-8")) or {}
except (OSError, yaml.YAMLError) as exc:
    block(f"task YAML unreadable: {exc}")
task = task_doc.get("task", task_doc)
if not isinstance(task, dict):
    block("task mapping missing")
if "scout_reports" not in task:
    raise SystemExit(3)

raw_paths = task.get("scout_reports")
if not isinstance(raw_paths, list) or len(raw_paths) < 2:
    block("at least two explicit report paths are required")

allowed_roots = tuple(
    (root / rel).resolve()
    for rel in ("queue/reports", "queue/archive/reports", "archive/reports")
)
reports = []
resolved_paths = set()
report_ids = set()
for index, raw_path in enumerate(raw_paths):
    if not isinstance(raw_path, str) or not raw_path.strip():
        block(f"entry[{index}] must be a non-empty repo-relative path")
    lexical = pathlib.PurePosixPath(raw_path.strip())
    if lexical.is_absolute() or ".." in lexical.parts:
        block(f"entry[{index}] is outside repo scope: {raw_path}")
    candidate = (root / lexical).resolve()
    try:
        candidate.relative_to(root)
    except ValueError:
        block(f"entry[{index}] resolves outside repo: {raw_path}")
    if not any(candidate == base or base in candidate.parents for base in allowed_roots):
        block(f"entry[{index}] is not under an approved report directory: {raw_path}")
    if candidate in resolved_paths:
        block(f"duplicate report path: {raw_path}")
    resolved_paths.add(candidate)
    if not candidate.is_file():
        block(f"report missing: {raw_path}")
    try:
        report = yaml.safe_load(candidate.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError) as exc:
        block(f"report unreadable ({raw_path}): {exc}")
    if not isinstance(report, dict):
        block(f"report is not a mapping: {raw_path}")
    report_id = str(report.get("report_id") or "").strip()
    if not report_id:
        block(f"report_id missing: {raw_path}")
    if report_id in report_ids:
        block(f"duplicate report_id: {report_id}")
    report_ids.add(report_id)
    status = str(report.get("status") or "").strip().lower()
    if status != "completed":
        block(f"report status is not completed ({raw_path}): {status or 'missing'}")
    task_type = str(report.get("task_type") or "").strip().lower()
    if task_type not in {"scout", "recon"}:
        block(f"report task_type is not scout/recon ({raw_path}): {task_type or 'missing'}")
    verdict = str(report.get("verdict") or "").strip().upper()
    if verdict not in {"PASS", "PASS_NO_IMPROVEMENT"}:
        block(f"report verdict is not PASS-family ({raw_path}): {verdict or 'missing'}")
    cmd_id = str(report.get("parent_cmd") or "").strip()
    if not cmd_id.startswith("cmd_"):
        block(f"report parent_cmd missing or invalid: {raw_path}")
    reports.append((raw_path, cmd_id))

metrics_path = root / "logs/gate_metrics.log"
latest_gate = {}
try:
    for line in metrics_path.read_text(encoding="utf-8").splitlines():
        parts = line.split("\t")
        if len(parts) >= 3:
            latest_gate[parts[1].strip()] = parts[2].strip().upper()
except OSError as exc:
    block(f"gate metrics unreadable: {exc}")

review_path = root / "logs/gunshi_review_log.yaml"
try:
    review_doc = yaml.safe_load(review_path.read_text(encoding="utf-8")) or []
except (OSError, yaml.YAMLError) as exc:
    block(f"gunshi review log unreadable: {exc}")
if not isinstance(review_doc, list):
    block("gunshi review log is not a list")

latest_review = {}
for raw_entry in review_doc:
    if not isinstance(raw_entry, dict):
        continue
    entry = raw_entry.get("review", raw_entry)
    if not isinstance(entry, dict):
        continue
    if str(entry.get("review_type") or "").strip().lower() != "report":
        continue
    cmd_id = str(entry.get("cmd_id") or "").strip()
    if cmd_id:
        latest_review[cmd_id] = str(entry.get("verdict") or "").strip().upper()

for raw_path, cmd_id in reports:
    if latest_gate.get(cmd_id) != "CLEAR":
        block(f"latest gate is not CLEAR ({raw_path}): {latest_gate.get(cmd_id, 'missing')}")
    if latest_review.get(cmd_id) != "LGTM":
        block(f"latest gunshi report review is not LGTM ({raw_path}): {latest_review.get(cmd_id, 'missing')}")

print(f"PASS: explicit scout_reports={len(reports)} distinct_report_ids={len(report_ids)}")
PY
}

# ─── 偵察ゲート: implタスクは偵察済みorscout_exempt必須 ───
# cmd_1393: check_scout_gate Python→bash/awk化
check_scout_gate() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "scout_gate: PASS (task file not found)"
        return 0
    fi

    # 0. 完了済みタスクはscout_gate再検査不要 — PASS
    local task_status
    task_status=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "status" "")
    case "$task_status" in
        done|idle|completed)
            log "scout_gate: PASS: status=${task_status} (completed task, skip re-check)"
            return 0
            ;;
    esac

    # 1. task_typeがimpl以外ならPASS（typeフィールドではなくtask_typeのみ参照）
    local task_type
    task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "")
    if [ "$task_type" != "impl" ]; then
        log "scout_gate: PASS: task_type=${task_type} (not impl)"
        return 0
    fi

    # 2. parent_cmd取得
    local parent_cmd
    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "")
    if [ -z "$parent_cmd" ]; then
        log "scout_gate: PASS: no parent_cmd"
        return 0
    fi

    # 3. shogun_to_karo.yamlでscout_exempt確認
    local stk_path="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
    if [ -f "$stk_path" ]; then
        local _se
        _se=$(awk -v cmd="$parent_cmd" '
            /^  [a-zA-Z_].*:$/ { sub(/^[[:space:]]*/, ""); sub(/:$/, ""); cur_id=$0 }
            /^[[:space:]]*-?[[:space:]]*id:[[:space:]]/ { s=$0; sub(/.*id:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); if (s ~ /^cmd_/) cur_id=s }
            cur_id == cmd && /scout_exempt:[[:space:]]*true/ { print "true"; exit }
        ' "$stk_path" 2>/dev/null)
        if [ "$_se" = "true" ]; then
            log "scout_gate: PASS: scout_exempt=true for ${parent_cmd}"
            return 0
        fi
    fi

    # 3.1 karo_direct cmd is not present in shogun_to_karo.yaml; trust task-local exemption.
    local task_scout_exempt
    task_scout_exempt=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "scout_exempt" "" 2>/dev/null || true)
    if [ "$task_scout_exempt" = "true" ]; then
        log "scout_gate: PASS: scout_exempt=true in task YAML for ${parent_cmd}"
        return 0
    fi

    # 3.5 研究cmd自動scout_exempt: q4_depth=shallow → 本番コード変更なし (LK057)
    if [ -f "$stk_path" ]; then
        local _q4
        _q4=$(awk -v cmd="$parent_cmd" '
            /^  [a-zA-Z_].*:$/ { sub(/^[[:space:]]*/, ""); sub(/:$/, ""); cur_id=$0 }
            cur_id == cmd && /q4_depth:/ { sub(/.*q4_depth:[[:space:]]*"?/, ""); sub(/"?[[:space:]]*—.*/, ""); print; exit }
        ' "$stk_path" 2>/dev/null)
        if [ "$_q4" = "shallow" ]; then
            log "scout_gate: PASS: q4_depth=shallow (research cmd auto-exempt, LK057)"
            return 0
        fi
    fi

    # 4. report_merge.doneチェック
    if [ -f "$SCRIPT_DIR/queue/gates/${parent_cmd}/report_merge.done" ]; then
        log "scout_gate: PASS: report_merge.done exists for ${parent_cmd}"
        return 0
    fi

    # 4.5 Explicitly reused, fully completed scouts from other parent commands.
    # Absence (rc=3) preserves the historical same-parent counting contract;
    # a present but invalid list always fails closed.
    local _explicit_scout_output="" _explicit_scout_rc=0
    _explicit_scout_output=$(validate_explicit_scout_reports "$task_file" 2>&1) || _explicit_scout_rc=$?
    case "$_explicit_scout_rc" in
        0)
            log "scout_gate: ${_explicit_scout_output}"
            return 0
            ;;
        3)
            ;;
        *)
            log "${_explicit_scout_output}"
            echo "${_explicit_scout_output}" >&2
            return 1
            ;;
    esac

    # 5. scout/reconタスクのdone数カウント
    local done_count=0
    local _tf
    for _tf in "$SCRIPT_DIR/queue/tasks/"*.yaml; do
        [ -f "$_tf" ] || continue
        local _pcmd _tid _tst
        _pcmd=$(awk '/^  parent_cmd:/ { sub(/.*parent_cmd:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; exit }' "$_tf" 2>/dev/null)
        [ "$_pcmd" = "$parent_cmd" ] || continue
        _tid=$(awk '/^  task_id:/ { sub(/.*task_id:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; exit }' "$_tf" 2>/dev/null)
        _tid=$(echo "$_tid" | tr '[:upper:]' '[:lower:]')
        case "$_tid" in
            *scout*|*recon*)
                _tst=$(awk '/^  status:/ { sub(/.*status:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; exit }' "$_tf" 2>/dev/null)
                if [ "$_tst" = "done" ]; then
                    done_count=$((done_count + 1))
                fi
                ;;
        esac
    done

    if [ "$done_count" -ge 2 ]; then
        log "scout_gate: PASS: ${done_count} scout/recon tasks done for ${parent_cmd}"
        return 0
    fi

    # BLOCK
    log "BLOCK(scout_gate): ${parent_cmd} — scout done=${done_count}/2, scout_exempt=false"
    echo "BLOCK(scout_gate): 偵察未完了。scout_reportsが2件未満かつscout_exemptなし。将軍にscout_exempt申請するか、先に偵察を配備せよ" >&2
    echo "詳細: ${parent_cmd} — scout done=${done_count}/2, scout_exempt=false" >&2
    exit 1
}

# ─── 教訓注入postcondition（cmd_378: 事後不変条件） ───
postcondition_lesson_inject() {
    local task_file="$1"
    local postcond_file
    deploy_task_postcondition_prepare "$task_file"
    postcond_file="$DEPLOY_TASK_POSTCOND_FILE"

    if [ ! -f "$postcond_file" ]; then
        # inject early exit (no project/no lessons) → postcond data not written → OK
        deploy_task_postcondition_cleanup
        return 0
    fi

    local available injected task_id
    available=$(grep '^available=' "$postcond_file" 2>/dev/null | head -1 | cut -d= -f2)
    injected=$(grep '^injected=' "$postcond_file" 2>/dev/null | head -1 | cut -d= -f2)
    task_id=$(grep '^task_id=' "$postcond_file" 2>/dev/null | head -1 | cut -d= -f2)
    deploy_task_postcondition_cleanup

    available="${available:-0}"
    injected="${injected:-0}"
    task_id="${task_id:-unknown}"

    if [ "$available" -gt 0 ] 2>/dev/null && [ "$injected" -eq 0 ] 2>/dev/null; then
        log "[deploy] WARN: 教訓注入ゼロ (available=${available} injected=0 task=${task_id})"
    else
        log "[deploy] OK: 教訓注入 (available=${available} injected=${injected} task=${task_id})"
    fi

    return 0
}

# ─── 初回配備開始ntfy（cmd_496） ───
# 同一cmdで1回のみ通知。再配備・追配備では送信しない。
mark_dispatch_ntfy_once() {
    local cmd_id="$1"
    local ninja_name="$2"
    local title="$3"
    local state_dir="$SCRIPT_DIR/queue/dispatch_ntfy_started"
    local marker="$state_dir/${cmd_id}.started"
    local ts
    ts="$(date '+%Y-%m-%dT%H:%M:%S')"

    mkdir -p "$state_dir"

    # Atomic create: 成功した呼び出しだけが通知を送信する
    if ( set -o noclobber; : > "$marker" ) 2>/dev/null; then
        cat > "$marker" <<EOF
timestamp: ${ts}
cmd_id: ${cmd_id}
ninja: ${ninja_name}
title: ${title}
EOF
        return 0
    fi

    return 1
}

resolve_dispatch_title() {
    local cmd_id="$1"
    local task_file="$2"
    local title=""
    local yaml_file=""

    if [ -f "$task_file" ]; then
        title=$(field_get "$task_file" "title" "")
    fi

    if [ -z "$title" ] && [[ -n "$cmd_id" && "$cmd_id" == cmd_* ]]; then
        # 1. Check shogun_to_karo.yaml (single file, dict format: "  cmd_XXXX:")
        local stk="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
        if [ -f "$stk" ]; then
            title=$(awk -v key="  ${cmd_id}:" '
                index($0, key) == 1 { found = 1; next }
                found && /^    title:/ {
                    sub(/^[[:space:]]*title:[[:space:]]*/, "")
                    sub(/[[:space:]]+#.*$/, "")
                    print
                    exit
                }
                found && /^  [^ ]/ { exit }
            ' "$stk" 2>/dev/null || true)
        fi

        # 2. If not found, locate archive file by filename glob (O(1))
        if [ -z "$title" ]; then
            yaml_file=$(find "$SCRIPT_DIR/queue/archive/cmds/" -maxdepth 1 -name "${cmd_id}_*.yaml" -print -quit 2>/dev/null)
            if [ -n "$yaml_file" ]; then
                title=$(awk '/^[[:space:]]*title:/ {
                    sub(/^[[:space:]]*title:[[:space:]]*/, "")
                    sub(/[[:space:]]+#.*$/, "")
                    print
                    exit
                }' "$yaml_file" 2>/dev/null || true)
            fi
        fi
    fi

    title=$(printf '%s' "$title" \
        | tr '\n' ' ' \
        | tr '\r' ' ' \
        | sed 's/^["'\'']//; s/["'\'']$//' \
        | awk '{gsub(/[[:space:]]+/, " "); sub(/^ /, ""); sub(/ $/, ""); print}')

    if [ "${#title}" -gt 80 ]; then
        title="${title:0:77}..."
    fi

    echo "$title"
}

# 消火キーワードtitle検知: cmdのtitleが消火系キーワードを含む場合にWARNING出力（cmd_1807）
# 家老経路(deploy_task.sh)でcmd_save.sh(将軍経路)と同一キーワードをカバーする
check_firefighting_title() {
    local cmd_id="$1"
    local task_file="$2"
    local title
    title=$(resolve_dispatch_title "$cmd_id" "$task_file")
    if [ -z "$title" ]; then
        return 0
    fi
    if echo "$title" | grep -qiE "$FIREFIGHTING_PATTERN"; then
        echo "⚠️ WARNING: 消火cmdを検知。真因と再発防止を検討せよ (title: ${title})" >&2
        log "firefighting_title_warn: ${cmd_id} title='${title}'"
    fi
}

count_task_acceptance_criteria() {
    local task_file="$1"
    local cmd_id="${2:-}"
    python3 - "$task_file" "$cmd_id" "$SCRIPT_DIR" <<'PY'
import sys
import os
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)
from pathlib import Path

task_file = sys.argv[1]
cmd_id = sys.argv[2].strip()
script_dir = Path(sys.argv[3])
count = 0

import re

def count_description_value(desc):
    if isinstance(desc, list):
        return len(desc)
    if isinstance(desc, dict):
        ac_keys = [k for k in desc if re.match(r'^AC\d+$', str(k))]
        if ac_keys:
            return len(ac_keys)
        return len(desc)
    if isinstance(desc, str) and desc.strip():
        ac_matches = re.findall(r'\bAC\d+\b', desc)
        return len(set(ac_matches)) if ac_matches else 1
    return 0

def count_acs_from_value(acs):
    """Count ACs: list→len, dict AC keys, description wrapper, str AC patterns."""
    if isinstance(acs, list):
        if len(acs) == 1 and isinstance(acs[0], dict):
            ac_keys = [k for k in acs[0] if re.match(r'^AC\d+$', k)]
            if ac_keys:
                return len(ac_keys)
        return len(acs)
    if isinstance(acs, dict):
        ac_keys = [k for k in acs if re.match(r'^AC\d+$', str(k))]
        if ac_keys:
            return len(ac_keys)
        desc_count = count_description_value(acs.get('description', ''))
        if desc_count:
            return desc_count if len(acs) == 1 else max(desc_count, 1)
        return max(len(acs), 1)
    if isinstance(acs, str) and acs.strip():
        ac_matches = re.findall(r'\bAC\d+\b', acs)
        return len(set(ac_matches)) if ac_matches else 1
    return 0

def count_acs_from_text(text, cmd_id=""):
    """Count only the acceptance_criteria block when full YAML parsing fails."""
    lines = text.splitlines()
    scopes = [(0, len(lines))]
    if cmd_id:
        cmd_pattern = re.compile(rf'^(\s*){re.escape(cmd_id)}:\s*(?:#.*)?$')
        for idx, line in enumerate(lines):
            match = cmd_pattern.match(line)
            if not match:
                continue
            cmd_indent = len(match.group(1))
            end = len(lines)
            for j in range(idx + 1, len(lines)):
                if lines[j].strip() and len(lines[j]) - len(lines[j].lstrip()) <= cmd_indent:
                    end = j
                    break
            scopes = [(idx + 1, end)]
            break

    for start, end in scopes:
        ac_start = None
        ac_indent = 0
        for idx in range(start, end):
            match = re.match(r'^(\s*)acceptance_criteria:\s*(?:#.*)?$', lines[idx])
            if match:
                ac_start = idx + 1
                ac_indent = len(match.group(1))
                break
        if ac_start is None:
            continue

        block = []
        for line in lines[ac_start:end]:
            if line.strip() and len(line) - len(line.lstrip()) <= ac_indent:
                break
            block.append(line)

        list_items = [
            line for line in block
            if re.match(r'^\s*-\s+(?:id:|description:|\S+)', line)
        ]
        if list_items:
            return len(list_items)

        ac_keys = set()
        for line in block:
            match = re.match(r'^\s*(AC\d+):\s*', line)
            if match:
                ac_keys.add(match.group(1))
        if ac_keys:
            return len(ac_keys)

        ac_matches = re.findall(r'\bAC\d+\b', "\n".join(block))
        if ac_matches:
            return len(set(ac_matches))
    return 0

try:
    with open(task_file, encoding='utf-8') as f:
        task_text = f.read()
    data = yaml.safe_load(task_text) or {}
    task = data.get('task') or {}
    acs = task.get('acceptance_criteria')
    count = count_acs_from_value(acs)
except Exception:
    try:
        with open(task_file, encoding='utf-8') as f:
            count = count_acs_from_text(f.read())
    except Exception:
        count = 0

if count <= 0 and cmd_id:
    search_files = [
        script_dir / "queue" / "shogun_to_karo.yaml",
    ]
    archive_dir = script_dir / "queue" / "archive" / "cmds"
    if archive_dir.is_dir():
        search_files.extend(sorted(archive_dir.glob(f"{cmd_id}_*.yaml"), reverse=True))

    for path in search_files:
        try:
            text = path.read_text(encoding='utf-8')
            data = yaml.safe_load(text) or {}
        except Exception:
            try:
                count = count_acs_from_text(text, cmd_id)
            except Exception:
                count = 0
            if count > 0:
                break
            continue

        commands = data.get("commands") or {}
        if isinstance(commands, dict):
            cmd = commands.get(cmd_id) or {}
        elif isinstance(commands, list):
            cmd = next((c for c in commands if str(c.get("id", "")).strip() == cmd_id), {})
        else:
            cmd = {}

        acs = cmd.get("acceptance_criteria")
        count = count_acs_from_value(acs)

        if count > 0:
            break

print(count)
PY
}

# 殿裁定(2026-08-14): 忍者ACにdoc laneの仕事を混ぜない。
# context境界更新・gist同期・計画書/文書更新は将軍laneへ戻す。DOC laneの
# 所有権はtaskのtarget_path/planned_pathsで判定し、AC本文の自然言語は検査しない。
deploy_task_guard_doc_update_ac() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    if task_targets_are_documentation_only "$task_file"; then
        log "BLOCK(DOC_LANE_ROUTING): target_path is documentation-owned"
        echo "BLOCK: task target_path is documentation-owned; doc update is not a ninja lane. Route the documentation update to the shogun doc lane." >&2
        return 2
    fi
    return 0
}

mark_draft_review_once() {
    local cmd_id="$1"
    local ninja_name="$2"
    local title="$3"
    local state_dir="$SCRIPT_DIR/queue/draft_review_started"
    local marker="$state_dir/${cmd_id}.draft_review.started"
    local ts
    ts="$(date '+%Y-%m-%dT%H:%M:%S')"

    mkdir -p "$state_dir"

    if ( set -o noclobber; : > "$marker" ) 2>/dev/null; then
        cat > "$marker" <<EOF
timestamp: ${ts}
cmd_id: ${cmd_id}
ninja: ${ninja_name}
title: ${title}
EOF
        return 0
    fi

    return 1
}

draft_review_already_completed() {
    local cmd_id="$1"
    local review_log="$SCRIPT_DIR/logs/gunshi_review_log.yaml"

    [ -n "$cmd_id" ] || return 1
    [ -f "$review_log" ] || return 1

    awk -v cmd="$cmd_id" '
        /^[[:space:]]*-[[:space:]]*cmd_id:[[:space:]]*/ { in_cmd=0 }
        $0 ~ "^[[:space:]]*-[[:space:]]*cmd_id:[[:space:]]*[\"'\'']?" cmd "[\"'\'']?[[:space:]]*$" {
            in_cmd=1
            next
        }
        in_cmd && /^[[:space:]]*verdict:[[:space:]]*[A-Za-z_]+/ {
            found=1
            exit
        }
        END { exit found ? 0 : 1 }
    ' "$review_log"
}

maybe_notify_draft_review() {
    local task_file="$1"
    local cmd_id="$2"
    local ninja_name="$3"
    local deploy_type="${4:-task_assigned}"
    local title ac_count message quality_contract

    if [ "$deploy_type" != "task_assigned" ]; then
        log "draft_review: SKIP (type=${deploy_type})"
        return 0
    fi

    if [ "${SKIP_DRAFT_REVIEW:-0}" = "1" ]; then
        log "draft_review: SKIP (env)"
        return 0
    fi

    if [ -z "$cmd_id" ]; then
        log "draft_review: SKIP (cmd_id empty)"
        return 0
    fi

    if draft_review_already_completed "$cmd_id"; then
        log "draft_review: SKIP (already reviewed: ${cmd_id})"
        return 0
    fi

    title=$(resolve_dispatch_title "$cmd_id" "$task_file")
    if printf '%s' "$title" | grep -q 'CI RED'; then
        log "draft_review: SKIP (CI RED)"
        return 0
    fi

    quality_contract="$(deploy_task_quality_contract_result "$task_file")"
    log "draft_review quality_contract: ${quality_contract}"

    if ! ac_count=$(count_task_acceptance_criteria "$task_file" "$cmd_id"); then
        log "draft_review: WARN (ac_count unavailable; sending review)"
        ac_count=2
    elif ! [[ "$ac_count" =~ ^[0-9]+$ ]]; then
        log "draft_review: WARN (ac_count invalid: ${ac_count:-empty}; sending review)"
        ac_count=2
    fi
    if ! mark_draft_review_once "$cmd_id" "$ninja_name" "${title:-$cmd_id}"; then
        log "draft_review: SKIP (already sent)"
        return 0
    fi

    message="draft ${cmd_id} レビュー依頼。${title:-$cmd_id}。ninja=${ninja_name}。"
    if bash "$SCRIPT_DIR/scripts/inbox_write.sh" gunshi "$message" review_draft karo review_request; then
        log "draft_review: SENT (gunshi)"
    else
        log "draft_review: WARN (inbox_write failed)"
    fi
}

# Direct/karo_direct tasks do not traverse cmd_save. Normalize task YAML to a
# standalone block, then apply the same detector-quality evaluator as draft review.
deploy_task_quality_contract_result() {
    local task_file="$1"
    local task_block applicable action fp
    [[ -f "$task_file" ]] || { printf 'UNAVAILABLE'; return 0; }
    task_block="$(python3 - "$task_file" <<'PY' 2>/dev/null
import io, sys, yaml
class CanonicalProjectionDumper(yaml.SafeDumper):
    # The shared line-oriented evaluator treats indentation as the section
    # boundary. Keep sequence items nested beneath their mapping key.
    def increase_indent(self, flow=False, indentless=False):
        return super().increase_indent(flow, False)

try:
    data = yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}
    task = data.get('task', data)
    if isinstance(task, dict):
        # The shared evaluator only needs the detector-relevant text. Emit a
        # deterministic canonical-YAML projection to stdout; never write back
        # to the operational task. Python repr loses YAML nesting and makes
        # structured AC/quality_gate text invisible to the shared evaluator.
        keys = ('project', 'title', 'purpose', 'command', 'acceptance_criteria', 'quality_gate')
        projection = {key: task[key] for key in keys if task.get(key) not in (None, '', [], {})}
        stream = io.StringIO()
        dumper = CanonicalProjectionDumper(
            stream,
            allow_unicode=True,
            default_flow_style=False,
            sort_keys=False,
            width=4096,
        )
        try:
            dumper.open()
            dumper.represent(projection)
            dumper.close()
        finally:
            dumper.dispose()
        print(stream.getvalue(), end='')
except Exception:
    pass
PY
)"
    IFS=$'\t' read -r applicable action fp < <(gate_hook_quality_contract_evaluate "$task_block")
    [[ "$applicable" == "yes" ]] || { printf 'NOT_APPLICABLE'; return 0; }
    if [[ "$action" == "pass" && "$fp" == "pass" ]]; then
        printf 'PASS'
    else
        printf 'WARN(action=%s,fp=%s)' "$action" "$fp"
    fi
}

deploy_task_direct_quality_contract_precheck() {
    local task_file="$1"
    local result
    result="$(deploy_task_quality_contract_result "$task_file")"
    case "$result" in
        WARN*)
            log "BLOCK(QUALITY_CONTRACT): ${result}"
            echo "BLOCK: direct deployment detector quality contract failed: ${result}" >&2
            return 1
            ;;
        *)
            log "quality_contract: ${result}"
            return 0
            ;;
    esac
}

# Ten minutes is a planning target, while fifteen minutes is the hard boundary.
# Between them, keep naturally atomic work together only with an explicit split
# decision.  Beyond fifteen minutes, require measured long-runtime evidence.
# Keep this read-only and before publish/task mutation so rejection has no side effects.
deploy_task_ten_min_contract_precheck() {
    local task_file="$1"
    local cmd_id="${2:-}"
    local result rc

    deploy_task_guard_doc_update_ac "$task_file" || return $?

    local cmd_args=()
    [[ -n "$cmd_id" ]] && cmd_args=(--cmd-id "$cmd_id")
    result="$(python3 "$SCRIPT_DIR/scripts/lib/time_contract_validator.py" \
        "${cmd_args[@]}" "$task_file")" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -ne 0 ]; then
        log "BLOCK(TEN_MIN_CONTRACT): ${result}"
        echo "BLOCK: natural-boundary task contract failed: ${result}" >&2
        return 2
    fi
    log "ten_min_contract: ${result}"
    return 0
}

# Validate the immutable deployment source before reset_stale_fields or publish.
# A rejected deployment must leave the worker's existing task byte-identical.
deploy_task_source_contract_precheck() {
    local source_file="$1"
    local cmd_id="${2:-}"

    [ -f "$source_file" ] || {
        log "BLOCK(SOURCE_CONTRACT): source not found: ${source_file}"
        echo "BLOCK: deployment source not found: ${source_file}" >&2
        return 2
    }
    deploy_task_ten_min_contract_precheck "$source_file" "$cmd_id" || return $?

    # Level5: automatically derive the shard manifest at the common deployment entrance.
    # Worker shortage is deferred, never silently collapsed to a single worker.
    local shard_id shard_output shard_result shard_rc=0
    local -a shard_args
    shard_id="${cmd_id:-$(basename "$source_file" .yaml)}"
    shard_output="$SCRIPT_DIR/queue/shard_manifests/${shard_id}.json"
    shard_args=("$source_file")
    if [ -n "$cmd_id" ]; then
        shard_args+=(--block-id "$cmd_id")
    fi
    shard_result="$(python3 "$SCRIPT_DIR/scripts/lib/universal_shard_contract.py" \
        "${shard_args[@]}" --tasks-dir "$SCRIPT_DIR/queue/tasks" \
        --output "$shard_output" 2>&1)" || shard_rc=$?
    if [ "$shard_rc" -ne 0 ]; then
        log "BLOCK(UNIVERSAL_SHARD): ${shard_result}"
        echo "$shard_result" >&2
        return 2
    fi
    log "universal_shard: ${shard_result}"
}

capture_done_redeploy_context() {
    local task_file="$1"
    local requested_cmd="${2:-}"
    local ninja_name prev_status prev_parent_cmd prev_report_path prev_report_filename prev_task_id prev_ac_task_id

    export _DEPLOY_DONE_REUSE=0
    export _DEPLOY_DONE_REPORT_PATH=""
    export _DEPLOY_DONE_PARENT_CMD=""
    export _DEPLOY_DONE_TASK_ID=""
    export _DEPLOY_DONE_AC_TASK_ID=""

    [ -f "$task_file" ] || return 0

    ninja_name=$(basename "$task_file" .yaml)
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" \
        status parent_cmd report_path report_filename task_id _ac_task_id 2>/dev/null)" || true

    prev_status="${status:-}"
    prev_parent_cmd="${parent_cmd:-}"
    prev_report_path="${report_path:-}"
    prev_report_filename="${report_filename:-}"
    prev_task_id="${task_id:-}"
    prev_ac_task_id="${_ac_task_id:-}"

    [ "$prev_status" = "done" ] || return 0
    [ -n "$requested_cmd" ] || requested_cmd="$prev_parent_cmd"
    [ -n "$requested_cmd" ] || return 0
    [ "$prev_parent_cmd" = "$requested_cmd" ] || return 0

    if [ -z "$prev_report_path" ] && [ -n "$prev_report_filename" ]; then
        prev_report_path="queue/reports/${prev_report_filename}"
    fi
    if [ -z "$prev_report_path" ] && [ -n "$prev_parent_cmd" ]; then
        prev_report_path="queue/reports/${ninja_name}_report_${prev_parent_cmd}.yaml"
    fi
    if [ -n "$prev_report_path" ] && [ ! -f "$SCRIPT_DIR/$prev_report_path" ]; then
        prev_report_path=""
    fi

    export _DEPLOY_DONE_REUSE=1
    export _DEPLOY_DONE_REPORT_PATH="$prev_report_path"
    export _DEPLOY_DONE_PARENT_CMD="$prev_parent_cmd"
    export _DEPLOY_DONE_TASK_ID="$prev_task_id"
    export _DEPLOY_DONE_AC_TASK_ID="$prev_ac_task_id"
    log "done_redeploy_capture: cmd=${prev_parent_cmd} report=${prev_report_path:-none} task_id=${prev_task_id:-none} ac_task_id=${prev_ac_task_id:-none}"
}

should_skip_same_cmd_resolve() {
    local task_file="$1"
    local requested_cmd="$2"
    local ninja_name="${3:-}"
    local prev_status prev_parent_cmd prev_task_id prev_report_path prev_report_filename

    [ -f "$task_file" ] || return 1
    [ -n "$requested_cmd" ] || return 1

    # Partial field extraction can succeed even when the task document is
    # malformed.  Reusing that document would skip stale reset/atomic --yaml
    # publication and make the corruption unrecoverable (GA-258).
    if ! python3 -c "import sys,yaml; yaml.safe_load(open(sys.argv[1], encoding='utf-8'))" "$task_file" >/dev/null 2>&1; then
        log "same_cmd_redeploy: task YAML invalid; force repair path for ${requested_cmd}"
        return 1
    fi

    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" \
        status parent_cmd task_id report_path report_filename 2>/dev/null)" || true

    prev_status="${status:-}"
    prev_parent_cmd="${parent_cmd:-}"
    prev_task_id="${task_id:-}"
    prev_report_path="${report_path:-}"
    prev_report_filename="${report_filename:-}"

    [ "$prev_parent_cmd" = "$requested_cmd" ] || return 1
    case "$prev_status" in
        assigned|acknowledged) ;;
        *) return 1 ;;
    esac
    [ -n "$prev_task_id" ] || return 1

    if [ -z "$prev_report_path" ] && [ -n "$prev_report_filename" ]; then
        prev_report_path="queue/reports/${prev_report_filename}"
    fi
    if [ -z "$prev_report_path" ] && [ -n "$ninja_name" ]; then
        prev_report_path="queue/reports/${ninja_name}_report_${requested_cmd}.yaml"
    fi
    [ -n "$prev_report_path" ] || return 1
    [ -f "$SCRIPT_DIR/$prev_report_path" ] || return 1

    log "cmd_resolve: SKIP duplicate same-cmd deploy (${requested_cmd} → ${ninja_name:-unknown}); reusing existing task YAML"
    return 0
}

deploy_task_direct_formal_rc_refresh_report() {
    local task_file="$1"
    local requested_cmd="$2"
    local ninja_name="$3"
    local source_file="${4:-}"
    local current_parent source_parent report_path report_filename

    [ "${DIRECT_MODE:-false}" = true ] || return 1
    [ -f "$task_file" ] || return 1
    [ -f "$source_file" ] || return 1
    [ -n "$requested_cmd" ] || return 1

    current_parent=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
    source_parent=$(FIELD_GET_NO_LOG=1 field_get "$source_file" "parent_cmd" "" 2>/dev/null || true)
    [ "$current_parent" = "$requested_cmd" ] || return 1
    [ "$source_parent" = "$requested_cmd" ] || return 1

    report_path=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "report_path" "" 2>/dev/null || true)
    report_filename=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "report_filename" "" 2>/dev/null || true)
    if [ -z "$report_path" ] && [ -n "$report_filename" ]; then
        report_path="queue/reports/$report_filename"
    fi
    [ -n "$report_path" ] || report_path="queue/reports/${ninja_name}_report_${requested_cmd}.yaml"
    [[ "$report_path" = /* ]] || report_path="$SCRIPT_DIR/$report_path"
    [ -f "$report_path" ] || return 1

    deploy_task_has_formal_karo_rc_for_report \
        "$requested_cmd" "$ninja_name" "$report_path" "$task_file" || return 1
    printf '%s\n' "$report_path"
}

inject_done_redeploy_hints() {
    local task_file="$1"
    local report_path report_filename existing_desc note

    [ "${_DEPLOY_DONE_REUSE:-0}" = "1" ] || return 0
    [ -f "$task_file" ] || return 0

    # test-speedの各roundは同一parent_cmdでもreport identityが別物。
    # 汎用done再配備hintでR2+をR1へ戻すと過去報告を上書きするため、生成器の明示契約を優先する。
    if deploy_task_speed_campaign_report_is_explicit "$task_file"; then
        log "done_redeploy_hint: SKIP explicit speed campaign round report"
        return 0
    fi

    report_path="${_DEPLOY_DONE_REPORT_PATH:-}"
    [ -n "$report_path" ] || return 0

    note="【再配備引継ぎ】 前回報告(${report_path})の files_modified/binary_checks を引継ぎ済み。前回結果を参照し、差分のみ再検証せよ。"
    existing_desc=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "description" "" 2>/dev/null || true)
    if [[ "$existing_desc" != *"【再配備引継ぎ】"* ]]; then
        if [ -n "$existing_desc" ]; then
            yaml_field_set "$task_file" "task" "description" "${note} | ${existing_desc}" || true
        else
            yaml_field_set "$task_file" "task" "description" "$note" || true
        fi
    fi

    report_filename=$(basename "$report_path")
    yaml_field_set "$task_file" "task" "report_path" "$report_path" || true
    if [ -n "$report_filename" ]; then yaml_field_set "$task_file" "task" "report_filename" "$report_filename" || true; fi
    log "done_redeploy_hint: reused report=${report_path}"
}

warn_same_ninja_redeploy() {
    local task_file="$1"
    local ninja_name="$2"
    local parent_cmd="${3:-}"
    local report_file report_status report_verdict reason_text=""
    local -a reasons=()

    [ -f "$task_file" ] || return 0
    [ -n "$ninja_name" ] || return 0

    if [ -z "$parent_cmd" ]; then
        parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
    fi
    [ -n "$parent_cmd" ] || return 0

    if [ -n "${_DEPLOY_PREV_PARENT_CMD:-}" ] && [ "$_DEPLOY_PREV_PARENT_CMD" = "$parent_cmd" ]; then
        reasons+=("同一parent_cmd再投入")
    fi
    if [ -n "${_DEPLOY_PREV_SESSION_STATE:-}" ]; then
        reasons+=("session_state残存")
    fi

    report_file="$SCRIPT_DIR/queue/reports/${ninja_name}_report_${parent_cmd}.yaml"
    if [ -f "$report_file" ]; then
        report_status=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "status" "" 2>/dev/null || true)
        report_verdict=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "verdict" "" 2>/dev/null || true)
        if [ -z "$report_verdict" ] || [ "$report_verdict" = "FAIL" ] || [ "$report_status" != "completed" ]; then
            reasons+=("同忍者の既存報告あり")
        fi
    fi

    [ "${#reasons[@]}" -gt 0 ] || return 0

    reason_text=$(printf '%s\n' "${reasons[@]}" | awk 'NF{printf "%s%s", sep, $0; sep=", "} END{print ""}')
    echo "WARNING: same-ninja redeploy (${parent_cmd} → ${ninja_name}) を検出。${reason_text}。mizchi Red flag『同じsubagentを使い回そう』の可能性あり。別忍者配備か、記憶依存でない理由を確認せよ" >&2
    log "same_ninja_redeploy_warn: cmd=${parent_cmd} ninja=${ninja_name} reasons=${reason_text}"
}

# 直近24hの非cmd commit検知: target_pathの直近コミットmessageにcmd_が無ければWARN
# 殿承認GP-110修正版: 忍者完了パスに依存せず、配備直前のgit実態をその場で確認する
warn_recent_noncmd_commit_targets() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local _tp_raw
    _tp_raw=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "target_path" "" 2>/dev/null)
    [ -n "$_tp_raw" ] || return 0

    local _repo_root
    _repo_root=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)
    [ -n "$_repo_root" ] || return 0

    local -a _tp_paths=()
    if echo "$_tp_raw" | grep -q '^- '; then
        while IFS= read -r _tp_line; do
            local _tp_p="${_tp_line#- }"
            _tp_p="${_tp_p#[[:space:]]}"
            _tp_p="${_tp_p%[[:space:]]}"
            [ -n "$_tp_p" ] && _tp_paths+=("$_tp_p")
        done <<< "$_tp_raw"
    else
        _tp_paths+=("$_tp_raw")
    fi

    local _tp_path _git_path _head_oid

    for _tp_path in "${_tp_paths[@]}"; do
        [ -n "$_tp_path" ] || continue
        _git_path="$_tp_path"
        if [[ "$_git_path" = "$_repo_root/"* ]]; then
            _git_path="${_git_path#"$_repo_root/"}"
        elif [[ "$_git_path" = /* ]]; then
            continue
        fi

        _head_oid=$(git -C "$_repo_root" rev-parse HEAD 2>/dev/null || true)
        deploy_task_queue_history_lookup "$_repo_root" "$_head_oid" "$_git_path"
    done
    log "recent_noncmd_commit_warn: deferred generation-aware history inspection targets=${#_tp_paths[@]}"
}

# q11_not_already_done再確認: cmd起票後のauto-commit等で既実装が混入していないか配備直前にWARNする。
warn_q11_not_already_done_drift() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local parent_cmd stk_path py_output
    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
    [ -n "$parent_cmd" ] || return 0

    stk_path="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
    [ -f "$stk_path" ] || return 0

    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env \
        TASK_FILE_ENV="$task_file" \
        STK_PATH_ENV="$stk_path" \
        SCRIPT_DIR_ENV="$SCRIPT_DIR" \
        PARENT_CMD_ENV="$parent_cmd" \
        python3 - <<'Q11_RECHECK_PY'; then
import os
import re
import subprocess
import sys

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

task_file = os.environ['TASK_FILE_ENV']
stk_path = os.environ['STK_PATH_ENV']
script_dir = os.environ['SCRIPT_DIR_ENV']
parent_cmd = os.environ['PARENT_CMD_ENV']

try:
    with open(stk_path, encoding='utf-8') as f:
        stk = yaml.safe_load(f) or {}
    with open(task_file, encoding='utf-8') as f:
        task_doc = yaml.safe_load(f) or {}
except Exception as exc:
    print(f'[Q11_RECHECK] WARN: failed to read YAML: {exc}', file=sys.stderr)
    sys.exit(1)

cmd = ((stk.get('commands') or {}).get(parent_cmd) or {})
if not isinstance(cmd, dict):
    sys.exit(0)

q11 = ((cmd.get('quality_gate') or {}).get('q11_not_already_done') or cmd.get('q11_not_already_done') or '')
q11 = str(q11 or '').strip()
if not q11:
    sys.exit(0)

pattern_match = re.search(r"grep\s+(?:-[A-Za-z0-9]+\s+)*(['\"])(.*?)\1", q11)
expected_match = re.search(r'([0-9]+)\s*件', q11)
if not pattern_match or not expected_match:
    sys.exit(0)

pattern = pattern_match.group(2)
expected_count = int(expected_match.group(1))

task = task_doc.get('task') if isinstance(task_doc.get('task'), dict) else task_doc
target_value = task.get('target_path') if isinstance(task, dict) else None
if isinstance(target_value, str):
    target_paths = [target_value] if target_value.strip() else []
elif isinstance(target_value, list):
    target_paths = [str(p) for p in target_value if str(p).strip()]
else:
    target_paths = []

total_hits = 0
checked_paths = []
for raw_path in target_paths:
    path = raw_path.strip()
    full_path = path if os.path.isabs(path) else os.path.join(script_dir, path)
    if not os.path.isfile(full_path):
        continue
    proc = subprocess.run(
        ['grep', '-n', pattern, full_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    if proc.returncode not in (0, 1):
        continue
    hits = len([line for line in proc.stdout.splitlines() if line])
    total_hits += hits
    checked_paths.append(path)

if checked_paths and total_hits > expected_count:
    print(
        f'WARNING: q11_not_already_done drift ({parent_cmd}) 起票時 {expected_count}件 → '
        f'配備時 {total_hits}件。target_path={", ".join(checked_paths)} pattern={pattern!r}。'
        ' HEADに先行実装が混入した可能性あり。配備続行/中止を判断せよ',
        file=sys.stderr,
    )
Q11_RECHECK_PY
        log "WARN: q11_not_already_done recheck failed for ${parent_cmd} (non-fatal)"
        return 0
    fi
    rm -f "$py_output"
}

# タスク明瞭性WARNING: 配備前に静的不明瞭さを軽量検査
# cmd_2122: BLOCKではなくWARNINGで、家老が配備前にtask品質の粗さを可視化する。
warn_task_clarity() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local parent_cmd stk_path py_output
    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
    [ -n "$parent_cmd" ] || return 0

    stk_path="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
    [ -f "$stk_path" ] || return 0

    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env \
        TASK_FILE_ENV="$task_file" \
        STK_PATH_ENV="$stk_path" \
        SCRIPT_DIR_ENV="$SCRIPT_DIR" \
        PARENT_CMD_ENV="$parent_cmd" \
        python3 - <<'TASK_CLARITY_PY'; then
import os
import re
import sys

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

task_file = os.environ['TASK_FILE_ENV']
stk_path = os.environ['STK_PATH_ENV']
script_dir = os.environ['SCRIPT_DIR_ENV']
parent_cmd = os.environ['PARENT_CMD_ENV']

try:
    with open(stk_path, encoding='utf-8') as f:
        stk = yaml.safe_load(f) or {}
except Exception as exc:
    print(f'[TASK_CLARITY] WARN: failed to read shogun_to_karo.yaml: {exc}', file=sys.stderr)
    sys.exit(1)

cmd = ((stk.get('commands') or {}).get(parent_cmd) or {})
if not isinstance(cmd, dict):
    sys.exit(0)

command_text = str(cmd.get('command', '') or '')
if not command_text.strip():
    sys.exit(0)

def ac_descriptions(value):
    descs = []
    if isinstance(value, list):
        for item in value:
            if isinstance(item, dict):
                desc = item.get('description') or item.get('check') or item.get('title') or ''
            else:
                desc = str(item or '')
            desc = str(desc).strip()
            m = re.match(r'^AC[0-9A-Za-z_-]+:\s*(.+)$', desc)
            if m:
                desc = m.group(1).strip()
            if desc:
                descs.append(desc)
    elif isinstance(value, dict):
        for item in value.values():
            if isinstance(item, dict):
                desc = item.get('description') or item.get('check') or item.get('title') or ''
            else:
                desc = str(item or '')
            desc = str(desc).strip()
            if desc:
                descs.append(desc)
    elif value:
        descs.append(str(value).strip())
    return descs

ac_descs = ac_descriptions(cmd.get('acceptance_criteria') or cmd.get('ac') or [])
command_lines = [line.strip() for line in command_text.splitlines() if line.strip()]

if len(command_lines) >= 10 and len(ac_descs) <= 1:
    print(
        f'WARNING: task clarity ({parent_cmd}) command {len(command_lines)}行に対してAC {len(ac_descs)}件。'
        ' commandが長くACが粗いため、タスクが不明瞭な可能性あり',
        file=sys.stderr,
    )

known_roots = (
    'scripts/', 'queue/', 'context/', 'projects/', 'docs/', 'config/', 'memory/',
    'logs/', 'lib/', 'tests/', 'archive/', 'instructions/',
)
known_exts = ('.sh', '.yaml', '.yml', '.md', '.py', '.json', '.toml', '.txt')
path_candidates = []
for raw in re.findall(r'(?<![A-Za-z0-9_])(?:/mnt/[^\s`"\'(),]+|[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+)', command_text):
    cand = raw.strip().rstrip('.,:;)]}')
    if not cand or cand.startswith(('http://', 'https://')):
        continue
    if not (cand.startswith('/mnt/') or cand.startswith(known_roots) or cand.endswith(known_exts)):
        continue
    if cand not in path_candidates:
        path_candidates.append(cand)

missing = []
for cand in path_candidates:
    full = cand if os.path.isabs(cand) else os.path.join(script_dir, cand)
    if not os.path.exists(full):
        missing.append(cand)

if missing:
    print(
        f'WARNING: task clarity ({parent_cmd}) command内の参照パスが実在しない可能性: '
        + ', '.join(missing),
        file=sys.stderr,
    )

if ac_descs and not any(('確認' in desc) or ('検証' in desc) for desc in ac_descs):
    print(
        f'WARNING: task clarity ({parent_cmd}) ACに「確認」「検証」が含まれない。'
        ' 行動のみで確認欠落の可能性あり',
        file=sys.stderr,
    )
TASK_CLARITY_PY
        log "WARN: task clarity check failed for ${parent_cmd} (non-fatal)"
        return 0
    fi
    rm -f "$py_output"
}

notify_initial_deploy_ntfy_once() {
    local task_file="$1"
    local ninja_name="$2"
    local cmd_id
    local title
    local message

    if [ ! -f "$task_file" ]; then
        log "dispatch_ntfy: SKIP (task file not found)"
        return 0
    fi

    cmd_id=$(field_get "$task_file" "parent_cmd" "")
    title=$(resolve_dispatch_title "$cmd_id" "$task_file")

    if [[ -z "$cmd_id" || "$cmd_id" != cmd_* ]]; then
        log "dispatch_ntfy: SKIP (parent_cmd missing or invalid: ${cmd_id:-none})"
        return 0
    fi

    if ! mark_dispatch_ntfy_once "$cmd_id" "$ninja_name" "$title"; then
        log "dispatch_ntfy: SKIP already notified (${cmd_id})"
        return 0
    fi

    message="初回配備開始 (title=${title:-(untitled)}, ninja=${ninja_name})"

    bash "$SCRIPT_DIR/scripts/ntfy_cmd.sh" "$cmd_id" "$message" &
    local ntfy_pid=$!
    log "dispatch_ntfy: sent (${cmd_id}) title='${title:-untitled}' ninja=${ninja_name} [bg:${ntfy_pid}]"

    return 0
}

deploy_task_apply_task_mutations() {
    local ninja_name="${1:-$NINJA_NAME}"
    local task_file="${2:-$SCRIPT_DIR/queue/tasks/${ninja_name}.yaml}"
    local task_status

    # 全injectorを同一dirの作業copyへ適用し、全validation PASS後に1回だけ公開する。
    # 後段FAIL時は実taskのbytes/SHAを不変に保つ。
    if [ "${DEPLOY_TASK_MUTATION_CANDIDATE:-0}" != "1" ]; then
        local mutation_candidate
        mutation_candidate=$(mktemp "${task_file}.mutation.XXXXXX") || return 1
        if ! cp -- "$task_file" "$mutation_candidate"; then
            rm -f "$mutation_candidate"
            return 1
        fi
        if ! DEPLOY_TASK_MUTATION_CANDIDATE=1 deploy_task_apply_task_mutations "$ninja_name" "$mutation_candidate"; then
            rm -f "$mutation_candidate"
            return 1
        fi
        if [ "${DEPLOY_TASK_TEST_FAIL_AFTER_MUTATIONS:-0}" = "1" ]; then
            rm -f "$mutation_candidate"
            return 1
        fi
        if ! deploy_task_guard_task_yaml_syntax "mutation_candidate_pre_publish" "$mutation_candidate" "$ninja_name"; then
            rm -f "$mutation_candidate"
            return 1
        fi
        if ! mv -f -- "$mutation_candidate" "$task_file"; then
            rm -f "$mutation_candidate"
            return 1
        fi
        return 0
    fi

    if [ "${DEPLOY_TASK_TEST_MUTATE_AND_FAIL:-0}" = "1" ]; then
        printf '\n  test_partial_mutation: true\n' >>"$task_file"
        return 1
    fi

    task_status=$(field_get "$task_file" "status" "unknown")

    if [ "$task_status" = "pending" ] || [ "$task_status" = "unknown" ]; then
        yaml_field_set "$task_file" "task" "status" "assigned"
        log "status_force: ${task_status} → assigned (Stage 1保護対象化)"
        task_status="assigned"
    fi

    DEPLOY_TASK_REPORT_SCAN_COUNT=0
    deploy_task_mutation_phase entrance_gates check_entrance_gate "$task_file" || return $?
    deploy_task_mutation_phase scout_gate check_scout_gate "$task_file" || return $?

    inject_task_id "$task_file" || true
    infer_ac_assigned_from_chunk_task_id "$task_file" || true
    inject_ac_assigned_from_stk "$task_file" || true  # cmd_2790: STK cmd定義からac_assigned転記
    # inject_related_lessonsはinject_task_modifiers(yaml.dump使用)の後に実行する。
    # yaml.dumpがrelated_lessons+descriptionの_sv書式を破壊するため(inject_ac_versionと同じ理由)。

    local clear_fields clear_tmp
    if [ "${DEPLOY_TASK_DIRECT_YAML_PREINJECTED:-0}" != "1" ]; then
        # role_reminder is intentionally absent. reset_stale_fields already
        # removes the previous task's value before normal/direct publication;
        # clearing it again here erased a caller-supplied --yaml isolation
        # contract and replaced it with the generic reminder.
        clear_fields="engineering_preferences|experiment_first_principle|skill_hint|reports_to_read|context_files|context_hints|report_template|bloom_level|stop_for|never_stop_for|ac_priority|ac_checkpoint|parallel_ok|ninja_weak_points|type"
        clear_tmp=$(mktemp)
        if awk -v fields="$clear_fields" '
        BEGIN { n=split(fields,arr,"|"); for(i=1;i<=n;i++) fset[arr[i]]=1; skip=0; cleared=0 }
        {
            if (match($0, /[^ ]/)) indent = RSTART - 1; else indent = 999
            if (skip) {
                if (indent <= 2 && $0 ~ /^  [a-zA-Z_][a-zA-Z0-9_]*:/) { skip = 0 }
                else { next }
            }
            if (indent == 2 && $0 ~ /^  [a-zA-Z_][a-zA-Z0-9_]*:/) {
                key = $0; sub(/^  /, "", key); sub(/:.*$/, "", key)
                if (key in fset) { skip = 1; cleared++; next }
            }
            print
        }
        END { if (cleared > 0) printf "[FIELD_CLEAR] Cleared %d fields\n", cleared > "/dev/stderr"
              else printf "[FIELD_CLEAR] No fields to clear\n" > "/dev/stderr" }
    ' "$task_file" > "$clear_tmp" 2>/dev/null; then
        if [ -s "$clear_tmp" ]; then
            mv "$clear_tmp" "$task_file"
        else
            rm -f "$clear_tmp"
        fi
        else
            log "WARN: auto-inject field clear failed (non-fatal)"
            rm -f "$clear_tmp"
        fi
    else
        log "direct_mode: preserving preinjected task metadata"
    fi

    if [ "${DEPLOY_TASK_DIRECT_YAML_PREINJECTED:-0}" = "1" ]; then
        log "direct_mode: preinjected task YAML detected; skipping heavy context/lesson/semantic reinjection"
    else
        deploy_task_mutation_phase task_modifiers inject_task_modifiers "$task_file" || true
        inject_session_state_hints "$task_file" || true  # GP-198
        inject_codd_failure_history "$task_file" || true  # GP-201
        inject_engineering_preferences "$task_file" || true
        inject_skill_hint "$task_file" || true

        # related_lessons+description注入はinject_task_modifiers(yaml.dump使用)の後に実行する。
        # yaml.dumpが_sv(シングルクォート)書式を破壊するため。inject_ac_versionと同じ理由。
        # cmd_karo_impl_related_lessons_snapshot_20260727: 同一cmdの再配備で
        # related_lessonsが再抽選され、先に生成済みの報告のlessons_useful評価集合と
        # 食い違ってGATEが無過失の忍者をBLOCKする事象を根治する。resolve前(pre-resolve)に
        # 既にこのCMD_ID向けのrelated_lessonsが存在していた場合は再注入せず、
        # 配備時点の集合を維持する(acceptance_criteriaが同一cmd再配備で上書きされないのと
        # 同じ思想。新規gate/hook/状態ファイルは作らず既存機構を拡張)。
        if [ -n "${CMD_ID:-}" ] && [ "${_DEPLOY_PRE_RESOLVE_PARENT_CMD:-}" = "$CMD_ID" ] && [ "${_DEPLOY_PRE_RESOLVE_RELATED_LESSONS_PRESENT:-0}" = "1" ]; then
            log "related_lessons: same-cmd redeploy detected (parent_cmd=${CMD_ID}) — preserving existing related_lessons, skip re-injection"
        else
            deploy_task_mutation_phase related_lessons inject_related_lessons "$task_file" || handle_yaml_injection_failure "inject_related_lessons" "$task_file" "$ninja_name"
        fi
        inject_workaround_pattern_lessons "$task_file" "$ninja_name" || handle_yaml_injection_failure "inject_workaround_pattern_lessons" "$task_file" "$ninja_name"
        inject_standard_skills "$task_file" || true  # Level5: 全taskに常時使用スキルを明示(cmd_2737)
        inject_model_injection_profile "$task_file" "$ninja_name" || true  # cmd_3727: モデル階層別注入強度
        deploy_task_mutation_phase semantic_context inject_semantic_concepts "$task_file" || true  # Level5
        deploy_task_mutation_phase memory_context inject_memory_db_context "$task_file" || true  # Level5
        inject_causal_links "$task_file" || true      # Level5: 全忍者にcmd origin因果リンクを自動提供(cmd_2822)
        inject_causal_verification_template "$task_file" || true  # Level5: infra変更前の因果確認をCLI非依存で注入
        inject_dm_signal_pf_operation_guardrails "$task_file" || true  # Level5: PF削除/復元/rollback前提知識を自動注入(cmd_3786)
        inject_dm_signal_golden_baseline_contract "$task_file" || true  # Level5: L877巨大golden-baseline二層契約
        inject_dm_signal_canary_rotation_contract "$task_file" || handle_yaml_injection_failure "inject_dm_signal_canary_rotation_contract" "$task_file" "$ninja_name"
        inject_context_hints "$task_file" || true  # Level5: purpose/project/task_typeから必読contextを強制提供
        inject_reflux_commit_contract "$task_file" || handle_yaml_injection_failure "inject_reflux_commit_contract" "$task_file" "$ninja_name"
        inject_production_invariants "$task_file" || true  # Level5: 忍者に本番不変量(PI)自動提供
        inject_checklist_constraints "$task_file" || true  # Level5: checklist隣接Step制約強制注入(cmd_2644)
        inject_growth_loop_defense "$task_file" || true    # Level5: gate/hook関連cmdに防御階層§11を強制注入(cmd_2649)
        inject_experiment_first_principle "$task_file" || true  # Level5: 全taskへ実験ファースト原則を強制注入
        inject_readonly_refs "$task_file" || true           # Level5: command必読/参照専用ファイルをreadonly_refへ源流注入
        inject_ac_version "$task_file" || true
        verify_ac_consistency "$task_file" || true

        # Some optional injectors normalize YAML through Python and can change
        # an AC mapping into a list.  Reassert the direct L4 template after
        # all optional mutations so its fixed dict schema is the final SSOT.
        local final_parent_cmd
        final_parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
        inject_direct_training_template "$task_file" "$final_parent_cmd" || true
    fi

    if [ "${DEPLOY_TASK_DIRECT_YAML_PREINJECTED:-0}" != "1" ]; then
        local pc_file inj_project inj_ids lid
        deploy_task_postcondition_prepare "$task_file"
        pc_file="$DEPLOY_TASK_POSTCOND_FILE"
        if [ -f "$pc_file" ]; then
            inj_project=$(grep '^project=' "$pc_file" | cut -d= -f2)
            inj_ids=$(grep '^injected_ids=' "$pc_file" | cut -d= -f2)
            if [ -n "$inj_ids" ] && [ -n "$inj_project" ]; then
                deploy_task_queue_lesson_scores "$task_file" "$inj_project" "$inj_ids" || true
                if [ "$inj_project" != "infra" ]; then
                    deploy_task_queue_lesson_scores "$task_file" infra "$inj_ids" || true
                fi
                log "injection_count: queued for deferred batch (${inj_ids})"
            fi
        fi
        postcondition_lesson_inject "$task_file" || true
    fi

    if [ "${DEPLOY_TASK_DIRECT_YAML_PREINJECTED:-0}" != "1" ]; then
        inject_reports_to_read "$task_file" || true
        register_blocked_parent_continuation "$task_file" "$ninja_name" || return $?
        inject_context_files "$task_file" || true
        inject_credential_files "$task_file" || true
        inject_target_path_check "$task_file" || true
        inject_context_update "$task_file" || true
        inject_push_allowed "$task_file" || true  # Level5: AC内push検出でpush_allowed自動付与(cmd_3820)
        inject_independent_recon_contract "$task_file" "$ninja_name" || return 1
        inject_role_reminder "$task_file" "$ninja_name" || true
        inject_report_template "$task_file" || true
    fi

    if [ "${DEPLOY_TASK_DIRECT_YAML_PREINJECTED:-0}" != "1" ]; then
        deploy_task_normalize_report_metadata "$task_file" || return 1
        inject_bloom_level "$task_file" || true
        inject_execution_controls "$task_file" || true
        inject_ninja_weak_points "$task_file" "$ninja_name" || handle_yaml_injection_failure "inject_ninja_weak_points" "$task_file" "$ninja_name"
        check_context_freshness "$task_file" || true
    fi

    # This is deliberately after every mutation path, including preinjected
    # YAML and report/context injectors.  A L4 direct-training task is not
    # deployable until its final on-disk AC schema is the canonical mapping.
    local canonical_training_parent_cmd canonical_training_task_type parent_cmd task_type
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" parent_cmd task_type 2>/dev/null)" || true
    canonical_training_parent_cmd="${parent_cmd:-}"
    canonical_training_task_type="${task_type:-normal}"
    if [[ "$canonical_training_parent_cmd" =~ ^cmd_training_L4_ ]] \
        && [ "$canonical_training_task_type" = "normal" ]; then
        inject_direct_training_template "$task_file" "$canonical_training_parent_cmd" || return 1
    fi

    # E3: direct --yaml / --cmd / normal resolveを含む全publication pathの最終形へ
    # ci_fix clean reproduction scaffoldと専用ACを一度だけ注入する。
    inject_ci_fix_clean_repro_contract "$task_file" || return 1

    # Explicit opt-in only; this must remain before final syntax/report publication.
    inject_head_fixed_validation_contract "$task_file" || return 1

    # Level5: investigation tasks receive an executable, bounded code-location
    # path before publication.  Raw recursive grep is intentionally forbidden.
    inject_outcome_neutral_investigation_contract "$task_file" || return 1
    inject_seam_contract "$task_file" || return 1
    inject_code_location_contract "$task_file" || return 1
    inject_scope_contract_fields "$task_file" || return 1

    local task_id parent_cmd project _ac_task_id report_filename
    deploy_task_guard_task_yaml_syntax "post_injection_pre_report_template" "$task_file" "$ninja_name" || return 1
    deploy_task_test_necessity_precheck "$task_file" || return 1

    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" task_id _ac_task_id parent_cmd project report_filename 2>/dev/null)" || true
    # task_id空なら_ac_task_idをfallback(家老が_ac_task_idを直接設定するケース)
    if [ -z "${task_id:-}" ]; then
        task_id="${_ac_task_id:-}"
    fi
    # Ordering marker retained for source-contract tests: the wrapper invokes
    # generate_report_template "$ninja_name" under the report-unit lock.
    deploy_task_report_publication_locked "$ninja_name" "$task_id" "$parent_cmd" "$project" "$task_file" || return $?
    inject_parent_contract "$task_file" "$SCRIPT_DIR/queue/reports/${report_filename:-}" "$ninja_name" \
        || { log "FATAL: parent contract injection failed"; return 1; }
    inject_done_redeploy_hints "$task_file" || true
    log "TASK_MUTATION_SUMMARY report_scans=${DEPLOY_TASK_REPORT_SCAN_COUNT:-0}"
}
deploy_task_ci_red_followup_push_guard() {
    local source_file="${1:-}"
    local task_type="" runs run_status conclusion red_sha followups limit
    [ "${DEPLOY_TASK_SKIP_CI_RED_GUARD:-0}" = "1" ] && return 0
    limit="${DEPLOY_TASK_CI_RED_FOLLOWUP_LIMIT:-2}"

    if [ -n "$source_file" ] && [ -f "$source_file" ]; then
        task_type=$(FIELD_GET_NO_LOG=1 field_get "$source_file" "task_type" "" 2>/dev/null || true)
    fi
    # ci_fix自身はREDを消すための弾なので常に通す。
    [ "${task_type,,}" = "ci_fix" ] && return 0

    runs="${DEPLOY_TASK_CI_RED_JSON:-}"
    if [ -z "$runs" ]; then
        command -v gh >/dev/null 2>&1 || return 0
        runs=$(timeout "${DEPLOY_TASK_GH_TIMEOUT:-8}" gh run list             --repo "${DEPLOY_TASK_CI_REPO:-simokitafresh/multi-agent-shogun}"             --branch main --limit 1             --json status,conclusion,databaseId,headSha 2>/dev/null || true)
        [ -n "$runs" ] || return 0
    fi
    run_status=$(printf '%s' "$runs" | jq -r 'if type=="array" and length>0 then (.[0].status // "completed") else "" end' 2>/dev/null || true)
    # A newer run for the current branch head supersedes the older completed
    # RED as the active CI state.  Let normal work continue while that run is
    # queued/in_progress; its completed verdict will govern the next deploy.
    [ "$run_status" = "completed" ] || return 0
    conclusion=$(printf '%s' "$runs" | jq -r 'if type=="array" and length>0 then (.[0].conclusion // "") else "" end' 2>/dev/null || true)
    [ "$conclusion" = "failure" ] || return 0
    red_sha=$(printf '%s' "$runs" | jq -r 'if type=="array" and length>0 then (.[0].headSha // "") else "" end' 2>/dev/null || true)

    followups="${DEPLOY_TASK_CI_FOLLOWUP_PUSHES:-}"
    if [ -z "$followups" ]; then
        [ -n "$red_sha" ] || return 0
        git -C "$SCRIPT_DIR" rev-parse --verify "${red_sha}^{commit}" >/dev/null 2>&1 || return 0
        followups=$(git -C "$SCRIPT_DIR" rev-list --count "${red_sha}..refs/remotes/origin/main" 2>/dev/null || echo "")
    fi
    [[ "$followups" =~ ^[0-9]+$ ]] || return 0

    if [ "$followups" -gt "$limit" ]; then
        log "BLOCK(ci_red_followup): red_sha=${red_sha:0:9} followup_pushes=${followups} limit=${limit}"
        echo "BLOCK: CI RED(sha=${red_sha:0:9})に対する追いpushが${followups}回(上限${limit}回)。新規配備を停止し、task_type=ci_fixでRED修正へ全リソースを寄せよ。" >&2
        return 1
    fi
    return 0
}

# E3 Level5: ci_fixはclean-CI相当の同一harnessで修正前FAIL→修正後PASSを
# push前に証明する。途中AC/binary_checksへ混入させず、型付きfinal_checkpoint
# として配備する。完成証跡は報告終端gateが一度だけfail-closed検証する。
inject_code_location_contract() {
    local task_file="$1" task_type bloom_level contract
    [ -f "$task_file" ] || return 0
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" task_type bloom_level 2>/dev/null)" || true
    task_type="${task_type,,}"
    bloom_level="${bloom_level,,}"
    if [[ ! "$task_type" =~ ^(recon|scout|focused)$ ]] && [ "$bloom_level" != "focused" ]; then
        return 0
    fi
    contract='Code-locationは `bash scripts/code_locate.sh "QUERY" [PATHSPEC ...]`（追跡対象限定、git grep）を使う。`grep -r`/`grep -R`は禁止。追跡外生成物が必要な場合のみ `bash scripts/code_locate.sh --include-untracked --reason "必要理由" "QUERY" [PATH ...]` を使う（node_modules/.git/.*_worktreesは既定除外）。exit 0=match、1=no match、2以上=実行異常として区別する。'
    yaml_field_set "$task_file" "task" "code_location_contract" "$contract"
}

# Read-only investigation succeeds by resolving the assigned question, not by
# producing the answer the issuer hoped to find.  Keep the authored scope/ACs
# intact for ancestry and review traceability, while making their success
# semantics outcome-neutral at deployment time.  The report gate consumes the
# same typed contract from task_contract_snapshot, so this cannot degrade into
# a worker/reviewer convention.
inject_outcome_neutral_investigation_contract() {
    local task_file="$1" task_type contract
    [ -f "$task_file" ] || return 0
    task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "" 2>/dev/null || true)
    task_type="${task_type,,}"
    case "$task_type" in
        recon|recon2|scout) ;;
        *) return 0 ;;
    esac

    contract='{"version":1,"required":true,"outcome_neutral":true,"success_basis":"assigned_method_completed_with_primary_evidence","discovery_required":false,"allowed_outcomes":["found","zero_found","not_present","external_boundary","unknown_after_exhaustion"],"minimum_primary_evidence":1}'
    yaml_field_set "$task_file" "task" "investigation_contract" "$contract" || return 1
    log "investigation_contract: outcome-neutral contract injected (${task_type})"
}

# Consumer seam work must publish its nine input-contract questions before a
# scout/recon worker starts. Keep the contract nested in investigation_contract
# so the task and immutable report snapshot share one typed source of truth.
inject_seam_contract() {
    local task_file="$1" task_type contract_json
    [ -f "$task_file" ] || return 0
    task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "" 2>/dev/null || true)
    task_type="${task_type,,}"

    contract_json=$(python3 - "$task_file" <<'PY_SEAM_CONTRACT'
import json, re, sys, yaml

path = sys.argv[1]
task = (yaml.safe_load(open(path, encoding="utf-8")) or {}).get("task", {})
task_type = str(task.get("task_type") or "").strip().lower()
if task_type not in {"recon", "recon2", "scout"}:
    raise SystemExit(3)

parts = []
for key in ("title", "purpose", "command", "description", "constraints", "not_in_scope"):
    value = task.get(key)
    if isinstance(value, (list, dict)):
        parts.append(json.dumps(value, ensure_ascii=False, sort_keys=True))
    elif value:
        parts.append(str(value))
for item in task.get("acceptance_criteria") or []:
    if isinstance(item, dict):
        parts.append(str(item.get("description") or item.get("criteria") or ""))
    else:
        parts.append(str(item))
text = " ".join(parts).lower()
trigger = bool(re.search(
    r"cutover|cache|caching|read[ _-]*(reduction|削減|count|回数)|"
    r"consumer|seam|継ぎ目|読み取り削減|読取削減|キャッシュ",
    text,
    re.IGNORECASE,
))

base = task.get("investigation_contract")
if not isinstance(base, dict):
    base = {
        "version": 1,
        "required": True,
        "outcome_neutral": True,
        "success_basis": "assigned_method_completed_with_primary_evidence",
        "discovery_required": False,
        "allowed_outcomes": ["found", "zero_found", "not_present", "external_boundary", "unknown_after_exhaustion"],
        "minimum_primary_evidence": 1,
    }
else:
    base = dict(base)

fields = [
    "primary_payload", "companion_caches", "key_set", "date_domain",
    "empty_behavior", "fallback", "side_effects", "legacy_only_policy",
    "downstream_cardinality",
]
base["seam_contract"] = {
    "required": trigger,
    "fields": {field: "" for field in fields},
    "primary_evidence_fields": fields,
    "minimum_primary_evidence": 9 if trigger else 1,
    "field_guidance": {
        "date_domain": "一次証拠でtarget_date/run境界と、前run終端DB状態(C1 read-once旧行)への履歴依存を確認する",
        "legacy_only_policy": "一次証拠で旧行を許容する条件と、汚染後復元の1回目(1989件逆転・465件残存)および2回目収束full確認のstate dependencyを扱う",
    },
}
if trigger:
    base["minimum_primary_evidence"] = 9
print(json.dumps(base, ensure_ascii=False, separators=(",", ":")))
PY_SEAM_CONTRACT
    ) || {
        [ "$?" -eq 3 ] && return 0
        log "BLOCK: seam_contract generation failed (${task_file})"
        return 1
    }

    yaml_field_set "$task_file" "task" "investigation_contract" "$contract_json" || return 1
    log "seam_contract: injected task_type=${task_type} required=$(python3 -c 'import json,sys; print(str(json.loads(sys.argv[1])["seam_contract"]["required"]).lower())' "$contract_json") fields=9"
}

# cmd_4215: only an explicit boolean declaration may opt a task into fixed-HEAD
# validation.  Normal editing tasks must continue to use the shared worktree.
inject_head_fixed_validation_contract() {
    local task_file="$1" declared contract
    [ -f "$task_file" ] || return 0
    declared=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "head_fixed_validation" "false" 2>/dev/null || true)
    [ "$declared" = "true" ] || return 0

    contract='Capture the current HEAD once, then run `bash scripts/head_fixed_validation.sh <task_yaml>`. The runner creates an isolated detached worktree at that SHA, executes the task-selected runner from that worktree, removes the worktree on every exit path, and fails if a registered or on-disk residue remains. Shared-tree HEAD changes after capture must not alter the validated SHA.'
    yaml_field_set "$task_file" "task" "head_fixed_validation_contract" "$contract"
}

# Direct hotfixes may repair a failed task owned by another ninja.  Validate
# the complete join before publishing the hotfix, then register the dependency
# with wait_reason last as the visibility barrier for ninja_monitor.
register_blocked_parent_continuation() {
    local hotfix_task="$1" current_ninja="$2"
    local task_type parent_cmd fixes blocked_ninja blocked_task configured_ninjas
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$hotfix_task" task_type parent_cmd fixes blocked_parent_ninja blocked_parent_task_id 2>/dev/null)" || true
    task_type="${task_type:-}"; parent_cmd="${parent_cmd:-}"; fixes="${fixes:-}"
    blocked_ninja="${blocked_parent_ninja:-}"; blocked_task="${blocked_parent_task_id:-}"
    [ -n "$fixes$blocked_ninja$blocked_task" ] || return 0
    [ "$task_type" = "hotfix" ] || { echo "BLOCK: blocked-parent continuation requires task_type=hotfix" >&2; return 2; }
    [ -n "$fixes" ] && [ -n "$blocked_ninja" ] && [ -n "$blocked_task" ] || { echo "BLOCK: incomplete blocked-parent reference" >&2; return 2; }
    [ "$blocked_ninja" != "$current_ninja" ] || { echo "BLOCK: blocked-parent self-reference" >&2; return 2; }
    configured_ninjas="$(get_ninja_names)" || { echo "BLOCK: failed to load configured ninja roster" >&2; return 2; }
    case " $configured_ninjas " in
        *" $blocked_ninja "*) ;;
        *) echo "BLOCK: invalid blocked_parent_ninja" >&2; return 2 ;;
    esac
    local parent_file="$SCRIPT_DIR/queue/tasks/${blocked_ninja}.yaml" actual_id actual_status
    [ -f "$parent_file" ] || { echo "BLOCK: blocked parent task file missing" >&2; return 2; }
    actual_id=$(FIELD_GET_NO_LOG=1 field_get "$parent_file" task_id "" 2>/dev/null || true)
    actual_status=$(FIELD_GET_NO_LOG=1 field_get "$parent_file" status "" 2>/dev/null || true)
    [ "$actual_id" = "$blocked_task" ] || { echo "BLOCK: blocked parent task mismatch" >&2; return 2; }
    [ "$actual_status" = "failed" ] || { echo "BLOCK: blocked parent must be failed" >&2; return 2; }
    yaml_field_set "$parent_file" task continuation_task_id "$blocked_task" || return 2
    yaml_field_set "$parent_file" task wait_connected_cmd "$parent_cmd" || return 2
    yaml_field_set "$parent_file" task wait_reason dependency || return 2
    log "DEPENDENCY-CONTINUATION-REGISTER: parent=${blocked_ninja}/${blocked_task} connected=${parent_cmd} fields=3/3"
}

# CI RED startup verification joins the active task to the failed Actions run
# by task_type=ci_fix + ci_run_id.  Reject an incomplete join key while the
# caller-owned source YAML is still the only artifact: no task/report/inbox
# publication has happened at this point.
deploy_task_ci_fix_run_id_precheck() {
    local source_file="$1"
    local result

    local rc
    if result=$(python3 - "$source_file" <<'PY'
import re
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

path = sys.argv[1]
try:
    data = yaml.safe_load(open(path, encoding="utf-8")) or {}
except Exception as exc:
    print(f"yaml_error:{exc}")
    raise SystemExit(2)

task = data.get("task", data)
if not isinstance(task, dict):
    print("task_mapping_missing")
    raise SystemExit(2)

task_type = str(task.get("task_type") or "").strip().lower()
if task_type != "ci_fix":
    print("not_ci_fix")
    raise SystemExit(0)

run_id = task.get("ci_run_id")
value = "" if run_id is None else str(run_id).strip()
if not re.fullmatch(r"[1-9][0-9]*", value):
    print("invalid_ci_run_id")
    raise SystemExit(1)

print(f"ci_fix_run_id={value}")
PY
    ); then
        rc=0
    else
        rc=$?
    fi
    case "$rc" in
        0)
            [ "$result" = "not_ci_fix" ] || log "ci_fix_contract: PASS ${result}"
            return 0
            ;;
        1)
            log "BLOCK: task_type=ci_fix requires ci_run_id as a positive integer before publication"
            echo "BLOCK: task_type=ci_fix requires ci_run_id as a positive integer (>0); missing, empty, zero, or non-numeric values are forbidden." >&2
            return 1
            ;;
        *)
            log "BLOCK: ci_fix contract source parse failed (${result:-unknown})"
            echo "BLOCK: unable to validate ci_fix ci_run_id in ${source_file}: ${result:-unknown}" >&2
            return 1
            ;;
    esac
}

# 歯止め(b) 殿裁可2026-07-25: 同一のCI REDに対する追いpushは2回まで。3回目からは
# 新規配備を止め、RED修正へリソースを寄せる。一次情報は2つだけを使う:
#   (1) CI REDの実態   = gh run list の最新完了run (conclusion/headSha)
#   (2) 追いpush回数   = git rev-list --count <red_head_sha>..origin/main
# gate_metrics.logはrun_idを持たずcmd単位の記録しか残らないため、RED起点からの
# push本数を数えられる唯一の一次情報がgit履歴である(新規台帳を作らない)。

inject_ci_fix_clean_repro_contract() {
    local task_file="$1" task_type
    [ -f "$task_file" ] || return 0
    task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "" 2>/dev/null || true)
    [ "${task_type,,}" = "ci_fix" ] || return 0

    python3 - "$task_file" <<'PY' || return 1
import json, os, re, sys, tempfile, yaml
path = sys.argv[1]
raw = open(path, encoding='utf-8').read()
d = yaml.safe_load(raw) or {}
t = d.get('task', d)
checkpoint = {
    'type': 'ci_fix_clean_repro',
    'required': True,
    'evidence_field': 'ci_fix_clean_repro_evidence',
    'validator': 'deploy_task_ci_fix_clean_repro_evidence_validate',
    'phase': 'terminal_report_gate',
}

def replace_task_field(text, key, value):
    encoded = json.dumps(value, ensure_ascii=False, separators=(',', ':'))
    lines = text.splitlines()
    out, i, replaced = [], 0, False
    while i < len(lines):
        line = lines[i]
        if re.match(r'^  ' + re.escape(key) + r':(?:\s|$)', line):
            out.append('  ' + key + ': ' + encoded); replaced = True; i += 1
            while i < len(lines):
                stripped = lines[i].lstrip(' '); indent = len(lines[i]) - len(stripped)
                if stripped and (indent < 2 or (indent == 2 and not stripped.startswith('- '))): break
                i += 1
            continue
        out.append(line); i += 1
    if not replaced:
        out.append('  ' + key + ': ' + encoded)
    return '\n'.join(out) + '\n'

def remove_task_field(text, key):
    lines = text.splitlines()
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        if re.match(r'^  ' + re.escape(key) + r':(?:\s|$)', line):
            i += 1
            while i < len(lines):
                stripped = lines[i].lstrip(' ')
                indent = len(lines[i]) - len(stripped)
                if stripped and (indent < 2 or (indent == 2 and not stripped.startswith('- '))):
                    break
                i += 1
            continue
        out.append(line)
        i += 1
    return '\n'.join(out) + '\n'

# A retry may start from a task produced by the old AC-based implementation.
# Remove that obsolete contract and its task-local evidence so the report is
# the sole terminal evidence owner for the new typed checkpoint.
raw = remove_task_field(raw, 'ci_fix_clean_repro_evidence')
raw = replace_task_field(raw, 'final_checkpoint', checkpoint)
yaml.safe_load(raw)
fd, tmp = tempfile.mkstemp(prefix=os.path.basename(path)+'.', dir=os.path.dirname(path) or '.')
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as fh: fh.write(raw)
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
    log "inject_ci_fix_clean_repro_contract: typed final_checkpoint injected"
}

deploy_task_ci_fix_clean_repro_evidence_validate() {
    local task_file="$1"
    # Keep the worker-facing helper compatible while sharing the one canonical
    # validator with the terminal report gate.
    PYTHONPATH="$SCRIPT_DIR${PYTHONPATH:+:$PYTHONPATH}" python3 - "$task_file" <<'PY'
import sys, yaml
from scripts.gates.gate_report_format_main import ci_fix_clean_repro_evidence_errors

doc = yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}
task = doc.get('task', doc)
if str(task.get('task_type') or '').strip().lower() != 'ci_fix':
    raise SystemExit(0)
evidence = task.get('ci_fix_clean_repro_evidence')
errors = ci_fix_clean_repro_evidence_errors(evidence)
if errors:
    for error in errors:
        print('BLOCK: ' + error, file=sys.stderr)
    raise SystemExit(1)
if isinstance(evidence, dict) and str(evidence.get('outcome') or '').strip().lower() == 'not_reproducible':
    print('PASS: ci_fix clean repro not_reproducible evidence valid')
else:
    print('PASS: ci_fix clean repro evidence valid')
PY
    return $?
}

# D006 is an unconditional safety boundary.  Reject task sources that require
# signalling an external process before reset_stale_fields can publish the
# source into queue/tasks or create a report/inbox event.  Explanations of the
# prohibition remain valid input; the guard targets executable/imperative
# requirements, not the words themselves.
deploy_task_destructive_signal_precheck() {
    local source_file="$1" cmd_id="${2:-}"
    python3 - "$source_file" "$cmd_id" <<'PY'
import re
import shlex
import sys

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

path, cmd_id = sys.argv[1:3]
try:
    raw = yaml.safe_load(open(path, encoding="utf-8")) or {}
except Exception as exc:
    print(f"BLOCK: destructive signal preflight could not parse source: {exc}", file=sys.stderr)
    raise SystemExit(2)

source = raw.get("commands", raw)
if cmd_id:
    if isinstance(source, dict) and cmd_id in source:
        task = source[cmd_id]
    elif isinstance(source, list):
        task = next((item for item in source if isinstance(item, dict) and item.get("id") == cmd_id), {})
    else:
        task = raw.get("task", raw)
else:
    task = raw.get("task", raw)
if not isinstance(task, dict):
    raise SystemExit(0)

def flatten_acs(value):
    if isinstance(value, dict):
        values = value.values()
    elif isinstance(value, list):
        values = value
    else:
        values = [value]
    out = []
    for value in values:
        if isinstance(value, dict):
            for key in ("description", "command", "check", "criteria", "title"):
                if value.get(key):
                    out.append(str(value[key]))
            for check in value.get("checks", []) if isinstance(value.get("checks"), list) else []:
                out.append(str(check.get("check", "") if isinstance(check, dict) else check))
        elif value:
            out.append(str(value))
    return out

texts = [str(task.get(key) or "") for key in ("purpose", "command")]
texts.extend(flatten_acs(task.get("acceptance_criteria") or task.get("ac") or []))

safe_explanation = re.compile(
    r"D006|禁止|禁則|違反|遮断|BLOCK|ブロック|検出|発火|参照|説明|例示|"
    r"要求.{0,12}(?:場合|なら)|(?:使うな|実行するな|してはならない)", re.I
)
imperative_signal = re.compile(
    r"(?:外部|別|他の|対象)?(?:プロセス|daemon|デーモン|PID|pane|ペイン).{0,30}"
    r"(?:kill|pkill|killall|signal|シグナル|終了させ|停止させ).{0,20}"
    r"(?:実行|送信|行う|せよ|すること|故障注入)", re.I
)
process_kill_fault = re.compile(
    r"(?:process[ _-]?kill|プロセスkill).{0,20}(?:故障注入|実行|行う|せよ)", re.I
)

def has_signal_command(line):
    """Recognize kill-family commands after shell wrappers and their args."""
    try:
        tokens = shlex.split(line, posix=True)
    except ValueError:
        tokens = re.split(r"\s+", line)
    signal_commands = {"kill", "pkill", "killall"}
    wrappers = {"env", "timeout", "command", "nohup", "nice", "setsid"}
    for token in tokens:
        normalized = token.strip(";|&(){}").rsplit("/", 1)[-1].lower()
        if normalized in signal_commands:
            return True
        # Wrapper names are intentionally recognized while scanning through
        # options, durations and VAR=value arguments to the eventual command.
        if normalized in wrappers or token.startswith("-") or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", token):
            continue
    return False

violations = []
for text in texts:
    for line in text.splitlines():
        line = line.strip()
        if not line or safe_explanation.search(line):
            continue
        if has_signal_command(line) or imperative_signal.search(line) or process_kill_fault.search(line):
            violations.append(line)

if violations:
    print("BLOCK: D006違反の外部プロセスsignal要求を配備前に検出。", file=sys.stderr)
    print("positive_rule: phase永続保存後に対象プロセス自身が非0終了するテスト専用failpointを使え。", file=sys.stderr)
    print(f"evidence: {violations[0]}", file=sys.stderr)
    raise SystemExit(2)
PY
}
