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
if status not in {"assigned", "acknowledged"}:
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

notice="${expected_task_id} draft review verdict: APPROVE; task_fingerprint: ${expected_fingerprint}; evidence_message_id: ${evidence_id}; receipt_recorded: true"
bash "$INBOX_WRITE" karo "$notice" review_result gunshi notify_karo >/dev/null || die "receipt recorded but review_result notification failed"
printf 'APPROVAL_RECORDED task=%s fingerprint=%s evidence=%s\n' "$expected_task_id" "$expected_fingerprint" "$evidence_id"
