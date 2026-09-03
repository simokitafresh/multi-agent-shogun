#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
YAML_SET="${YAML_FIELD_SET_CMD:-$ROOT/scripts/lib/yaml_field_set.sh}"
INBOX_WRITE="${INBOX_WRITE_CMD:-$ROOT/scripts/inbox_write.sh}"

die() { printf 'BLOCK: draft review approval: %s\n' "$*" >&2; exit 2; }

[ "$#" -eq 4 ] || die "usage: $0 <task-yaml> <exact-task-id> <exact-ac-fingerprint> <evidence-message-id>"
task_file="$1"; expected_task_id="$2"; expected_fingerprint="$3"; evidence_id="$4"
[ -f "$task_file" ] || die "task YAML not found: $task_file"
[ -n "$expected_task_id" ] || die "task id is empty"
[ -n "$expected_fingerprint" ] || die "task fingerprint is empty"
[ -n "$evidence_id" ] || die "evidence message id is empty"

# ─── ac_version自動注入(構造バグ根治 2026-08-05): karo_direct draftにac_versionがない場合、
# deploy_task.shの_compute_ac_hashと同一ロジックで自動計算・注入する。
# これにより家老が手動でac_versionを追加する3回繰返しを構造的に防止する。
_current_ac=$(python3 -c "
import yaml, sys
doc = yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}
task = doc.get('task') or doc
print(str(task.get('ac_version') or task.get('ac_fingerprint') or '').strip())
" "$task_file" 2>/dev/null || true)
if [ -z "$_current_ac" ]; then
    # deploy_task.shのinject_ac_versionを呼び出す(source不要、関数を直接利用)
    _computed_ac=$(python3 - "$task_file" <<'ACPY'
import sys, hashlib, yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
task = data.get("task") if isinstance(data, dict) else None
raw_items = (task or {}).get("acceptance_criteria", []) if isinstance(task, dict) else []
# Support both list form ([{id: AC1, description: ...}]) and mapping form
# ({AC1: {description: ...}}) used by karo_direct drafts.
items = raw_items if isinstance(raw_items, list) else list(raw_items.values()) if isinstance(raw_items, dict) else []
values = []
for item in items:
    if not isinstance(item, dict):
        values.append(str(item)); continue
    description = str(item.get("description", "")).strip()
    if description:
        values.append(description); continue
    checks = item.get("checks", [])
    if isinstance(checks, list):
        values.append("|".join(
            str(check.get("check", "")).strip() if isinstance(check, dict) else str(check).strip()
            for check in checks
        ))
    else:
        values.append(str(item.get("check", "")).strip())
import hashlib as _h
sys.stdout.write(_h.md5("|".join(sorted(values)).encode()).hexdigest()[:8])
ACPY
    )
    if [ -n "$_computed_ac" ]; then
        bash "$YAML_SET" "$task_file" task ac_version "$_computed_ac" 2>/dev/null \
            && printf '[draft_review_approval] auto-injected ac_version=%s\n' "$_computed_ac" >&2 \
            || printf '[draft_review_approval] WARN: ac_version auto-inject failed\n' >&2
    fi
fi

lock_key="$(printf '%s' "$(realpath "$task_file")" | sha256sum | cut -c1-32)"
exec 9>"${TMPDIR:-/tmp}/draft-review-approval-${lock_key}.lock"
flock -w 30 9 || die "approval lock timeout"

inspection="$(python3 - "$task_file" "$expected_task_id" "$expected_fingerprint" "$evidence_id" <<'PY'
import json, sys, yaml
path, expected_id, expected_fp, evidence = sys.argv[1:]
doc = yaml.safe_load(open(path, encoding="utf-8")) or {}
task = doc.get("task") or doc
actual_id = str(task.get("task_id") or task.get("_ac_task_id") or "").strip()
actual_fp = str(task.get("ac_version") or task.get("ac_fingerprint") or "").strip()
status = str(task.get("status") or "").strip().lower()
if actual_id != expected_id:
    raise SystemExit("task id mismatch")
if actual_fp != expected_fp:
    raise SystemExit("task fingerprint mismatch")
if status not in {"assigned", "acknowledged", "in_progress"}:
    raise SystemExit(f"task status must be assigned or acknowledged, got {status or '<empty>'}")
wanted = {"reviewer":"gunshi", "result":"LGTM", "task_id":expected_id,
          "task_fingerprint":expected_fp, "evidence_message_id":evidence}
current = task.get("pre_implementation_review")
if current is not None and current != wanted:
    raise SystemExit("different pre_implementation_review receipt already exists")
print(json.dumps({"mode":"idempotent" if current == wanted else "write", "receipt":wanted}, ensure_ascii=False, separators=(",",":")))
PY
)" || die "task contract validation failed"

mode="$(jq -r .mode <<<"$inspection")"
receipt="$(jq -c .receipt <<<"$inspection")"
if [ "$mode" = idempotent ]; then
    printf 'APPROVAL_IDEMPOTENT task=%s fingerprint=%s evidence=%s\n' "$expected_task_id" "$expected_fingerprint" "$evidence_id"
    exit 0
fi

before_sha="$(sha256sum "$task_file" | awk '{print $1}')"
if ! bash "$YAML_SET" "$task_file" task pre_implementation_review "$receipt"; then
    [ "$(sha256sum "$task_file" | awk '{print $1}')" = "$before_sha" ] || die "receipt writer failed after mutating task"
    die "receipt writer failed with task unchanged"
fi

python3 - "$task_file" "$receipt" <<'PY' || die "receipt post-write verification failed"
import json, sys, yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
task = doc.get("task") or doc
if task.get("pre_implementation_review") != json.loads(sys.argv[2]):
    raise SystemExit(1)
PY

# inbox_write requires the commander identity envelope for review_result to karo
# (task_id=commander_directive subject_task_id=<task> parent_cmd=<cmd>). Derive
# parent_cmd from the task itself so the receipt and the notice bind one identity.
parent_cmd=$(python3 -c 'import sys,yaml; d=yaml.safe_load(open(sys.argv[1],encoding="utf-8")) or {}; t=d.get("task") or d; print(str(t.get("parent_cmd") or "").strip())' "$task_file" 2>/dev/null || true)
notice="${expected_task_id} draft review verdict: APPROVE; task_fingerprint: ${expected_fingerprint}; evidence_message_id: ${evidence_id}; receipt_recorded: true"
[ -z "$parent_cmd" ] || notice="${notice} task_id=commander_directive subject_task_id=${expected_task_id} parent_cmd=${parent_cmd}"
bash "$INBOX_WRITE" karo "$notice" review_result gunshi notify_karo >/dev/null || die "receipt recorded but review_result notification failed"
printf 'APPROVAL_RECORDED task=%s fingerprint=%s evidence=%s\n' "$expected_task_id" "$expected_fingerprint" "$evidence_id"
